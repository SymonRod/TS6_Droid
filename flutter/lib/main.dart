import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/rust/frb_generated.dart';
import 'src/ui/connection_screen.dart';
import 'src/ui/server_screen.dart';
import 'src/state/server_controller.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: TsApp()));
}

class TsApp extends StatelessWidget {
  const TsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TS6 Droid',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Root(),
      );
}

/// No router yet: the connection state picks the screen.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(serverProvider.select((s) => s.status == ConnStatus.connected));
    return connected ? const ServerScreen() : const ConnectionScreen();
  }
}
