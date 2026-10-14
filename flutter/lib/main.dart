import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'src/rust/frb_generated.dart';
import 'src/state/onboarding_controller.dart';
import 'src/state/server_controller.dart';
import 'src/ui/connection_screen.dart';
import 'src/ui/myts_login_screen.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/server_screen.dart';
import 'src/ui/stream_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: TsApp()));
}

/// The connection state picks the screen: `/` when idle, `/server` (and
/// `/server/stream`) when connected.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(serverProvider.select((s) => s.status), (_, _) => refresh.value++);
  ref.listen(onboardingProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final setup = ref.read(onboardingProvider).asData?.value;
      // The connection screen (and auto-reconnect) must not run before the
      // initial choice or while local storage is still being inspected.
      if (setup == null) return loc == '/setup' ? null : '/setup';
      if (!setup.complete) {
        return (loc == '/setup' || loc == '/myts') ? null : '/setup';
      }
      if (loc == '/setup') return '/';
      final connected = ref.read(serverProvider).status == ConnStatus.connected;
      // The myTeamSpeak login screen is usable while disconnected.
      if (!connected) return (loc == '/' || loc == '/myts') ? null : '/';
      if (loc == '/') return '/server';
      if (loc == '/server/stream' &&
          ref.read(serverProvider.notifier).viewer == null) {
        return '/server';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (_, _) => const ConnectionScreen()),
      GoRoute(
        path: '/myts',
        builder: (_, _) => MyTsLoginScreen(
          initialSetup:
              ref.read(onboardingProvider).asData?.value.complete == false,
        ),
      ),
      GoRoute(
        path: '/server',
        builder: (_, _) => const ServerScreen(),
        routes: [
          GoRoute(
            path: 'stream',
            builder: (_, _) =>
                StreamScreen(viewer: ref.read(serverProvider.notifier).viewer!),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class TsApp extends ConsumerWidget {
  const TsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DynamicColorBuilder(
    builder: (light, dark) => MaterialApp.router(
      title: 'TS6 Droid',
      theme: buildTheme(Brightness.light, dynamic: light?.harmonized()),
      darkTheme: buildTheme(Brightness.dark, dynamic: dark?.harmonized()),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
