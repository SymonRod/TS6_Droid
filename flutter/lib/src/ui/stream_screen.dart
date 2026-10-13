import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../state/stream_viewer.dart';

/// Full-screen viewer. Rotates freely; fit/fill toggle; pinch-zoom via
/// InteractiveViewer. Pops itself when the user leaves.
class StreamScreen extends StatefulWidget {
  final StreamViewer viewer;
  const StreamScreen({super.key, required this.viewer});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _fill = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _close() async {
    await widget.viewer.leave();
    if (mounted) context.pop();
  }

  String _status(AppLocalizations l, StreamViewer v) => switch (v.phase) {
        StreamPhase.requesting => l.shareRequesting,
        StreamPhase.connecting => l.shareConnecting,
        StreamPhase.failed => switch (v.message) {
            'stream_ended' => l.shareEnded,
            'join_timeout' => l.shareTimeout,
            'refused' => l.shareRefused,
            'ice_failed' => l.shareIce,
            final m => m ?? l.shareFailed,
          },
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: widget.viewer,
          builder: (context, _) {
            final v = widget.viewer;
            final playing = v.phase == StreamPhase.playing;
            return Stack(fit: StackFit.expand, children: [
              if (playing)
                InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: RTCVideoView(
                    v.renderer,
                    objectFit: _fill
                        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                        : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                )
              else
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (v.phase != StreamPhase.failed) const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_status(AppLocalizations.of(context), v), style: const TextStyle(color: Colors.white)),
                  ]),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: Row(children: [
                    if (playing && v.hasAudio) ...[
                      Icon(v.volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                      SizedBox(
                        width: 140,
                        child: Slider(value: v.volume, onChanged: v.setVolume),
                      ),
                    ],
                    if (playing)
                      IconButton(
                        color: Colors.white,
                        icon: Icon(_fill ? Icons.fit_screen : Icons.fullscreen),
                        tooltip: _fill ? AppLocalizations.of(context).fit : AppLocalizations.of(context).fill,
                        onPressed: () => setState(() => _fill = !_fill),
                      ),
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      tooltip: AppLocalizations.of(context).leave,
                      onPressed: _close,
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
