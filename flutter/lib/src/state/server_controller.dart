import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';
import '../data/message_store.dart';
import '../data/server_bookmark.dart';
import '../data/stores.dart';
import '../rust/api.dart';
import '../util/errors.dart';
import 'stream_broadcaster.dart';
import 'stream_viewer.dart';

/// Platform channel to the Kotlin foreground service / audio engine (phases 3-4).
/// PCM and Opus never cross it: only control calls.
const _audioChannel = MethodChannel('ts6/audio');

final bookmarkStoreProvider = Provider((_) => BookmarkStore());
final settingsStoreProvider = Provider((_) => SettingsStore());
final identityStoreProvider = Provider((_) => IdentityStore());
final messageStoreProvider = Provider((_) => MessageStore());

AppLocalizations _l10n() {
  try {
    return lookupAppLocalizations(PlatformDispatcher.instance.locale);
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

class ChatMessage {
  final String sender;
  final String text;
  final TsMessageTarget target;
  final bool isMe;
  final int senderId;
  final DateTime time;
  ChatMessage(this.sender, this.text, this.target,
      {this.isMe = false, this.senderId = 0, DateTime? time})
      : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'text': text,
        'target': target.name,
        'isMe': isMe,
        'senderId': senderId,
        'time': time.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        j['sender'] as String? ?? '',
        j['text'] as String? ?? '',
        TsMessageTarget.values.asNameMap()[j['target']] ?? TsMessageTarget.channel,
        isMe: j['isMe'] as bool? ?? false,
        senderId: j['senderId'] as int? ?? 0,
        time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int? ?? 0),
      );
}

enum ConnStatus { idle, connecting, connected }

/// One entry of the Android audio route list (speaker, earpiece, wired, Bluetooth...).
class AudioDevice {
  final int id;
  final int type; // android.media.AudioDeviceInfo.TYPE_*
  final String name; // 'speaker' / 'earpiece' for built-ins, else the product name
  const AudioDevice(this.id, this.type, this.name);

  bool get isBluetooth => const {7, 8, 26, 27, 30}.contains(type); // SCO, A2DP, BLE headset/speaker/broadcast
  bool get isWired => const {3, 4, 11, 22}.contains(type); // headset, headphones, usb device, usb headset
}

class AudioRoute {
  final List<AudioDevice> devices;
  final int? active;
  final bool auto;
  const AudioRoute({this.devices = const [], this.active, this.auto = true});

  factory AudioRoute.fromMap(Map<dynamic, dynamic> m) => AudioRoute(
        devices: [
          for (final d in (m['devices'] as List? ?? const []))
            AudioDevice(d['id'] as int, d['type'] as int, d['name'] as String? ?? ''),
        ],
        active: m['active'] as int?,
        auto: m['auto'] as bool? ?? true,
      );

  AudioDevice? get current {
    for (final d in devices) {
      if (d.id == active) return d;
    }
    return null;
  }
}

class ServerState {
  final ConnStatus status;
  final String? error;
  final TsSnapshot? snapshot;
  final List<ChatMessage> messages;
  final Set<int> talking;
  final bool muted;
  final bool ptt;
  final bool deafened;
  final int imageRev;
  final AudioRoute route;
  final ShareState share;
  final int shareViewers;

  const ServerState({
    this.status = ConnStatus.idle,
    this.error,
    this.snapshot,
    this.messages = const [],
    this.talking = const {},
    this.muted = true,
    this.ptt = false,
    this.deafened = false,
    this.imageRev = 0,
    this.route = const AudioRoute(),
    this.share = ShareState.idle,
    this.shareViewers = 0,
  });

  ServerState copyWith({
    ConnStatus? status,
    String? error,
    bool clearError = false,
    TsSnapshot? snapshot,
    List<ChatMessage>? messages,
    Set<int>? talking,
    bool? muted,
    bool? ptt,
    bool? deafened,
    int? imageRev,
    AudioRoute? route,
    ShareState? share,
    int? shareViewers,
  }) =>
      ServerState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        snapshot: snapshot ?? this.snapshot,
        messages: messages ?? this.messages,
        talking: talking ?? this.talking,
        muted: muted ?? this.muted,
        ptt: ptt ?? this.ptt,
        deafened: deafened ?? this.deafened,
        imageRev: imageRev ?? this.imageRev,
        route: route ?? this.route,
        share: share ?? this.share,
        shareViewers: shareViewers ?? this.shareViewers,
      );
}

/// Port of TsClient.kt + the state part of ServerViewModel: owns the Rust
/// client, turns its event stream into Riverpod state.
class ServerController extends Notifier<ServerState> {
  TsClient? _client;
  StreamSubscription<TsEvent>? _sub;
  Timer? _refreshTimer;
  Timer? _periodic;
  Timer? _saveTimer;
  StreamViewer? viewer;
  StreamBroadcaster? broadcaster;
  String? _address;
  final _queriedOwners = <int>{};

  // Icons and avatars: key -> bytes, fetched from the server (channel 0) and cached on disk.
  final _images = <String, Uint8List>{};
  final _imageQueue = <String>[];
  final _imageInFlight = <String, Timer>{}; // key -> timeout
  final _imageFails = <String, int>{};
  Directory? _imageDir;

  @override
  ServerState build() {
    _audioChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'disconnectRequested': // notification button
          await disconnect();
        case 'muteToggleRequested': // notification button
          if (state.status == ConnStatus.connected) await toggleMute();
        case 'voiceActivity': // capture-thread level detector (visual only)
          _voice = call.arguments == true;
          _syncLocalTalking();
        case 'audioRoute': // device added/removed or route changed
          if (state.status == ConnStatus.connected) {
            state = state.copyWith(route: AudioRoute.fromMap(call.arguments as Map));
          }
      }
    });
    ref.read(settingsStoreProvider).pushToTalk().then((v) {
      if (ref.mounted) state = state.copyWith(ptt: v);
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
      _address = b.address;
      viewer = StreamViewer(client);
      broadcaster = StreamBroadcaster(client)..addListener(_onBroadcaster);
      final ptt = await ref.read(settingsStoreProvider).pushToTalk();
      final saved = await ref.read(messageStoreProvider).load(b.address);
      await client.waitConnected();
      _sub = client.events().listen(_onEvent, onError: (Object e) {
        state = state.copyWith(error: cleanError(e));
      });
      // Phase 3/4: permissions, then foreground service (audio runs in Kotlin+Rust).
      try {
        final l = _l10n();
        await _audioChannel.invokeMethod('requestPermissions');
        await _audioChannel.invokeMethod('startService', {
          'text': l.connectedTo(b.address),
          'disconnect': l.disconnect,
          'mute': l.notifMute,
          'unmute': l.notifUnmute,
        });
        await _audioChannel.invokeMethod('setMuted', {'muted': true});
        await client.setInputMuted(muted: true);
        final r = await _audioChannel.invokeMethod('getAudioRoute');
        if (r is Map) state = state.copyWith(route: AudioRoute.fromMap(r));
      } catch (e) {
        state = state.copyWith(error: 'audio: ${cleanError(e)}');
      }
      _periodic = Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
      state = state.copyWith(
        status: ConnStatus.connected,
        snapshot: client.snapshot(),
        messages: [for (final j in saved) ChatMessage.fromJson(j)],
        ptt: ptt,
        muted: true,
      );
      return true;
    } catch (e) {
      final c = _client;
      _teardown();
      if (c != null) _release(c);
      state = ServerState(error: cleanError(e));
      return false;
    }
  }

  void _refresh() {
    final c = _client;
    if (c == null) return;
    try {
      final snap = c.snapshot();
      state = state.copyWith(snapshot: snap);
      // Shares already running at join time only show up after a request.
      for (final u in snap.users) {
        if (u.isStreaming &&
            !snap.streams.any((s) => s.ownerId == u.id) &&
            _queriedOwners.add(u.id)) {
          c.requestStreamInfo(ownerId: u.id).catchError((_) {});
        }
      }
    } catch (_) {}
  }

  void _scheduleRefresh() {
    _refreshTimer ??= Timer(const Duration(milliseconds: 80), () {
      _refreshTimer = null;
      _refresh();
    });
  }

  void _onEvent(TsEvent e) {
    viewer?.onEvent(e);
    broadcaster?.onEvent(e);
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
        final c = _client;
        _saveNow();
        _teardown();
        // The Rust client (runtime, sockets, audio sender) must be released too.
        if (c != null) _release(c);
        _audioChannel.invokeMethod('stopService').catchError((_) {});
        state = ServerState(error: cleanError(reason), messages: state.messages, ptt: state.ptt);
        return;
      case TsEvent_CommandError():
        debugPrint('server error ${e.errorId}: ${e.message}');
        state = state.copyWith(error: cleanError(e.message));
      case TsEvent_Poked():
        _addMessage(ChatMessage(e.pokerName, '[poke] ${e.message}', TsMessageTarget.private,
            senderId: e.pokerId));
      case TsEvent_FileDownloaded():
        _onImage(e.path, e.data);
      case TsEvent_FileTransferFailed():
        _onImageFailed(e.path);
      default:
        break;
    }
    _scheduleRefresh();
  }

  /// Disconnect (best effort) and free the native client.
  void _release(TsClient c) {
    () async {
      try {
        await c.disconnect();
      } catch (_) {}
      c.dispose();
    }();
  }

  // ----------------------------------------------------------------- images

  static String _uidToAvatarPath(String uid) {
    final bytes = base64.decode(base64.normalize(uid));
    final sb = StringBuffer('/avatar_');
    for (final b in bytes) {
      sb.writeCharCode(0x61 + (b >> 4));
      sb.writeCharCode(0x61 + (b & 15));
    }
    return sb.toString();
  }

  static String _pathFor(String key) =>
      key.startsWith('icon:') ? '/icon_${key.substring(5)}' : _uidToAvatarPath(key.substring(7));

  /// Returns the bytes if already known; otherwise starts loading and returns
  /// null (the UI rebuilds when `imageRev` changes). Keys: `icon:<id>`, `avatar:<uid>`.
  Uint8List? image(String key) {
    final hit = _images[key];
    if (hit != null) return hit;
    if ((_imageFails[key] ?? 0) >= 3 || _imageInFlight.containsKey(key) || _imageQueue.contains(key)) {
      return null;
    }
    _imageQueue.add(key);
    Future.microtask(_pumpImages);
    return null;
  }

  Future<File> _imageFile(String key) async {
    _imageDir ??= await Directory('${(await getApplicationCacheDirectory()).path}/ts_images').create();
    return File('${_imageDir!.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
  }

  Future<void> _pumpImages() async {
    final c = _client;
    if (c == null) return;
    while (_imageInFlight.length < 2 && _imageQueue.isNotEmpty) {
      final key = _imageQueue.removeAt(0);
      try {
        final f = await _imageFile(key);
        if (await f.exists() && await f.length() > 0) {
          _images[key] = await f.readAsBytes();
          state = state.copyWith(imageRev: state.imageRev + 1);
          continue;
        }
        _imageInFlight[key] = Timer(const Duration(seconds: 15), () => _onImageFailed(_pathFor(key)));
        await c.downloadFile(channelId: 0, path: _pathFor(key));
      } catch (_) {
        _imageInFlight.remove(key)?.cancel();
        _imageFails[key] = (_imageFails[key] ?? 0) + 1;
      }
    }
  }

  String? _keyForPath(String path) {
    for (final k in _imageInFlight.keys) {
      if (_pathFor(k) == path) return k;
    }
    return null;
  }

  Future<void> _onImage(String path, List<int> data) async {
    final key = _keyForPath(path);
    if (key == null) return;
    _imageInFlight.remove(key)?.cancel();
    if (data.isNotEmpty) {
      final bytes = Uint8List.fromList(data);
      _images[key] = bytes;
      try {
        await (await _imageFile(key)).writeAsBytes(bytes);
      } catch (_) {}
      if (ref.mounted) state = state.copyWith(imageRev: state.imageRev + 1);
    } else {
      _imageFails[key] = (_imageFails[key] ?? 0) + 1;
    }
    _pumpImages();
  }

  void _onImageFailed(String path) {
    final key = _keyForPath(path);
    if (key == null) return;
    _imageInFlight.remove(key)?.cancel();
    _imageFails[key] = (_imageFails[key] ?? 0) + 1;
    _pumpImages();
  }

  // ------------------------------------------------------------------- chat

  void _addMessage(ChatMessage m) {
    state = state.copyWith(messages: [...state.messages, m]);
    _saveTimer ??= Timer(const Duration(seconds: 2), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final a = _address;
    if (a == null) return;
    ref.read(messageStoreProvider).save(a, [for (final m in state.messages) m.toJson()]);
  }

  Future<void> clearChat() async {
    state = state.copyWith(messages: const []);
    final a = _address;
    if (a != null) await ref.read(messageStoreProvider).clear(a);
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

  Future<void> moveToChannel(int channelId, {String? password}) async {
    try {
      if (password != null && password.isNotEmpty) {
        await _client?.moveToChannelWithPassword(channelId: channelId, password: password);
      } else {
        await _client?.moveToChannel(channelId: channelId);
      }
    } catch (e) {
      state = state.copyWith(error: cleanError(e));
    }
  }

  // ------------------------------------------------------------------ audio

  bool _voice = false;

  /// Own "speaking" ring: the server never echoes our audio, so derive it locally.
  /// PTT: while the mic is open (button held). Open mic: level detector in Kotlin.
  /// Only touches state on transitions.
  void _syncLocalTalking() {
    final me = state.snapshot?.clientId;
    if (me == null || state.status != ConnStatus.connected) return;
    final on = !state.muted && !state.deafened && (state.ptt || _voice);
    if (on == state.talking.contains(me)) return;
    state = state.copyWith(
        talking: on ? {...state.talking, me} : ({...state.talking}..remove(me)));
  }

  Future<void> _applyMuted(bool m) async {
    state = state.copyWith(muted: m);
    _syncLocalTalking();
    try {
      await _audioChannel.invokeMethod('setMuted', {'muted': m});
      await _client?.setInputMuted(muted: m);
    } catch (e) {
      state = state.copyWith(error: cleanError(e));
    }
  }

  bool _micWasOnBeforeDeafen = false;

  /// Deafen: stops local playback, tells the server (client_output_muted) and,
  /// like the official client, mutes the mic while on; the mic is restored on
  /// undeafen if it was active before.
  Future<void> toggleDeafen({bool restoreMic = true}) async {
    final d = !state.deafened;
    if (d) _micWasOnBeforeDeafen = !state.muted;
    state = state.copyWith(deafened: d);
    _syncLocalTalking();
    try {
      await _audioChannel.invokeMethod('setDeafened', {'deafened': d});
      await _client?.setOutputMuted(muted: d);
    } catch (e) {
      state = state.copyWith(error: cleanError(e));
    }
    if (d) {
      if (!state.muted) await _applyMuted(true);
    } else if (restoreMic && _micWasOnBeforeDeafen && !state.ptt) {
      await _applyMuted(false);
    }
  }

  Future<void> toggleMute() async {
    if (state.deafened) {
      // Enabling the mic while deafened also undeafens (mic stays as requested).
      await toggleDeafen(restoreMic: false);
      if (!state.muted) return;
    }
    await _applyMuted(!state.muted);
  }

  Future<void> setPushToTalk(bool on) async {
    state = state.copyWith(ptt: on);
    _syncLocalTalking();
    await ref.read(settingsStoreProvider).setPushToTalk(on);
    await _applyMuted(true);
  }

  /// Push-to-talk button: down opens the mic, up closes it.
  Future<void> pttHold(bool down) => _applyMuted(!down);

  /// null = automatic routing.
  Future<void> setAudioDevice(int? id) async {
    try {
      await _audioChannel.invokeMethod('setAudioDevice', {'id': id});
    } catch (e) {
      state = state.copyWith(error: cleanError(e));
    }
  }

  Future<void> toggleScreenShare() async {
    final b = broadcaster, snap = state.snapshot;
    if (b == null || snap == null) return;
    if (b.active) return b.stop();
    final me = snap.clientId;
    if (me == null) return;
    final nick = snap.users.where((u) => u.id == me).map((u) => u.nickname).firstOrNull ?? 'Screen';
    await b.start(nick, me, snap.streams);
  }

  void _onBroadcaster() {
    final b = broadcaster;
    if (b == null) return;
    state = state.copyWith(share: b.state, shareViewers: b.viewers);
    final err = b.error;
    if (err != null) {
      b.error = null;
      state = state.copyWith(error: cleanError(err));
    }
  }

  void requestStreamInfo(int ownerId) => _client?.requestStreamInfo(ownerId: ownerId).catchError((_) {});

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> disconnect() async {
    final c = _client;
    if (c != null) _saveNow();
    _teardown();
    _audioChannel.invokeMethod('stopService').catchError((_) {});
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
      c.dispose();
    }
    _voice = false;
    state = ServerState(ptt: state.ptt);
  }

  void _teardown() {
    viewer?.dispose();
    viewer = null;
    broadcaster?.dispose();
    broadcaster = null;
    _queriedOwners.clear();
    _sub?.cancel();
    _sub = null;
    _periodic?.cancel();
    _periodic = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _saveTimer?.cancel();
    _saveTimer = null;
    for (final t in _imageInFlight.values) {
      t.cancel();
    }
    _imageInFlight.clear();
    _imageQueue.clear();
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
