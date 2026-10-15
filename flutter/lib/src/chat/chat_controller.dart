import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../myts/api.dart';
import '../myts/contact_store.dart';
import '../myts/controller.dart';
import 'chat_client.dart';
import 'chat_models.dart';

enum ChatPhase {
  /// The account key is not in memory; the password is needed.
  locked,
  unlocking,

  /// Unlocked and talking to the chat server for the first time.
  connecting,
  ready,
}

enum ChatError {
  wrongPassword,

  /// The password saved on this device no longer unlocks the account.
  savedPasswordRejected,
  network,
  authentication,
  rateLimited,
  server,
  invalid,
  loginUncertain,
  notLoggedIn,
  notSendable,
  contacts,

  /// Encrypted send: no device of the contact could receive the room key.
  noRecipients,

  /// Encrypted send in a room that is not a one-to-one conversation.
  unsupportedRoom,

  /// The engine's session storage is full.
  limit,
}

/// A one-off remark about a delivered action, shown once and then cleared.
enum ChatNotice {
  /// A device of the contact changed its keys and was left out of the send.
  deviceChanged,
}

class ChatState {
  final ChatPhase phase;
  final ChatError? error;
  final int? httpStatus;
  final ChatNotice? notice;
  final bool refreshing;
  final ChatAccount account;
  final List<ChatRoom> rooms;
  final Map<String, List<ChatMessage>> messages;
  final Map<String, List<PendingMessage>> pending;
  final List<StoredContact> contacts;

  const ChatState({
    this.phase = ChatPhase.locked,
    this.error,
    this.httpStatus,
    this.notice,
    this.refreshing = false,
    this.account = const ChatAccount(),
    this.rooms = const [],
    this.messages = const {},
    this.pending = const {},
    this.contacts = const [],
  });

  bool get ready => phase == ChatPhase.ready;

  ChatState copyWith({
    ChatPhase? phase,
    Object? error = _keep,
    Object? httpStatus = _keep,
    Object? notice = _keep,
    bool? refreshing,
    ChatAccount? account,
    List<ChatRoom>? rooms,
    Map<String, List<ChatMessage>>? messages,
    Map<String, List<PendingMessage>>? pending,
    List<StoredContact>? contacts,
  }) => ChatState(
    phase: phase ?? this.phase,
    error: identical(error, _keep) ? this.error : error as ChatError?,
    httpStatus: identical(httpStatus, _keep)
        ? this.httpStatus
        : httpStatus as int?,
    notice: identical(notice, _keep) ? this.notice : notice as ChatNotice?,
    refreshing: refreshing ?? this.refreshing,
    account: account ?? this.account,
    rooms: rooms ?? this.rooms,
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    contacts: contacts ?? this.contacts,
  );
}

const Object _keep = Object();

/// Overridable in tests.
final chatClientOpenerProvider =
    Provider<
      Future<ChatClient> Function(String password, bool allowOwnEmpty)
    >((ref) {
      return (password, allowOwnEmpty) => ChatClient.open(
        api: ref.read(myTsApiProvider),
        sessions: ref.read(myTsSessionStoreProvider),
        password: password,
        allowOwnEmpty: allowOwnEmpty,
      );
    });

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  ChatClient? _client;
  Timer? _listTimer;
  Timer? _roomTimer;
  String? _openRoom;
  bool _busy = false;
  int _generation = 0;
  String? _cachedHost;
  final _random = Random.secure();

  @override
  ChatState build() {
    // Leaving the myTS account locks and wipes the in-memory chat.
    ref.listen(myTsProvider.select((s) => s.status), (_, status) {
      if (status != MyTsStatus.signedIn) lock();
    });
    ref.onDispose(_teardown);
    return const ChatState();
  }

  ChatError _classify(Object e) {
    if (e is ChatException) {
      return switch (e.failure) {
        ChatFailure.network => ChatError.network,
        ChatFailure.authentication => ChatError.authentication,
        ChatFailure.rateLimited => ChatError.rateLimited,
        ChatFailure.http => ChatError.server,
        ChatFailure.invalid => ChatError.invalid,
        ChatFailure.loginUncertain => ChatError.loginUncertain,
        ChatFailure.notLoggedIn => ChatError.notLoggedIn,
        ChatFailure.notSendable => ChatError.notSendable,
        ChatFailure.noRecipients => ChatError.noRecipients,
        ChatFailure.unsupportedRoom => ChatError.unsupportedRoom,
        ChatFailure.limit => ChatError.limit,
        // The UI asks first; if it ever gets here the send simply didn't happen.
        ChatFailure.consentRequired => ChatError.notSendable,
      };
    }
    if (e is SocketException ||
        e is TlsException ||
        e is TimeoutException ||
        e is HttpException) {
      return ChatError.network;
    }
    return ChatError.invalid;
  }

  void _fail(Object e) {
    state = state.copyWith(
      error: _classify(e),
      httpStatus: e is ChatException ? e.status : null,
    );
  }

  /// Explicit user action from the error banner.
  Future<void> retryLogin() async {
    final client = _client;
    if (client == null || _busy) return;
    _busy = true;
    state = state.copyWith(refreshing: true, error: null);
    try {
      await client.retryLogin();
      await _pullView();
      unawaited(_refreshPeople());
    } catch (e) {
      if (ref.mounted) _fail(e);
    } finally {
      _busy = false;
      if (ref.mounted) state = state.copyWith(refreshing: false);
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(error: null);
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(notice: null);
  }

  /// Unlocks with the password saved on this device, if there is one. Does
  /// nothing otherwise, so the caller can fall back to the password form.
  Future<void> unlockWithSaved() async {
    if (state.phase != ChatPhase.locked) return;
    final String? saved;
    try {
      saved = await ref.read(myTsSessionStoreProvider).loadPassword();
    } catch (_) {
      return; // Unreadable secure storage: ask for the password instead.
    }
    if (saved == null || !ref.mounted || state.phase != ChatPhase.locked) return;
    await unlock(saved, fromSaved: true);
  }

  /// Unlocks with the account password, then connects. A password typed by
  /// the user is kept in secure storage afterwards unless they opted out;
  /// one that came from storage and fails is forgotten.
  Future<void> unlock(
    String password, {
    bool allowOwnEmpty = false,
    bool fromSaved = false,
  }) async {
    if (state.phase == ChatPhase.unlocking ||
        state.phase == ChatPhase.connecting ||
        state.ready) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: ChatPhase.unlocking, error: null);
    final ChatClient client;
    try {
      client = await ref.read(chatClientOpenerProvider)(
        password,
        allowOwnEmpty,
      );
    } on FormatException catch (e) {
      if (generation == _generation) {
        final wrong = e.message == 'chat unlock failed';
        if (wrong && fromSaved) {
          await ref.read(rememberPasswordProvider.notifier).forget();
        }
        if (!ref.mounted) return;
        state = state.copyWith(
          phase: ChatPhase.locked,
          error: !wrong
              ? ChatError.invalid
              : fromSaved
              ? ChatError.savedPasswordRejected
              : ChatError.wrongPassword,
        );
      }
      return;
    } catch (e) {
      if (generation == _generation) {
        state = state.copyWith(phase: ChatPhase.locked, error: _classify(e));
      }
      return;
    }
    if (generation != _generation || !ref.mounted) {
      client.close();
      return;
    }
    _client = client;
    state = state.copyWith(phase: ChatPhase.connecting);
    if (!fromSaved) {
      try {
        await ref.read(rememberPasswordProvider.notifier).remember(password);
      } catch (_) {
        // Not saving is harmless: the password is simply asked again.
      }
    }
    await _loadContactsFromStore();
    try {
      await client.connect();
    } catch (e) {
      // Stay unlocked: the cached conversations are still readable offline.
      _fail(e);
    }
    if (generation != _generation || !ref.mounted) return;
    await _pullView();
    state = state.copyWith(phase: ChatPhase.ready);
    unawaited(refreshContacts());
    unawaited(_refreshPeople());
  }

  /// Forgets the unlocked key and every in-memory conversation. Stored data
  /// stays sealed on the device.
  void lock() {
    _generation++;
    _teardown();
    if (ref.mounted) state = const ChatState();
  }

  void _teardown() {
    _listTimer?.cancel();
    _roomTimer?.cancel();
    _listTimer = _roomTimer = null;
    _openRoom = null;
    _client?.close();
    _client = null;
  }

  Future<void> _loadContactsFromStore() async {
    try {
      final owner = await ref.read(myTsSessionStoreProvider).load();
      if (owner == null) return;
      final snap = await ref.read(contactStoreProvider).load(owner.email);
      if (snap != null && ref.mounted) {
        _cachedHost = snap.chatHost;
        state = state.copyWith(contacts: snap.contacts);
      }
    } catch (_) {
      // An unreadable roster cache is not fatal; it is reloaded from the cloud.
    }
  }

  Future<void> _pullView([String room = '']) async {
    final client = _client;
    if (client == null) return;
    final view = await client.view(room);
    if (!ref.mounted || _client != client) return;
    final account = ChatAccount.fromJson(
      (view['account'] as Map).cast<String, dynamic>(),
    );
    var next = state.copyWith(account: account);
    if (room.isEmpty) {
      final rooms = [
        for (final r in view['rooms'] as List)
          ChatRoom.fromJson((r as Map).cast<String, dynamic>()),
      ]..sort((a, b) => b.lastTs.compareTo(a.lastTs));
      next = next.copyWith(rooms: rooms);
    } else {
      final list = [
        for (final m in view['messages'] as List)
          ChatMessage.fromJson((m as Map).cast<String, dynamic>()),
      ];
      next = next.copyWith(messages: {...state.messages, room: list});
    }
    state = next;
  }

  /// Runs a user-triggered action, surfacing failures as [ChatState.error].
  Future<bool> _run(Future<void> Function(ChatClient c) op) async {
    final client = _client;
    if (client == null) return false;
    try {
      await op(client);
      return true;
    } catch (e) {
      if (ref.mounted) _fail(e);
      return false;
    }
  }

  // --- conversation list ---------------------------------------------------

  /// Visible chat screen: keeps the list fresh. Pass false when it is hidden.
  void setForeground(bool visible) {
    _listTimer?.cancel();
    _listTimer = null;
    if (!visible) return;
    _listTimer = Timer.periodic(const Duration(seconds: 25), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy || !state.ready) return;
    _busy = true;
    state = state.copyWith(refreshing: true);
    try {
      final ok = await _run((c) => c.refresh());
      if (ok) {
        state = state.copyWith(error: null);
        await _pullView();
        if (_openRoom != null) await _pullView(_openRoom!);
        unawaited(_refreshPeople());
      }
    } finally {
      _busy = false;
      if (ref.mounted) state = state.copyWith(refreshing: false);
    }
  }

  Future<void> _refreshPeople() async {
    final users = <String>{
      for (final c in state.contacts)
        if (c.matrixId.isNotEmpty) c.matrixId,
      for (final r in state.rooms)
        if (r.peer.isNotEmpty) r.peer,
    };
    final client = _client;
    if (client == null) return;
    try {
      await client.refreshPeople(users);
      await _pullView();
    } catch (_) {
      // Presence is decoration; it never raises an error banner.
    }
  }

  Future<void> acceptInvite(String room) async {
    if (await _run((c) => c.acceptInvite(room))) {
      await _run((c) => c.refresh());
      await _pullView();
    }
  }

  Future<void> leaveRoom(String room) async {
    if (await _run((c) => c.leave(room))) {
      await _pullView();
      if (ref.mounted) {
        state = state.copyWith(
          messages: {...state.messages}..remove(room),
          pending: {...state.pending}..remove(room),
        );
      }
    }
  }

  // --- one conversation ----------------------------------------------------

  /// Called when a conversation opens; starts its faster poll.
  Future<void> openRoom(String room) async {
    _openRoom = room;
    _roomTimer?.cancel();
    _roomTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollRoom());
    if (await _run((c) => c.loadMessages(room))) await _pullView(room);
    await _pullView();
  }

  void closeRoom(String room) {
    if (_openRoom != room) return;
    _openRoom = null;
    _roomTimer?.cancel();
    _roomTimer = null;
  }

  Future<void> _pollRoom() async {
    final room = _openRoom;
    final client = _client;
    if (room == null || client == null || _busy) return;
    _busy = true;
    try {
      await client.poll(room);
      await _pullView(room);
    } catch (_) {
      // Transient poll failures are not worth a banner.
    } finally {
      _busy = false;
    }
  }

  Future<void> loadOlder(String room) async {
    if (await _run((c) => c.loadMessages(room, older: true))) {
      await _pullView(room);
    }
  }

  String _txn() {
    final bytes = Uint8List.fromList(
      List.generate(9, (_) => _random.nextInt(256)),
    );
    final id = base64Url.encode(bytes).replaceAll('-', 'a').replaceAll('=', '');
    return 'ts6d_$id';
  }

  void _setPending(String room, List<PendingMessage> list) {
    final pending = {...state.pending};
    if (list.isEmpty) {
      pending.remove(room);
    } else {
      pending[room] = list;
    }
    state = state.copyWith(pending: pending);
  }

  Future<void> send(String room, String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _client == null) return;
    final message = PendingMessage(_txn(), clean);
    _setPending(room, [...?state.pending[room], message]);
    await _deliver(room, message);
  }

  Future<void> retry(String room, String txn) async {
    final list = state.pending[room] ?? const [];
    final message = list.where((m) => m.txn == txn).firstOrNull;
    if (message == null) return;
    _setPending(room, [
      for (final m in list) m.txn == txn ? m.copyWith(failed: false) : m,
    ]);
    await _deliver(room, message);
  }

  void discard(String room, String txn) => _setPending(room, [
    for (final m in state.pending[room] ?? const <PendingMessage>[])
      if (m.txn != txn) m,
  ]);

  /// True when sending to [room] would publish this phone's chat device keys for
  /// the first time and the user has not agreed yet. An unreadable consent flag
  /// counts as "not agreed": the user is simply asked again.
  Future<bool> needsEncryptionConsent(String room) async {
    final client = _client;
    final info = state.rooms.where((r) => r.id == room).firstOrNull;
    if (client == null || info?.encrypted != true) return false;
    try {
      return !await client.hasEncryptionConsent();
    } catch (_) {
      return true;
    }
  }

  /// Remembers the user's agreement; false if it could not be stored, in which
  /// case nothing may be sent.
  Future<bool> grantEncryptionConsent() async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.grantEncryptionConsent();
      return true;
    } catch (_) {
      if (ref.mounted) state = state.copyWith(error: ChatError.invalid);
      return false;
    }
  }

  Future<void> _deliver(String room, PendingMessage message) async {
    final client = _client;
    if (client == null) return;
    try {
      // The same transaction ID makes a retry idempotent on the server.
      final warnings = await client.send(room, message.text, message.txn);
      if (warnings.contains('device_changed') && ref.mounted) {
        state = state.copyWith(notice: ChatNotice.deviceChanged);
      }
      discard(room, message.txn);
      await _pullView(room);
      await _pullView();
    } catch (e) {
      if (!ref.mounted) return;
      _setPending(room, [
        for (final m in state.pending[room] ?? const <PendingMessage>[])
          m.txn == message.txn ? m.copyWith(failed: true) : m,
      ]);
      _fail(e);
    }
  }

  // --- profile -------------------------------------------------------------

  Future<void> setPresence(int presence, String status) async {
    if (await _run((c) => c.setPresence(presence, status))) {
      await _pullView();
    }
  }

  Future<void> setDisplayName(String name) async {
    if (await _run((c) => c.setDisplayName(name))) await _pullView();
  }

  // --- contacts and new chats ---------------------------------------------

  /// Existing direct room with [matrixId], if any.
  String? directRoomWith(String matrixId) {
    final known = state.account.direct[matrixId] ?? const <String>[];
    final ids = {for (final r in state.rooms) r.id};
    for (final room in known) {
      if (ids.contains(room)) return room;
    }
    return state.rooms.where((r) => r.peer == matrixId).firstOrNull?.id;
  }

  /// Creates a new unencrypted direct room; the UI must have warned the user.
  Future<String?> startDirect(String matrixId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final room = await client.startDirect(matrixId);
      await _pullView();
      return room;
    } catch (e) {
      if (ref.mounted) _fail(e);
      return null;
    }
  }

  Future<void> refreshContacts() async {
    try {
      final owner = await ref.read(myTsSessionStoreProvider).load();
      if (owner == null) return;
      final api = ref.read(myTsApiProvider);
      final remote = await api.contacts(owner.session);
      final contacts = [
        for (final c in remote) StoredContact(c.identifier, c.note, c.matrixId),
      ];
      final current = await ref.read(myTsSessionStoreProvider).load();
      if (!ref.mounted || current?.session != owner.session) return;
      await ref
          .read(contactStoreProvider)
          .save(
            owner.email,
            ContactSnapshot(
              contacts,
              state.account.host.isEmpty ? _cachedHost : state.account.host,
            ),
          );
      state = state.copyWith(contacts: contacts);
    } catch (_) {
      // Keep the cached roster; the contacts tab offers a manual retry.
      if (ref.mounted && state.contacts.isEmpty) {
        state = state.copyWith(error: ChatError.contacts);
      }
    }
  }

  Future<bool> _editContact(
    Future<void> Function(MyTsApi api, String session) op,
  ) async {
    try {
      final owner = await ref.read(myTsSessionStoreProvider).load();
      if (owner == null) return false;
      await op(ref.read(myTsApiProvider), owner.session);
      await refreshContacts();
      return true;
    } catch (_) {
      if (ref.mounted) state = state.copyWith(error: ChatError.contacts);
      return false;
    }
  }

  Future<bool> saveContact(String matrixId, String note) =>
      _editContact((api, session) => api.updateContact(session, matrixId, note));

  Future<bool> removeContact(String matrixId) =>
      _editContact((api, session) => api.removeContact(session, matrixId));

  /// Session needed by the avatar loader.
  Future<String?> sessionToken() async =>
      (await ref.read(myTsSessionStoreProvider).load())?.session;
}
