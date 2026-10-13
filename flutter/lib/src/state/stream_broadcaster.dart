import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../rust/api.dart';

const _audioChannel = MethodChannel('ts6/audio');

enum ShareState { idle, starting, live }

/// Broadcaster half of TS6 P2P screen sharing: one RTCPeerConnection per viewer
/// fed by the same MediaProjection capture. Signaling goes through [TsClient].
class StreamBroadcaster extends ChangeNotifier {
  StreamBroadcaster(this._client);

  static const _bitrate = 1500000;
  static const _candidateInterval = Duration(milliseconds: 120);
  static const _iceServers = [
    {'urls': 'stun:turn.teamspeak.com:3478'},
    {'urls': 'stun:turn2.teamspeak.com:3478'},
  ];

  final TsClient _client;

  ShareState state = ShareState.idle;
  int viewers = 0;
  String? error;

  MediaStream? _capture;
  bool _withAudio = false;
  String? _streamId;
  int? _myId;
  Set<String> _knownOwn = {};
  Timer? _setupTimeout;
  final _peers = <int, _Peer>{};

  bool get active => state != ShareState.idle;

  /// Asks the capture consent, then publishes the stream. [name] is what viewers see.
  Future<void> start(String name, int myId, Iterable<TsStream> current, {bool withAudio = false}) async {
    if (active) return;
    state = ShareState.starting;
    error = null;
    _myId = myId;
    _withAudio = withAudio;
    _knownOwn = {for (final s in current) if (s.ownerId == myId) s.id};
    notifyListeners();
    try {
      // Consent first, then the mediaProjection foreground type, then capture
      // (Android 14 rejects the type without a prior grant).
      final ok = await Helper.requestCapturePermission();
      if (!ok) throw 'capture_denied';
      await _audioChannel.invokeMethod('setScreenShare', {'on': true});
      final cap = await navigator.mediaDevices.getDisplayMedia({'video': true, 'audio': withAudio});
      debugPrint('share: capture audioTracks=${cap.getAudioTracks().length}');
      _capture = cap;
      cap.getVideoTracks().first.onEnded = () => stop();
      await _client.setupStream(name: name, bitrate: _bitrate, audio: withAudio);
      _setupTimeout = Timer(const Duration(seconds: 10), () {
        if (state == ShareState.starting) _fail('setup_timeout');
      });
    } catch (e) {
      await _fail('$e');
    }
  }

  Future<void> stop() async {
    final id = _streamId;
    await _teardown();
    if (id != null) {
      try {
        await _client.stopStream(streamId: id);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Feed every [TsEvent] here.
  void onEvent(TsEvent e) {
    switch (e) {
      case TsEvent_StreamsChanged():
        if (state == ShareState.starting) {
          final mine = e.streams.where((s) => s.ownerId == _myId && !_knownOwn.contains(s.id));
          if (mine.isNotEmpty) {
            _setupTimeout?.cancel();
            _streamId = mine.first.id;
            state = ShareState.live;
            notifyListeners();
          }
        } else if (state == ShareState.live &&
            !e.streams.any((s) => s.ownerId == _myId && s.id == _streamId)) {
          // The server dropped our stream.
          _teardown().then((_) => notifyListeners());
        }
      case TsEvent_StreamJoinRequest():
        debugPrint('share[${e.viewerId}] join request remove=${e.isRemove}');
        if (e.streamId != _streamId || state != ShareState.live) break;
        if (e.isRemove) {
          _dropPeer(e.viewerId);
        } else {
          _addViewer(e.viewerId);
        }
      case TsEvent_StreamSignaling():
        // For a broadcaster, ownerId carries the viewer's id.
        final known = _peers.containsKey(e.ownerId);
        String cmd = '?';
        try {
          cmd = '${(jsonDecode(e.json) as Map)['cmd']}';
        } catch (_) {}
        debugPrint('share[${e.ownerId}] signaling in: $cmd '
            '(stream ok=${e.streamId == _streamId}, peer known=$known)');
        if (e.streamId == _streamId) {
          _peers[e.ownerId]?.onSignaling(e.json).catchError((Object err) {
            debugPrint('share[${e.ownerId}] signaling failed: $err');
          });
        }
      default:
        break;
    }
  }

  Future<void> _addViewer(int viewerId) async {
    final sid = _streamId, cap = _capture;
    if (sid == null || cap == null) return;
    await _dropPeer(viewerId);
    try {
      final pc = await createPeerConnection({
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'continualGatheringPolicy': 'gather_continually',
      });
      final peer = _Peer(viewerId, pc);
      peer.nudge = () => _nudge(peer);
      _peers[viewerId] = peer;
      pc.onIceCandidate = (c) {
        if (c.candidate == null || c.candidate!.isEmpty) return;
        peer.outgoing.add(c);
      };
      pc.onIceConnectionState = (st) {
        debugPrint('share[$viewerId] ice=$st');
        if (st == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          // A still screen produces no frames: kick the encoder so the viewer gets a picture.
          Timer(const Duration(milliseconds: 600), () => peer.nudge?.call());
        }
        if (st == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            st == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          _dropPeer(viewerId);
        }
      };
      // The desktop client's own offers are VP8; H.264 (the phone's hardware
      // default) arrives as a black picture there.
      final tr = await pc.addTransceiver(
        track: cap.getVideoTracks().first,
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [cap],
          sendEncodings: [
            RTCRtpEncoding(maxBitrate: _bitrate, maxFramerate: 15, scaleResolutionDownBy: 2.0),
          ],
        ),
      );
      peer.sender = tr.sender;
      // The desktop client's offers also carry an audio section (opus) and a viewer waits
      // forever without it. Inactive keeps the m-line but sends nothing: sendonly without
      // a track made libwebrtc open the mic and put the user's voice into the stream.
      // With the device-audio option the section is SendOnly with the playback-capture track.
      final audio = _withAudio ? cap.getAudioTracks() : const <MediaStreamTrack>[];
      if (audio.isNotEmpty) {
        await pc.addTransceiver(
          track: audio.first,
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [cap]),
        );
      } else {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.Inactive),
        );
      }
      final caps = await getRtpSenderCapabilities('video');
      final all = caps.codecs ?? const <RTCRtpCodecCapability>[];
      final vp8 = all.where((c) => c.mimeType.toLowerCase() == 'video/vp8').toList();
      if (vp8.isNotEmpty) {
        final rest = all.where((c) => c.mimeType.toLowerCase() != 'video/vp8').toList();
        await tr.setCodecPreferences([...vp8, ...rest]);
      }
      final offer = await pc.createOffer({'offerToReceiveVideo': false, 'offerToReceiveAudio': false});
      await pc.setLocalDescription(offer);
      // Like the desktop client and tslib-stream: let ICE gathering finish (bounded) so
      // the candidates travel inside the offer; a remote viewer may not answer a bare one.
      final gathered = Completer<void>();
      pc.onIceGatheringState = (g) {
        debugPrint('share[$viewerId] gathering=$g');
        if (g == RTCIceGatheringState.RTCIceGatheringStateComplete && !gathered.isCompleted) {
          gathered.complete();
        }
      };
      await gathered.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      final local = await pc.getLocalDescription();
      final sdp = local?.sdp ?? offer.sdp!;
      final inline = RegExp('^a=candidate:', multiLine: true).allMatches(sdp).length;
      debugPrint('share[$viewerId] offer carries $inline candidates');
      if (inline > 0) peer.outgoing.clear(); // already in the offer
      await _client.acceptStreamViewer(viewerId: viewerId, streamId: sid, offer: sdp);
      debugPrint('share[$viewerId] accept sent (${sdp.length} bytes of SDP)');
      // Paced trickle: a burst trips flood protection (error 524).
      peer.pump = Timer.periodic(_candidateInterval, (_) {
        if (peer.outgoing.isEmpty) return;
        final c = peer.outgoing.removeAt(0);
        _client
            .sendStreamSignaling(
                ownerId: viewerId,
                streamId: sid,
                json: jsonEncode({
                  'cmd': 'iceCandidate',
                  'args': {'mLine': c.sdpMLineIndex ?? 0, 'mid': c.sdpMid ?? '', 'sdp': c.candidate},
                }))
            .catchError((_) {});
      });
      peer.stats = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          for (final r in await pc.getStats()) {
            if (r.type == 'outbound-rtp' && r.values['kind'] == 'video') {
              final frames = (r.values['framesEncoded'] as num?)?.toInt() ?? 0;
              if (frames == peer.lastFrames) peer.nudge?.call(); // static screen: nothing encoded
              peer.lastFrames = frames;
              debugPrint('share[$viewerId] sent: bytes=${r.values['bytesSent']} '
                  'frames=${r.values['framesEncoded']} ${r.values['frameWidth']}x${r.values['frameHeight']} '
                  'codec=${r.values['codecId']}');
            }
          }
        } catch (_) {}
      });
      debugPrint('share[$viewerId] offer sent, tracks=${cap.getVideoTracks().length} '
          'enabled=${cap.getVideoTracks().first.enabled}');
      viewers = _peers.length;
      notifyListeners();
    } catch (e) {
      debugPrint('Broadcast negotiation failed: $e');
      await _dropPeer(viewerId);
      _client.refuseStreamViewer(viewerId: viewerId, streamId: sid).catchError((_) {});
    }
  }

  /// Toggling the encoding off and on restarts the encoder, which emits a keyframe
  /// from the last captured frame even if the screen has not changed.
  Future<void> _nudge(_Peer peer) async {
    final sender = peer.sender;
    if (sender == null || peer.nudging) return;
    peer.nudging = true;
    try {
      final p = sender.parameters;
      final enc = p.encodings;
      if (enc == null || enc.isEmpty) return;
      enc.first.active = false;
      await sender.setParameters(p);
      enc.first.active = true;
      await sender.setParameters(p);
      debugPrint('share[${peer.viewerId}] nudged');
    } catch (e) {
      debugPrint('share nudge failed: $e');
    } finally {
      peer.nudging = false;
    }
  }

  Future<void> _dropPeer(int viewerId) async {
    final p = _peers.remove(viewerId);
    if (p == null) return;
    await p.close();
    viewers = _peers.length;
    notifyListeners();
  }

  Future<void> _fail(String reason) async {
    final id = _streamId;
    await _teardown();
    if (id != null) {
      try {
        await _client.stopStream(streamId: id);
      } catch (_) {}
    }
    error = reason;
    notifyListeners();
  }

  Future<void> _teardown() async {
    _setupTimeout?.cancel();
    _setupTimeout = null;
    state = ShareState.idle;
    _streamId = null;
    for (final p in _peers.values) {
      await p.close();
    }
    _peers.clear();
    viewers = 0;
    final cap = _capture;
    _capture = null;
    if (cap != null) {
      for (final t in cap.getTracks()) {
        t.onEnded = null;
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await cap.dispose();
      } catch (_) {}
    }
    await _audioChannel.invokeMethod('setScreenShare', {'on': false}).catchError((_) {});
  }

  @override
  void dispose() {
    final id = _streamId;
    if (id != null) _client.stopStream(streamId: id).catchError((_) {});
    _teardown();
    super.dispose();
  }
}

class _Peer {
  _Peer(this.viewerId, this.pc);

  final int viewerId;
  final RTCPeerConnection pc;
  final outgoing = <RTCIceCandidate>[];
  final _pendingRemote = <RTCIceCandidate>[];
  bool _remoteSet = false;
  Timer? pump;
  Timer? stats;
  RTCRtpSender? sender;
  Future<void> Function()? nudge;
  bool nudging = false;
  int lastFrames = -1;

  Future<void> onSignaling(String json) async {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final args = m['args'];
    if (args is! Map) return;
    switch (m['cmd']) {
      case 'answer':
        final sdp = args['answer'];
        if (sdp is! String || sdp.isEmpty) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        _remoteSet = true;
        for (final c in _pendingRemote) {
          await pc.addCandidate(c);
        }
        _pendingRemote.clear();
      case 'iceCandidate':
        final sdp = args['sdp'];
        if (sdp is! String || sdp.isEmpty) return;
        final c = RTCIceCandidate(
            sdp, (args['mid'] as String?) ?? '', (args['mLine'] as num?)?.toInt() ?? 0);
        if (_remoteSet) {
          await pc.addCandidate(c);
        } else {
          _pendingRemote.add(c);
        }
    }
  }

  Future<void> close() async {
    pump?.cancel();
    stats?.cancel();
    try {
      await pc.close();
      await pc.dispose();
    } catch (_) {}
  }
}
