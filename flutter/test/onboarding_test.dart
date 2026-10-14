import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/state/onboarding_controller.dart';
import 'package:ts6_flutter/src/state/server_controller.dart';

import 'onboarding_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestIdentityStore identities;
  late OnboardingStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    identities = TestIdentityStore();
    store = OnboardingStore(identities: identities, bookmarks: BookmarkStore());
  });

  test('empty app is detected without generating an identity', () async {
    expect(await store.isComplete(), false);
    expect(identities.creates, 0);
    expect(identities.requests, 0);
  });

  test(
    'existing identity with no bookmarks bypasses setup without replacement',
    () async {
      identities.present = true;
      expect(await store.isComplete(), true);
      expect(identities.requests, 0);
    },
  );

  test('saved bookmarks alone are not classified as a fresh app', () async {
    SharedPreferences.setMockInitialValues({
      'bookmarks_json':
          '[{"address":"synthetic.invalid:9987","nickname":"Test"}]',
    });
    expect(await store.isComplete(), true);
    expect(identities.requests, 0);
  });

  for (final raw in ['broken', '{}', '[null]', '[{}]', '[{"address":42}]']) {
    test('invalid bookmark data is not treated as absent: $raw', () async {
      SharedPreferences.setMockInitialValues({'bookmarks_json': raw});
      await expectLater(store.isComplete(), throwsA(anything));
      await expectLater(store.skip(), throwsA(anything));
      expect(identities.requests, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('bookmarks_json'),
        raw,
      );
    });
  }

  test(
    'unreadable identity blocks first setup without creating another',
    () async {
      identities.readFails = true;
      await expectLater(store.isComplete(), throwsStateError);
      await expectLater(store.skip(), throwsStateError);
      expect(identities.requests, 0);
    },
  );

  test(
    'skip saves completion only after a usable identity and reuses it on retry',
    () async {
      await store.skip();
      expect(identities.creates, 1);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          OnboardingStore.completeKey,
        ),
        true,
      );
      final restarted = OnboardingStore(
        identities: identities,
        bookmarks: BookmarkStore(),
      );
      expect(await restarted.isComplete(), true);
      await restarted.skip();
      expect(identities.creates, 1);
    },
  );

  test(
    'controller serializes skip and waits for identity persistence',
    () async {
      identities.creationGate = Completer<void>();
      final c = ProviderContainer(
        overrides: [
          identityStoreProvider.overrideWithValue(identities),
          accountVaultProvider.overrideWithValue(memoryVault()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(onboardingProvider.future);
      final first = c.read(onboardingProvider.notifier).skip();
      await c.read(onboardingProvider.notifier).skip();
      expect(c.read(onboardingProvider).requireValue.busy, true);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          OnboardingStore.completeKey,
        ),
        isNull,
      );
      identities.creationGate!.complete();
      await first;
      expect(identities.requests, 1);
      expect(c.read(onboardingProvider).requireValue.complete, true);
    },
  );

  test('failed skip remains incomplete and can be retried', () async {
    identities.createFails = true;
    final c = ProviderContainer(
      overrides: [
          identityStoreProvider.overrideWithValue(identities),
          accountVaultProvider.overrideWithValue(memoryVault()),
        ],
    );
    addTearDown(c.dispose);
    await c.read(onboardingProvider.future);
    await c.read(onboardingProvider.notifier).skip();
    expect(c.read(onboardingProvider).requireValue.complete, false);
    expect(c.read(onboardingProvider).requireValue.failed, true);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completeKey,
      ),
      isNull,
    );
    identities.createFails = false;
    await c.read(onboardingProvider.notifier).skip();
    expect(c.read(onboardingProvider).requireValue.complete, true);
  });

  group('imported account data', () {
    test('a vault with data is not a fresh app, even without marker or identity file', () async {
      final vault = memoryVault();
      await vault.write(VaultState(identities: [
        VaultIdentity(
          id: 'i-1',
          owner: 'o',
          cloudId: 'c',
          cloudVersion: 'v',
          uid: 'u',
          counter: BigInt.zero,
          desktopString: 'k',
        ),
      ]));
      final s = OnboardingStore(identities: identities, bookmarks: BookmarkStore(), vault: vault);
      expect(await s.isComplete(), true);
      expect(identities.requests, 0);
    });

    test('an empty vault is a fresh app', () async {
      final s = OnboardingStore(identities: identities, bookmarks: BookmarkStore(), vault: memoryVault());
      expect(await s.isComplete(), false);
    });

    test('an unreadable vault is never classified as empty', () async {
      final backend = MemoryMyTsSecureBackend();
      await backend.write(AccountVault.storageKey, 'garbage');
      final s = OnboardingStore(
        identities: identities,
        bookmarks: BookmarkStore(),
        vault: AccountVault(backend),
      );
      await expectLater(s.isComplete(), throwsA(anything));
      await expectLater(s.skip(), throwsA(anything));
      expect(identities.requests, 0);
      expect(await backend.read(AccountVault.storageKey), 'garbage');
    });

    test('skip with a vault of imported data does not touch it', () async {
      final backend = MemoryMyTsSecureBackend();
      final vault = AccountVault(backend);
      final s = OnboardingStore(identities: identities, bookmarks: BookmarkStore(), vault: vault);
      await s.skip(); // fresh app: creates the local identity as before
      expect(identities.creates, 1);
      expect(await backend.read(AccountVault.storageKey), isNull);
    });
  });
}
