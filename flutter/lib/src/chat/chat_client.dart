import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import '../myts/api.dart';
import '../myts/public_https.dart';
import '../myts/session_store.dart';
import '../rust/myts.dart' as rs;

/// One account's authenticated-encrypted Rust snapshot, additionally protected by
/// platform secure storage. Never put this in preferences or a shared cache.
class ChatStore {
  final MyTsSecureBackend backend;
  ChatStore([MyTsSecureBackend? backend])
    : backend = backend ?? const FlutterMyTsSecureBackend();

  String _digest(String account) {
    if (account.isEmpty) throw const FormatException('missing chat owner');
    return sha256.convert(utf8.encode(account)).toString();
  }

  // The key predates the chat UI and keeps existing history snapshots readable.
  String _key(String account) => 'myts_history_v1_${_digest(account)}';

  // Next to the snapshot, not inside it: the Rust engine never sees it.
  String _consentKey(String account) => 'myts_chat_e2ee_v1_${_digest(account)}';

  /// The user agreed to publish this phone's chat device keys and to share room
  /// keys with every device of the people in a conversation.
  Future<bool> hasEncryptionConsent(String account) async =>
      await backend.read(_consentKey(account)) == '1';

  Future<void> grantEncryptionConsent(String account) =>
      backend.write(_consentKey(account), '1');

  /// Consent belongs to the stored chat device. When the snapshot is gone the
  /// next login creates another device, which the user must agree to again.
  Future<void> clearEncryptionConsent(String account) =>
      backend.delete(_consentKey(account));

  Future<Uint8List> load(String account) async {
    final raw = await backend.read(_key(account));
    if (raw == null) return Uint8List(0);
    if (raw.isEmpty || raw.length > 12 * 1024 * 1024) {
      throw const FormatException('invalid chat storage');
    }
    return base64Decode(raw);
  }

  Future<void> save(String account, Uint8List snapshot) async {
    if (snapshot.isEmpty || snapshot.length > 8 * 1024 * 1024) {
      throw const FormatException('invalid chat snapshot');
    }
    // A single replacement contains token, receive keys, events and replay state.
    await backend.write(_key(account), base64Encode(snapshot));
  }
}

enum ChatFailure {
  /// The device could not reach the chat server (offline, TLS, timeout).
  network,

  /// The stored Matrix token was rejected. No new device is ever created
  /// automatically.
  authentication,

  /// HTTP 429.
  rateLimited,

  /// Any other HTTP status; see [ChatException.status].
  http,

  /// A reply or an argument failed validation.
  invalid,

  /// A previous login attempt may or may not have created a device.
  loginUncertain,

  /// There is no stored token: the chat login has not completed.
  notLoggedIn,

  /// The send was refused locally (unknown room, or a plaintext send refused).
  notSendable,

  /// No device of the contact could be given the room key.
  noRecipients,

  /// An encrypted room without a single peer: only direct rooms are supported.
  unsupportedRoom,

  /// The engine's session storage is full.
  limit,

  /// The user has not agreed to publish this phone's chat device keys.
  consentRequired,
}

class ChatException implements Exception {
  final ChatFailure failure;
  final int? status;
  const ChatException(this.failure, [this.status]);
  @override
  String toString() => 'ChatException(${failure.name}, $status)';
}

/// Matrix account chat. Every protocol decision is in the Rust engine; this class
/// serializes the operations, performs the TLS-only HTTP exchange and commits the
/// sealed snapshot after each accepted reply.
class ChatClient {
  final MyTsApi api;
  final MyTsSessionStore sessions;
  final ChatStore store;
  final MyTsStoredSession owner;
  final rs.MyTsAccountKey _key;
  final rs.MyTsHistory _history;
  final Future<MyTsHttpResponse> Function(rs.MyTsHistoryRequest, String) _http;
  final Map<String, dynamic> Function(Map<String, dynamic> plan)? _planHook;
  bool _closed = false;
  Future<void> _tail = Future.value();

  ChatClient._(
    this.api,
    this.sessions,
    this.store,
    this.owner,
    this._key,
    this._history,
    this._http,
    this._planHook,
  );

  /// Unlocks the account key with [password] and opens the stored state. No
  /// Matrix request is made.
  static Future<ChatClient> open({
    required MyTsApi api,
    required MyTsSessionStore sessions,
    required String password,
    bool allowOwnEmpty = false,
    ChatStore? store,
    Future<MyTsHttpResponse> Function(rs.MyTsHistoryRequest, String)? http,
    @visibleForTesting
    Map<String, dynamic> Function(Map<String, dynamic> plan)? planHook,
  }) async {
    final owner = await sessions.load();
    if (owner == null || owner.uuid.isEmpty) {
      throw const FormatException('chat account unavailable');
    }
    final key = await api.unlockAccountKey(
      email: owner.email,
      password: password,
      wrappedKey: owner.wrappedKey,
    );
    if (key == null) throw const FormatException('chat unlock failed');
    final storage = store ?? ChatStore();
    try {
      final snapshot = await storage.load(owner.uuid);
      if (snapshot.isEmpty) await storage.clearEncryptionConsent(owner.uuid);
      final config = await api.historyConfig(owner.session);
      final history = await rs.myTsHistoryOpen(
        key: key,
        account: owner.uuid,
        configBody: config,
        snapshot: snapshot,
        allowOwnEmpty: allowOwnEmpty,
      );
      final client = ChatClient._(
        api,
        sessions,
        storage,
        owner,
        key,
        history,
        http ?? matrixExchange,
        planHook,
      );
      try {
        await client._ensureCurrent();
        await client._save();
        return client;
      } catch (_) {
        history.dispose();
        rethrow;
      }
    } catch (_) {
      key.dispose();
      rethrow;
    }
  }

  /// Runs [op] after every earlier operation: the Rust state is one mutable
  /// document and a poll must never interleave with a send.
  Future<T> serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _ensureCurrent() async {
    final current = await sessions.load();
    if (_closed ||
        current?.uuid != owner.uuid ||
        current?.session != owner.session) {
      throw const FormatException('chat account changed');
    }
  }

  Future<void> _save() async {
    await _ensureCurrent();
    await store.save(
      owner.uuid,
      await rs.myTsHistorySnapshot(history: _history),
    );
  }

  /// Display data. Replay bookkeeping from decrypting is committed before the
  /// caller can show any newly decrypted message.
  Future<Map<String, dynamic>> view([String room = '']) => serial(() async {
    await _ensureCurrent();
    final view =
        jsonDecode(await rs.myTsHistoryView(history: _history, room: room))
            as Map<String, dynamic>;
    await _save();
    return view;
  });

  /// One Matrix call: build in Rust, exchange, validate in Rust, seal.
  Future<void> _call(
    String action, [
    Map<String, Object?> args = const {},
    bool Function(int status)? tolerate,
  ]) async {
    await _ensureCurrent();
    final encoded = jsonEncode(args);
    final rs.MyTsHistoryRequest request;
    try {
      request = await rs.myTsHistoryRequest(
        history: _history,
        action: action,
        args: encoded,
      );
    } catch (e) {
      throw _classifyLocal(e, action);
    }
    // Whatever the request just changed in the engine (the login intent, fresh
    // keys, a ratchet step, a built event) is durable before it leaves: an
    // uncertain outcome must never create another device or reuse a Megolm index.
    if (request.persist) await _save();
    final MyTsHttpResponse response;
    try {
      response = await _http(request, action);
    } on SocketException {
      if (kDebugMode) debugPrint('chat: $action -> network error');
      throw const ChatException(ChatFailure.network);
    } on TlsException {
      throw const ChatException(ChatFailure.network);
    } on TimeoutException {
      throw const ChatException(ChatFailure.network);
    } on HttpException {
      throw const ChatException(ChatFailure.network);
    }
    if (kDebugMode) {
      // Action and status only: never URLs, headers or bodies.
      debugPrint('chat: $action -> HTTP ${response.status}');
    }
    await _ensureCurrent();
    var body = response.body;
    if (response.status != 200) {
      if (tolerate != null && tolerate(response.status)) {
        body = Uint8List.fromList(utf8.encode('{}'));
      } else {
        throw _classifyHttp(response.status);
      }
    }
    try {
      await rs.myTsHistoryAccept(
        history: _history,
        action: action,
        args: encoded,
        body: body,
      );
    } catch (_) {
      throw const ChatException(ChatFailure.invalid);
    }
    await _save();
  }

  ChatException _classifyLocal(Object e, String action) {
    final text = e.toString();
    if (text.contains('chat:login_uncertain')) {
      return const ChatException(ChatFailure.loginUncertain);
    }
    if (text.contains('chat:not_logged_in')) {
      return const ChatException(ChatFailure.notLoggedIn);
    }
    if (text.contains('chat:authentication')) {
      return const ChatException(ChatFailure.authentication);
    }
    if (action == 'send') return const ChatException(ChatFailure.notSendable);
    return const ChatException(ChatFailure.invalid);
  }

  ChatException _classifyHttp(int status) => switch (status) {
    401 => const ChatException(ChatFailure.authentication),
    429 => const ChatException(ChatFailure.rateLimited),
    _ => ChatException(ChatFailure.http, status),
  };

  /// Explicit connection: logs in only when there is no stored token, then loads
  /// everything the lists need.
  Future<void> connect() => serial(() async {
    final status =
        jsonDecode(await rs.myTsHistoryStatus(history: _history)) as Map;
    if (status['authenticated'] != true) await _call('login');
    await _refreshAll();
  });

  /// User-confirmed retry after an uncertain login. The Matrix device ID is kept,
  /// so even if the first attempt reached the server no second device appears.
  Future<void> retryLogin() => serial(() async {
    await rs.myTsHistoryAllowLoginRetry(history: _history);
    await _save();
    await _call('login');
    await _refreshAll();
  });

  Future<void> refresh() => serial(_refreshAll);

  Future<void> _refreshAll() async {
    await _call('whoami');
    await _call('rooms');
    // These are enrichments: a failure must not hide the cached conversations.
    await _soft(() => _call('invites'));
    await _soft(() => _call('direct', const {}, (s) => s == 404));
    final listed = await _roomIds();
    for (final room in listed.take(40)) {
      await _soft(() => _call('state', {'room': room}));
    }
    for (final room in listed.take(20)) {
      await _soft(() => _call('messages', {'room': room, 'limit': 20}));
    }
  }

  Future<List<String>> _roomIds() => rs.myTsHistoryRoomIds(history: _history);

  Future<void> _soft(Future<void> Function() op) async {
    try {
      await op();
    } on ChatException catch (e) {
      // Authentication problems are real; everything else is an enrichment miss.
      if (e.failure == ChatFailure.authentication) rethrow;
    }
  }

  /// Newest page, or the next older one. New cloud keys are fetched for the
  /// sessions this page needs (bounded, exact pairs, no enumeration).
  Future<void> loadMessages(String room, {bool older = false}) =>
      serial(() async {
        await _call('messages', {'room': room, 'older': older});
        final current =
            jsonDecode(await rs.myTsHistoryView(history: _history, room: room))
                as Map<String, dynamic>;
        for (final session in (current['missing'] as List).take(12)) {
          await _ensureCurrent();
          try {
            final request = await rs.myTsHistoryCloudRequest(
              history: _history,
              session: owner.session,
              room: room,
              groupSession: session as String,
            );
            final response = await api.historyCloud(request);
            await _ensureCurrent();
            await rs.myTsHistoryAcceptCloud(
              history: _history,
              key: _key,
              room: room,
              groupSession: session,
              body: response,
            );
            await _save();
          } catch (_) {
            // The ciphertext stays; the message is shown as unavailable.
          }
        }
      });

  /// Fetches the newest page quietly; used by the open conversation's poll.
  Future<void> poll(String room) =>
      serial(() => _call('messages', {'room': room, 'limit': 40}));

  /// The user agreed to publish this phone's chat device keys.
  Future<bool> hasEncryptionConsent() async {
    await _ensureCurrent();
    return store.hasEncryptionConsent(owner.uuid);
  }

  Future<void> grantEncryptionConsent() async {
    await _ensureCurrent();
    await store.grantEncryptionConsent(owner.uuid);
  }

  /// Sends [text] to [room]: in the clear where the room is not encrypted, else
  /// end to end. The Rust engine decides each step (publish keys, discover
  /// devices, claim keys, share the room key, send); this only performs the HTTP
  /// exchange and seals the state, and stops after [_maxSendSteps] as a guard.
  /// Every message needs its own [txn]; only a retry of that message reuses it.
  /// Returns the engine's warnings, for example `device_changed`.
  Future<List<String>> send(String room, String text, String txn) =>
      serial(() async {
        final warnings = <String>{};
        for (var step = 0; step < _maxSendSteps; step++) {
          await _ensureCurrent();
          var plan =
              jsonDecode(
                    await rs.myTsHistorySendStep(
                      history: _history,
                      room: room,
                      txn: txn,
                    ),
                  )
                  as Map<String, dynamic>;
          if (_planHook != null) plan = _planHook(plan);
          warnings.addAll((plan['warnings'] as List? ?? const []).cast());
          final action = plan['action'] as String;
          if (action == 'done') return warnings.toList();
          if (action == 'fail') throw _planFailure(plan['code'] as String?);
          if (!_sendActions.contains(action)) {
            throw const ChatException(ChatFailure.invalid);
          }
          // Nothing of the encrypted path runs before the user has agreed.
          if (_keyActions.contains(action) &&
              !await store.hasEncryptionConsent(owner.uuid)) {
            throw const ChatException(ChatFailure.consentRequired);
          }
          final args = <String, Object?>{
            ...(plan['args'] as Map).cast<String, Object?>(),
            if (action == 'send' || action == 'send_encrypted') 'text': text,
          };
          try {
            await _call(action, args);
          } on ChatException catch (e) {
            // A request the server refused for good would stay pending and
            // block the room: forget it. Network errors keep it for a retry.
            if ((action == 'share_keys' || action == 'send_encrypted') &&
                e.failure == ChatFailure.http &&
                _permanent(e.status)) {
              await rs.myTsHistorySendReset(history: _history, room: room);
              await _save();
            }
            rethrow;
          }
        }
        throw const ChatException(ChatFailure.invalid);
      });

  static bool _permanent(int? status) =>
      status != null &&
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;

  ChatException _planFailure(String? code) => ChatException(switch (code) {
    'not_logged_in' => ChatFailure.notLoggedIn,
    'no_recipients' => ChatFailure.noRecipients,
    'unsupported_room' => ChatFailure.unsupportedRoom,
    'limit' => ChatFailure.limit,
    'room_unknown' => ChatFailure.notSendable,
    _ => ChatFailure.invalid,
  });

  Future<void> setPresence(int state, String status) => serial(
    () => _call('presence_set', {'state': state, 'status': status}),
  );

  Future<void> setDisplayName(String name) =>
      serial(() => _call('set_name', {'name': name}));

  /// Presence and display name of [users]; per-user failures are skipped.
  Future<void> refreshPeople(Iterable<String> users) => serial(() async {
    final me = (await _accountUser());
    for (final user in users.take(60)) {
      await _soft(() => _call('presence_get', {'user': user}, (s) => s == 404));
      if (user != me) await _soft(() => _call('profile', {'user': user}));
    }
    await _soft(() => _call('profile', {'user': me}));
  });

  Future<String> _accountUser() async =>
      (jsonDecode(await rs.myTsHistoryStatus(history: _history)) as Map)['user']
          as String;

  Future<void> acceptInvite(String room) =>
      serial(() => _call('join', {'room': room}));

  /// Declines an invitation or leaves a joined room.
  Future<void> leave(String room) =>
      serial(() => _call('leave', {'room': room}));

  /// Creates an unencrypted direct room with [user] and records it in `m.direct`.
  Future<String> startDirect(String user) => serial(() async {
    final before = (await _roomIds()).toSet();
    await _call('create_dm', {'user': user});
    final created = (await _roomIds()).firstWhere(
      (r) => !before.contains(r),
      orElse: () => '',
    );
    if (created.isEmpty) throw const ChatException(ChatFailure.invalid);
    await _soft(() => _call('state', {'room': created}));
    await _soft(() => _call('set_direct', {'user': user, 'room': created}));
    return created;
  });

  void close() {
    if (_closed) return;
    _closed = true;
    _history.dispose();
    _key.dispose();
  }
}

/// Steps of one send that [ChatClient.send] may run; a step the engine names
/// that is not listed here is a bug, not something to execute.
const _sendActions = {
  'keys_upload',
  'keys_query',
  'keys_claim',
  'share_keys',
  'send_encrypted',
  'send',
};

/// The steps that need the user's consent: they publish this phone's device
/// keys or hand room keys to other devices.
const _keyActions = {
  'keys_upload',
  'keys_query',
  'keys_claim',
  'share_keys',
  'send_encrypted',
};

const _maxSendSteps = 12;

/// The only Matrix operations permitted from the app. There is deliberately no
/// generic SDK connect routine: those often publish device keys on start. The
/// key actions are reachable only through the consent-gated [ChatClient.send].
const _allowedActions = {
  'login',
  'whoami',
  'rooms',
  'state',
  'messages',
  'send',
  'keys_upload',
  'keys_query',
  'keys_claim',
  'share_keys',
  'send_encrypted',
  'presence_set',
  'presence_get',
  'profile',
  'set_name',
  'invites',
  'join',
  'leave',
  'direct',
  'create_dm',
  'set_direct',
};

Future<MyTsHttpResponse> matrixExchange(
  rs.MyTsHistoryRequest request,
  String action,
) async {
  if (!_allowedActions.contains(action) ||
      !safePublicHttpsHost(request.host) ||
      request.segments.isEmpty ||
      request.segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
      !{'GET', 'POST', 'PUT'}.contains(request.method)) {
    throw const FormatException('invalid chat destination');
  }
  final uri = Uri(
    scheme: 'https',
    host: request.host,
    pathSegments: request.segments,
    queryParameters: (jsonDecode(request.query) as Map).cast<String, String>(),
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = publicHttpsConnection;
  try {
    return await (() async {
      final outgoing = await client.openUrl(request.method, uri);
      outgoing.followRedirects = false;
      (jsonDecode(request.headers) as Map).cast<String, String>().forEach(
        outgoing.headers.set,
      );
      if (request.body.isNotEmpty) {
        outgoing.contentLength = request.body.length;
        outgoing.add(request.body);
      }
      final response = await outgoing.close();
      if (response.statusCode != 200) {
        return MyTsHttpResponse(response.statusCode, Uint8List(0));
      }
      const limit = 2 * 1024 * 1024;
      if (response.contentLength > limit) throw const MyTsResponseRejected();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const MyTsResponseRejected();
        }
        bytes.add(chunk);
      }
      return MyTsHttpResponse(200, bytes.takeBytes());
    })().timeout(const Duration(seconds: 25));
  } finally {
    client.close(force: true);
    request.body.fillRange(0, request.body.length, 0);
  }
}
