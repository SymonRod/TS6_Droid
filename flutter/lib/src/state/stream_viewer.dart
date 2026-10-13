import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../rust/api.dart';

enum StreamPhase { idle, requesting, connecting, playing, failed }

/// Port of StreamViewer.kt: viewer half of TS6 P2P screen sharing. Signaling
/// goes through [TsClient]; this class owns the RTCPeerConnection.
class StreamViewer extends ChangeNotifier {
  StreamViewer(this._client);

  static const _joinTimeout = Duration(seconds: 30);
  static const _candidateInterval = Duration(milliseconds: 120);
  static const _iceServers = [
    {'urls': 'stun:turn.teamspeak.com:3478'},
    {'urls': 'stun:turn2.teamspeak.com:3478'},
  ];

  final TsClient _client;

  StreamPhase phase = StreamPhase.idle;
  String? message;
  String title = '';
  int? ownerId;
  String? streamId;
  final renderer = RTCVideoRenderer();
  bool _rendererReady = false;

  RTCPeerConnection? _pc;
  Timer? _timeout;
  Timer? _pump;
  final _outgoing = <RTCIceCandidate>[];
  final _pendingRemote = <RTCIceCandidate>[];
  bool _remoteSet = false;

  bool _is(int o, String s) => ownerId == o && streamId == s;

  Future<void> join(int owner, String stream, String name) async {
    await _teardown(notify: true);
    if (!_rendererReady) {
      await renderer.initialize();
      _rendererReady = true;
    }
    ownerId = owner;
    streamId = stream;
    title = name;
    message = null;
    phase = StreamPhase.requesting;
    notifyListeners();
    try {
      await _client.joinStream(ownerId: owner, streamId: stream);
    } catch (e) {
      _fail('$e');
      return;
    }
    _timeout = Timer(_joinTimeout, () {
      if (phase == StreamPhase.requesting) _fail('join_timeout');
    });
  }

  Future<void> leave() async {
    await _teardown(notify: true);
    phase = StreamPhase.idle;
    message = null;
    notifyListeners();
  }

  /// Feed every [TsEvent] here.
  void onEvent(TsEvent e) {
    switch (e) {
      case TsEvent_StreamJoinResponse():
        if (_is(e.ownerId, e.streamId)) _onJoinResponse(e);
      case TsEvent_StreamSignaling():
        if (_is(e.ownerId, e.streamId)) _onSignaling(e.json);
      case TsEvent_StreamsChanged():
        final o = ownerId, s = streamId;
        if (o != null && s != null && phase != StreamPhase.idle && phase != StreamPhase.failed) {
          if (!e.streams.any((x) => x.ownerId == o && x.id == s)) _fail('stream_ended');
        }
      default:
        break;
    }
  }

  Future<void> _onJoinResponse(TsEvent_StreamJoinResponse r) async {
    _timeout?.cancel();
    if (!r.accepted) {
      _fail(r.message?.isNotEmpty == true ? r.message! : 'refused');
      return;
    }
    final offer = r.offer;
    if (offer == null || offer.isEmpty) {
      _fail('no_offer');
      return;
    }
    phase = StreamPhase.connecting;
    notifyListeners();
    try {
      await _answer(offer);
    } catch (e) {
      debugPrint('WebRTC negotiation failed: $e');
      _fail('negotiation_failed');
    }
  }

  Future<void> _answer(String offer) async {
    final o = ownerId!, s = streamId!;
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'continualGatheringPolicy': 'gather_continually',
    });
    _pc = pc;
    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      _outgoing.add(c);
    };
    pc.onTrack = (ev) {
      if (ev.track.kind == 'video') {
        renderer.srcObject = ev.streams.isNotEmpty ? ev.streams.first : null;
        phase = StreamPhase.playing;
        message = null;
        notifyListeners();
      }
    };
    pc.onIceConnectionState = (st) {
      if (st == RTCIceConnectionState.RTCIceConnectionStateFailed) _fail('ice_failed');
      if (st == RTCIceConnectionState.RTCIceConnectionStateClosed) _fail('connection_closed');
    };
    // Paced trickle: a burst trips flood protection (error 524).
    _pump = Timer.periodic(_candidateInterval, (_) {
      if (_outgoing.isEmpty) return;
      final c = _outgoing.removeAt(0);
      _client
          .sendStreamSignaling(
              ownerId: o,
              streamId: s,
              json: jsonEncode({
                'cmd': 'iceCandidate',
                'args': {'mLine': c.sdpMLineIndex ?? 0, 'mid': c.sdpMid ?? '', 'sdp': c.candidate},
              }))
          .catchError((_) {});
    });

    await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    _remoteSet = true;
    for (final c in _pendingRemote) {
      await pc.addCandidate(c);
    }
    _pendingRemote.clear();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _client.sendStreamSignaling(
        ownerId: o,
        streamId: s,
        json: jsonEncode({
          'cmd': 'answer',
          'args': {'answer': answer.sdp},
        }));
  }

  Future<void> _onSignaling(String json) async {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['cmd'] != 'iceCandidate') return;
    final args = m['args'];
    if (args is! Map) return;
    final sdp = args['sdp'];
    if (sdp is! String || sdp.isEmpty) return;
    final c = RTCIceCandidate(sdp, (args['mid'] as String?) ?? '', (args['mLine'] as num?)?.toInt() ?? 0);
    final pc = _pc;
    if (pc != null && _remoteSet) {
      await pc.addCandidate(c);
    } else {
      _pendingRemote.add(c);
    }
  }

  void _fail(String reason) {
    if (ownerId == null) return;
    _teardown(notify: false).then((_) {
      phase = StreamPhase.failed;
      message = reason;
      notifyListeners();
    });
  }

  Future<void> _teardown({required bool notify}) async {
    _timeout?.cancel();
    _timeout = null;
    _pump?.cancel();
    _pump = null;
    _outgoing.clear();
    _pendingRemote.clear();
    _remoteSet = false;
    final pc = _pc;
    _pc = null;
    if (_rendererReady) renderer.srcObject = null;
    final o = ownerId, s = streamId;
    if (notify && o != null && s != null) {
      try {
        await _client.leaveStream(ownerId: o, streamId: s);
      } catch (_) {}
    }
    ownerId = null;
    streamId = null;
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _teardown(notify: true);
    if (_rendererReady) renderer.dispose();
    super.dispose();
  }
}
