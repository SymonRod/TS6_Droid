import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/server_bookmark.dart';
import '../data/stores.dart';
import '../rust/api.dart';

/// Platform channel to the Kotlin foreground service / audio engine (phases 3-4).
/// PCM and Opus never cross it: only control calls.
const _audioChannel = MethodChannel('ts6/audio');

final bookmarkStoreProvider = Provider((_) => BookmarkStore());
final settingsStoreProvider = Provider((_) => SettingsStore());
final identityStoreProvider = Provider((_) => IdentityStore());

class ChatMessage {
  final String sender;
  final String text;
  final TsMessageTarget target;
  final bool isMe;
  final int senderId;
  final DateTime time = DateTime.now();
  ChatMessage(this.sender, this.text, this.target, {this.isMe = false, this.senderId = 0});
}

enum ConnStatus { idle, connecting, connected }

class ServerState {
  final ConnStatus status;
  final String? error;
  final TsSnapshot? snapshot;
  final List<ChatMessage> messages;
  final Set<int> talking;
  final bool muted;

  const ServerState({
    this.status = ConnStatus.idle,
    this.error,
    this.snapshot,
    this.messages = const [],
    this.talking = const {},
    this.muted = true,
  });

  ServerState copyWith({
    ConnStatus? status,
    String? error,
    bool clearError = false,
    TsSnapshot? snapshot,
    List<ChatMessage>? messages,
    Set<int>? talking,
    bool? muted,
  }) =>
      ServerState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        snapshot: snapshot ?? this.snapshot,
        messages: messages ?? this.messages,
        talking: talking ?? this.talking,
        muted: muted ?? this.muted,
      );
}

/// Port of TsClient.kt + the state part of ServerViewModel: owns the Rust
/// client, turns its event stream into Riverpod state.
class ServerController extends Notifier<ServerState> {
  TsClient? _client;
  StreamSubscription<TsEvent>? _sub;
  Timer? _refreshTimer;
  Timer? _periodic;

  @override
  ServerState build() {
    // Notification "Disconnect" button.
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'disconnectRequested') await disconnect();
    });
    ref.onDispose(() => _teardown());
    return const ServerState();
  }

  Future<bool> connect(ServerBookmark b) async {
    await disconnect();
    state = const ServerState(status: ConnStatus.connecting);
    try {
      final identity = await ref.read(identityStoreProvider).getOrCreate();
      final client = await TsClient.connect(
        address: b.address,
        identity: identity,
        nickname: b.nickname,
        password: b.password,
        channel: b.channel,
      );
      _client = client;
      await client.waitConnected();
      _sub = client.events().listen(_onEvent, onError: (Object e) {
        state = state.copyWith(error: '$e');
      });
      // Phase 3/4: permissions, then foreground service (audio runs in Kotlin+Rust).
      try {
        await _audioChannel.invokeMethod('requestPermissions');
        await _audioChannel.invokeMethod('startService', {'text': 'Connected to ${b.address}'});
        await _audioChannel.invokeMethod('setMuted', {'muted': true});
        await client.setInputMuted(muted: true);
      } catch (e) {
        state = state.copyWith(error: 'audio: $e');
      }
      _periodic = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
      state = state.copyWith(status: ConnStatus.connected, snapshot: client.snapshot());
      return true;
    } catch (e) {
      _teardown();
      state = ServerState(error: '$e');
      return false;
    }
  }

  void _refresh() {
    final c = _client;
    if (c == null) return;
    try {
      state = state.copyWith(snapshot: c.snapshot());
    } catch (_) {}
  }

  void _scheduleRefresh() {
    _refreshTimer ??= Timer(const Duration(milliseconds: 80), () {
      _refreshTimer = null;
      _refresh();
    });
  }

  void _onEvent(TsEvent e) {
    switch (e) {
      case TsEvent_TextMessage():
        final me = state.snapshot?.clientId;
        if (e.senderId == me) break; // we add our own messages locally
        _addMessage(ChatMessage(e.senderName, e.message, e.target, senderId: e.senderId));
      case TsEvent_TalkStatusStart():
        state = state.copyWith(talking: {...state.talking, e.userId});
      case TsEvent_TalkStatusStop():
        state = state.copyWith(talking: {...state.talking}..remove(e.userId));
      case TsEvent_Disconnected() || TsEvent_ConnectionLost():
        final reason = e is TsEvent_Disconnected ? e.reason : (e as TsEvent_ConnectionLost).reason;
        _teardown();
        _audioChannel.invokeMethod('stopService').catchError((_) {});
        state = ServerState(error: reason, messages: state.messages);
        return;
      case TsEvent_CommandError():
        state = state.copyWith(error: e.message);
      case TsEvent_Poked():
        _addMessage(ChatMessage(e.pokerName, '[poke] ${e.message}', TsMessageTarget.private,
            senderId: e.pokerId));
      default:
        break;
    }
    _scheduleRefresh();
  }

  void _addMessage(ChatMessage m) {
    state = state.copyWith(messages: [...state.messages, m]);
  }

  String get _myName {
    final s = state.snapshot;
    if (s == null) return 'me';
    return s.users.where((u) => u.id == s.clientId).map((u) => u.nickname).firstOrNull ?? 'me';
  }

  Future<void> sendChannelMessage(String text) async {
    await _client?.sendChannelMessage(msg: text);
    _addMessage(ChatMessage(_myName, text, TsMessageTarget.channel, isMe: true));
  }

  Future<void> sendServerMessage(String text) async {
    await _client?.sendServerMessage(msg: text);
    _addMessage(ChatMessage(_myName, text, TsMessageTarget.server, isMe: true));
  }

  Future<void> sendPrivateMessage(int userId, String text) async {
    await _client?.sendPrivateMessage(userId: userId, msg: text);
    _addMessage(
        ChatMessage(_myName, text, TsMessageTarget.private, isMe: true, senderId: userId));
  }

  Future<void> moveToChannel(int channelId) async {
    try {
      await _client?.moveToChannel(channelId: channelId);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> toggleMute() async {
    final m = !state.muted;
    state = state.copyWith(muted: m);
    try {
      await _audioChannel.invokeMethod('setMuted', {'muted': m});
      await _client?.setInputMuted(muted: m);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> disconnect() async {
    final c = _client;
    _teardown();
    _audioChannel.invokeMethod('stopService').catchError((_) {});
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
      c.dispose();
    }
    state = const ServerState();
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _periodic?.cancel();
    _periodic = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _client = null;
  }
}

final serverProvider = NotifierProvider<ServerController, ServerState>(ServerController.new);

class BookmarksController extends AsyncNotifier<List<ServerBookmark>> {
  @override
  Future<List<ServerBookmark>> build() => ref.read(bookmarkStoreProvider).load();

  Future<void> _set(List<ServerBookmark> l) async {
    state = AsyncData(l);
    await ref.read(bookmarkStoreProvider).save(l);
  }

  Future<void> add(ServerBookmark b) async => _set([...?state.value, b]);

  Future<void> replace(int i, ServerBookmark b) async {
    final l = [...?state.value];
    if (i >= 0 && i < l.length) {
      l[i] = b;
      await _set(l);
    }
  }

  Future<void> remove(int i) async {
    final l = [...?state.value];
    if (i >= 0 && i < l.length) {
      l.removeAt(i);
      await _set(l);
    }
  }
}

final bookmarksProvider =
    AsyncNotifierProvider<BookmarksController, List<ServerBookmark>>(BookmarksController.new);
