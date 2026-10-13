import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/server_controller.dart';

/// Server icon or avatar. Keys: `icon:<id>` or `avatar:<uid>`; shows [fallback] until loaded.
class TsImage extends ConsumerWidget {
  final String imageKey;
  final double size;
  final Widget fallback;
  final bool round;
  const TsImage(this.imageKey,
      {super.key, this.size = 20, this.fallback = const SizedBox.shrink(), this.round = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverProvider.select((s) => s.imageRev));
    final bytes = ref.read(serverProvider.notifier).image(imageKey);
    if (bytes == null) return SizedBox(width: size, height: size, child: fallback);
    Widget img = Image.memory(bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SizedBox(width: size, height: size, child: fallback));
    if (round) img = ClipOval(child: img);
    return img;
  }
}
