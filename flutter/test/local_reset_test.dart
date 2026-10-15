// Every sign-in starts from scratch: warning first, then a full local wipe.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/l10n/app_localizations.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/local_reset.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/state/onboarding_controller.dart';
import 'package:ts6_flutter/src/ui/myts_login_screen.dart';

import 'onboarding_helpers.dart';

class _FakeReset extends LocalReset {
  final bool data;
  _FakeReset(super.ref, this.data);

  @override
  Future<bool> hasData() async => data;
}

Widget _login(TestMyTsController controller, {required bool hasData}) =>
    ProviderScope(
      overrides: [
        myTsProvider.overrideWith(() => controller),
        localResetProvider.overrideWith((ref) => _FakeReset(ref, hasData)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MyTsLoginScreen(),
      ),
    );

Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
  await tester.enterText(find.byType(TextField).at(1), 'pw');
  final button = find.widgetWithText(FilledButton, 'Sign in');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('LocalReset', () {
    late MemoryMyTsSecureBackend backend;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'bookmarks_json': '[{"address":"ts.example.org"}]',
        'last_bookmark_address': 'ts.example.org',
        OnboardingStore.completeKey: true,
        'audio_gain': 1.5,
      });
      backend = MemoryMyTsSecureBackend();
      container = ProviderContainer(
        overrides: [
          myTsSessionStoreProvider.overrideWithValue(MyTsSessionStore(backend)),
          onboardingStoreProvider.overrideWithValue(
            OnboardingStore(
              identities: TestIdentityStore(),
              bookmarks: BookmarkStore(),
              vault: AccountVault(backend),
            ),
          ),
        ],
      );
    });
    tearDown(() => container.dispose());

    test(
      'removes secure data, bookmarks and the setup marker, keeps settings',
      () async {
        await backend.write(MyTsSessionStore.kSession, 's');
        await backend.write(AccountVault.storageKey, '{}');
        await backend.write('myts_history_v1_abc', 'snapshot');
        await backend.write('myts_contacts_v1_abc', 'contacts');
        expect(await container.read(localResetProvider).hasData(), isTrue);

        await container.read(localResetProvider).wipe();

        expect(await backend.keys(), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('bookmarks_json'), isNull);
        expect(prefs.getString('last_bookmark_address'), isNull);
        expect(prefs.getBool(OnboardingStore.completeKey), isNull);
        expect(prefs.getDouble('audio_gain'), 1.5);
        expect(await container.read(localResetProvider).hasData(), isFalse);
      },
    );

    test('the remember-password preference alone is not "data"', () async {
      SharedPreferences.setMockInitialValues({});
      await backend.write(MyTsSessionStore.kRememberPassword, '0');
      expect(await container.read(localResetProvider).hasData(), isFalse);
    });
  });

  group('login screen', () {
    testWidgets('warns first; cancelling signs nothing in', (tester) async {
      final controller = TestMyTsController();
      await tester.pumpWidget(_login(controller, hasData: true));
      await _submit(tester);
      expect(find.text('Start from scratch?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.loginCalls, 0);
    });

    testWidgets('confirming signs in with the reset flag', (tester) async {
      final controller = TestMyTsController();
      await tester.pumpWidget(_login(controller, hasData: true));
      await _submit(tester);
      await tester.tap(find.text('Delete and sign in'));
      await tester.pumpAndSettle();
      expect(controller.loginCalls, 1);
      expect(controller.lastResetLocalData, isTrue);
    });

    testWidgets('nothing stored: no warning', (tester) async {
      final controller = TestMyTsController();
      await tester.pumpWidget(_login(controller, hasData: false));
      await _submit(tester);
      expect(find.text('Start from scratch?'), findsNothing);
      expect(controller.loginCalls, 1);
    });
  });
}
