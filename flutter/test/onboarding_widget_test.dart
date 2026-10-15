import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/l10n/app_localizations.dart';
import 'package:ts6_flutter/main.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/state/onboarding_controller.dart';
import 'package:ts6_flutter/src/state/server_controller.dart';
import 'package:ts6_flutter/src/ui/connection_screen.dart';
import 'package:ts6_flutter/src/ui/myts_login_screen.dart';
import 'package:ts6_flutter/src/ui/onboarding_screen.dart';

import 'onboarding_helpers.dart';

Future<ProviderContainer> mountApp(
  WidgetTester tester,
  TestIdentityStore identities, {
  TestMyTsController? account,
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  final c = ProviderContainer(
    overrides: [
      identityStoreProvider.overrideWithValue(identities),
      accountVaultProvider.overrideWithValue(memoryVault()),
      myTsSessionStoreProvider.overrideWithValue(
        MyTsSessionStore(MemoryMyTsSecureBackend()),
      ),
      serverProvider.overrideWith(TestServerController.new),
      myTsProvider.overrideWith(() => account ?? TestMyTsController()),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: ref.watch(routerProvider),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return c;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('storage inspection gates connections and server deep links', (
    tester,
  ) async {
    final identities = TestIdentityStore()..inspectionGate = Completer<void>();
    final c = await mountApp(tester, identities, settle: false);
    await tester.pump();
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    c.read(routerProvider).go('/server');
    await tester.pump();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    identities.inspectionGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Skip sign-in'), findsOneWidget);
    expect(identities.requests, 0);
  });

  testWidgets('fresh setup gates connections; skip survives an app restart', (
    tester,
  ) async {
    final identities = TestIdentityStore();
    final c = await mountApp(tester, identities);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(identities.creates, 0);

    await tapVisible(tester, find.text('Skip sign-in'));
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(c.read(onboardingProvider).requireValue.complete, true);
    expect(identities.creates, 1);
    await tester.pumpWidget(const SizedBox());
    await mountApp(tester, identities);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(identities.creates, 1);
    await tapVisible(tester, find.byTooltip('myTeamSpeak'));
    expect(find.byType(MyTsLoginScreen), findsOneWidget);
    expect(find.text('Back to setup'), findsNothing);
  });

  testWidgets('existing identity bypasses welcome even without bookmarks', (
    tester,
  ) async {
    final identities = TestIdentityStore()..present = true;
    await mountApp(tester, identities);
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(identities.requests, 0);
  });

  testWidgets('storage error blocks setup and retries without replacing data', (
    tester,
  ) async {
    final identities = TestIdentityStore()..readFails = true;
    await mountApp(tester, identities);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(find.text('Skip sign-in'), findsNothing);
    expect(identities.requests, 0);
    identities.readFails = false;
    await tapVisible(tester, find.text('Retry'));
    expect(find.text('Skip sign-in'), findsOneWidget);
  });

  testWidgets('successful sign-in is not import or setup completion', (
    tester,
  ) async {
    final identities = TestIdentityStore();
    final account = TestMyTsController();
    final c = await mountApp(tester, identities, account: account);
    await tapVisible(tester, find.text('Sign in with myTeamSpeak'));
    await tester.enterText(
      find.byType(TextField).at(0),
      'synthetic@example.invalid',
    );
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tapVisible(tester, find.text('Sign in'));
    expect(find.text('Import your account data'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(c.read(onboardingProvider).requireValue.complete, false);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completeKey,
      ),
      isNull,
    );
    expect(identities.requests, 0);
    // Connection deep links cannot bypass the pending import.
    c.read(routerProvider).go('/');
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tapVisible(tester, find.text('Sign in with myTeamSpeak'));
    expect(find.text('Import your account data'), findsOneWidget);
    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Back to setup'),
    );
    await tapVisible(tester, find.text('Skip sign-in'));
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(identities.creates, 1);
  });

  testWidgets('restored account session alone does not bypass fresh setup', (
    tester,
  ) async {
    final identities = TestIdentityStore();
    await mountApp(
      tester,
      identities,
      account: TestMyTsController(
        initial: const MyTsState(status: MyTsStatus.signedIn),
      ),
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(identities.requests, 0);
    await tapVisible(tester, find.text('Sign in with myTeamSpeak'));
    expect(find.text('Import your account data'), findsOneWidget);
  });

  testWidgets('login retains OTP and credential failure presentation', (
    tester,
  ) async {
    final account = TestMyTsController(
      loginResult: const MyTsState(
        status: MyTsStatus.otpNeeded,
        failure: MyTsFailure.otpRequired,
      ),
    );
    await mountApp(tester, TestIdentityStore(), account: account);
    await tapVisible(tester, find.text('Sign in with myTeamSpeak'));
    await tester.enterText(
      find.byType(TextField).at(0),
      'synthetic@example.invalid',
    );
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tapVisible(tester, find.text('Sign in'));
    expect(find.text('One-time code'), findsOneWidget);
    account.loginResult = const MyTsState(failure: MyTsFailure.credentials);
    await tapVisible(tester, find.text('Sign in'));
    expect(find.text('Wrong email or password'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets(
    'password can be revealed and is cleared after successful sign-in',
    (tester) async {
      await mountApp(tester, TestIdentityStore());
      await tapVisible(tester, find.text('Sign in with myTeamSpeak'));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        true,
      );
      await tapVisible(tester, find.byTooltip('Show password'));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        false,
      );
      await tester.enterText(
        find.byType(TextField).at(0),
        'synthetic@example.invalid',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'synthetic-password',
      );
      await tapVisible(tester, find.text('Sign in'));
      await tapVisible(tester, find.text('Sign out'));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        true,
      );
    },
  );

  testWidgets(
    'later login warns about the reset and keeps the local identity file',
    (tester) async {
      const saved = '[{"address":"synthetic.invalid:9987","nickname":"Test"}]';
      SharedPreferences.setMockInitialValues({'bookmarks_json': saved});
      final identities = TestIdentityStore()..present = true;
      final c = await mountApp(tester, identities);
      c.read(routerProvider).push('/myts');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'synthetic@example.invalid',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'synthetic-password',
      );
      await tapVisible(tester, find.text('Sign in'));
      // Saved bookmarks exist: the sign-in asks before wiping and starting over.
      expect(find.text('Start from scratch?'), findsOneWidget);
      await tapVisible(tester, find.text('Delete and sign in'));
      await tapVisible(tester, find.text('Sign out'));
      expect(identities.requests, 0);
      expect(identities.present, true);
      expect(c.read(onboardingProvider).requireValue.complete, true);
    },
  );

  testWidgets('failed skip shows recovery and does not navigate', (
    tester,
  ) async {
    final identities = TestIdentityStore()..createFails = true;
    await mountApp(tester, identities);
    await tapVisible(tester, find.text('Skip sign-in'));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    identities.createFails = false;
    await tapVisible(tester, find.text('Skip sign-in'));
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  testWidgets('pending skip disables both choices', (tester) async {
    final identities = TestIdentityStore()..creationGate = Completer<void>();
    await mountApp(tester, identities);
    await tester.ensureVisible(find.text('Skip sign-in'));
    await tester.tap(find.text('Skip sign-in'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    identities.creationGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  for (final locale in ['en', 'it', 'fr']) {
    testWidgets('welcome fits small screens with large text in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mountApp(tester, TestIdentityStore(), locale: Locale(locale));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(OutlinedButton));
      expect(tester.takeException(), isNull);
    });
  }
}
