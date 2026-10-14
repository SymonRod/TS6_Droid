// Account import end to end over a synthetic service: login -> unwrap ->
// read-only pull -> validation -> secure storage. Real Rust engine, synthetic
// replies (tools/myts/pull_fixture.py); no network, no real account.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/import_controller.dart';
import 'package:ts6_flutter/src/state/onboarding_controller.dart';

import 'fixtures/synthetic_pull.dart';
import 'import_helpers.dart';
import 'myts_helpers.dart';
import 'myts_rust.dart';

const _owner = 'alice@example.com';

void main() {
  setUpAll(initRustForTests);
  late World w;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    w = World();
    addTearDown(() => w.container.dispose());
  });

  Future<bool?> flag() async =>
      (await SharedPreferences.getInstance()).getBool(OnboardingStore.completeKey);

  /// Sign in as the app does, with the first-setup state already loaded.
  Future<ImportState> signIn(World w, {String password = fixturePassword}) async {
    await w.container.read(onboardingProvider.future);
    await w.container.read(myTsProvider.notifier).login(fixtureEmail, password);
    return w.container.read(myTsImportProvider);
  }

  void expectNothingStored(World w) {
    expect(w.vaultBackend.writes, 0);
    expect(w.identities.creates, 0, reason: 'no identity may be generated');
  }

  group('empty app', () {
    test('imports every supported identity and bookmark automatically', () async {
      final s = await signIn(w);
      expect(s.phase, ImportPhase.done);
      expect(s.report!.addedIdentities, 2);
      expect(s.report!.addedBookmarks, 3);
      expect(w.identities.creates, 0, reason: 'no identity may be generated');
      expect(w.identities.requests, 0);

      final state = await w.vault.load();
      expect(state.identities.map((i) => i.uid), [fixtureUidA, fixtureUidB]);
      expect(state.identities.map((i) => i.counter), [BigInt.zero, fixtureCounterB]);
      expect(state.identities.map((i) => i.cloudId), ['cloud-identity-a', 'cloud-identity-b']);
      expect(state.identities.every((i) => i.owner == _owner), isTrue);
      expect(state.identities.map((i) => i.cloudDefault), [true, true]);
      expect(state.identities[1].desktopString, fixtureDesktopB);

      final byCloud = {for (final b in state.bookmarks) b.cloudId: b};
      expect(byCloud['cloud-bookmark-1']!.identityRef, '');
      expect(byCloud['cloud-bookmark-2']!.identityRef, isNull);
      expect(byCloud['cloud-bookmark-3']!.identityRef, 'cloud-identity-b');
      expect(byCloud['cloud-bookmark-1']!.serverPassword, 'synthetic-pw-1');
      expect(byCloud['cloud-bookmark-1']!.connectAddress, 'one.example.invalid:9987');
      expect(byCloud['cloud-bookmark-3']!.connectAddress, 'three.example.invalid');
      // The cloud reference is never turned into a choice.
      expect(state.links, isEmpty);
    });

    test('setup is complete only afterwards, and remembered across restarts', () async {
      await w.container.read(onboardingProvider.future);
      expect(w.container.read(onboardingProvider).requireValue.complete, isFalse);
      await signIn(w);
      expect(w.container.read(onboardingProvider).requireValue.complete, isTrue);
      expect(await flag(), true);

      final again = w.restart();
      addTearDown(again.dispose);
      expect((await again.read(onboardingProvider.future)).complete, isTrue);

      // Even if the marker is lost, the stored data is recognized.
      SharedPreferences.setMockInitialValues({});
      final noFlag = w.restart();
      addTearDown(noFlag.dispose);
      expect((await noFlag.read(onboardingProvider.future)).complete, isTrue);
    });

    test('secrets stay in secure storage, not in preferences', () async {
      await signIn(w);
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        final value = '${prefs.get(key)}';
        expect(value, isNot(contains(fixtureDesktopA)), reason: key);
        expect(value, isNot(contains('synthetic-pw-1')), reason: key);
      }
      final sessionStored = await w.sessionBackend.read('myts_session');
      expect(sessionStored, 'synthetic-session');
    });

    test('the request is one read-only POST with the receive caps', () async {
      await signIn(w);
      expect(w.service.syncCalls, hasLength(1));
      final call = w.service.syncCalls.single;
      expect(call.uri, Uri.https('clientapi.myteamspeak.com', '/synchronization'));
      expect(call.headers['content-type'], 'application/ts3cloud');
      expect(call.maxBytes, 8 * 1024 * 1024);
      expect(String.fromCharCodes(call.body.sublist(1, 19)), 'requestServerItems');
      expect(w.service.calls.first.maxBytes, 1024 * 1024);
      expect(w.service.calls.map((c) => c.uri.path), ['/authentication', '/synchronization']);
    });

    test('the same import twice adds nothing and writes nothing', () async {
      await signIn(w);
      final writes = w.vaultBackend.writes;
      final before = await w.vaultBackend.read(AccountVault.storageKey);
      await w.container.read(myTsImportProvider.notifier).startFromStoredSession(fixturePassword);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.done);
      expect(s.report!.hasChanges, isFalse);
      expect(s.report!.unchangedIdentities, 2);
      expect(s.report!.unchangedBookmarks, 3);
      expect(w.vaultBackend.writes, writes);
      expect(await w.vaultBackend.read(AccountVault.storageKey), before);
      expect(w.identities.creates, 0);
    });

    test('invalid items are skipped and reported, valid ones are imported', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, fixturePullPartlyInvalid);
      final s = await signIn(w);
      expect(s.phase, ImportPhase.done);
      expect(s.report!.invalidIdentities, 1);
      expect(s.report!.invalidBookmarks, 1);
      final state = await w.vault.load();
      expect(state.identities.map((i) => i.cloudId), ['cloud-identity-a']);
      expect(state.bookmarks.map((b) => b.cloudId), ['cloud-bookmark-1']);
    });

    test('a duplicate key under another cloud ID is not added twice', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, fixturePullDuplicateUid);
      final s = await signIn(w);
      expect(s.report!.addedIdentities, 1);
      expect(s.report!.duplicateIdentities, 1);
      expect((await w.vault.load()).identities, hasLength(1));
    });

    test('an empty cloud stores nothing, generates nothing, completes nothing', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, fixturePullEmpty);
      final s = await signIn(w);
      expect(s.phase, ImportPhase.nothingToImport);
      expectNothingStored(w);
      expect(await flag(), isNull);
      expect(w.container.read(onboardingProvider).requireValue.complete, isFalse);
    });
  });

  group('failures leave the app untouched and unfinished', () {
    Future<void> expectFailed(World w, ImportFailure failure) async {
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.failed);
      expect(s.failure, failure);
      expectNothingStored(w);
      expect(await flag(), isNull);
      expect(w.container.read(onboardingProvider).requireValue.complete, isFalse);
      expect(await w.vaultBackend.read(AccountVault.storageKey), isNull);
    }

    test('network error', () async {
      w.service.sync = (_) async => throw const SocketException('synthetic');
      await signIn(w);
      await expectFailed(w, ImportFailure.network);
    });

    test('timeout', () async {
      w.service.sync = (_) async => throw TimeoutException('synthetic');
      await signIn(w);
      await expectFailed(w, ImportFailure.network);
    });

    test('reply above the receive cap', () async {
      w.service.sync = (_) async => throw const MyTsResponseRejected();
      await signIn(w);
      await expectFailed(w, ImportFailure.invalidData);
    });

    test('HTTP error body is not parsed', () async {
      w.service.sync = (_) async => MyTsHttpResponse(503, Uint8List.fromList([1, 2, 3]));
      await signIn(w);
      await expectFailed(w, ImportFailure.service);
    });

    test('expired session', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, tvarintField(1, 102));
      await signIn(w);
      await expectFailed(w, ImportFailure.sessionExpired);
    });

    test('other service status', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, tvarintField(1, 999));
      await signIn(w);
      await expectFailed(w, ImportFailure.service);
    });

    test('garbage reply', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, Uint8List.fromList([0xff, 0xff, 0xff]));
      await signIn(w);
      await expectFailed(w, ImportFailure.invalidData);
    });

    test('tampered item data fails the whole batch', () async {
      w.service.sync = (_) async => MyTsHttpResponse(200, fixturePullTampered);
      await signIn(w);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.failed);
      expect(s.failure, anyOf(ImportFailure.integrity, ImportFailure.invalidData));
      expectNothingStored(w);
      expect(await flag(), isNull);
    });

    test('missing wrapped key: unwrap fails closed, no pull is sent', () async {
      w.service.loginKey = Uint8List(0);
      await signIn(w);
      await expectFailed(w, ImportFailure.unlock);
      expect(w.service.syncCalls, isEmpty);
    });

    test('altered wrapped key', () async {
      w.service.loginKey = Uint8List.fromList([...fixtureWrappedKey]..[40] ^= 1);
      await signIn(w);
      await expectFailed(w, ImportFailure.unlock);
      expect(w.service.syncCalls, isEmpty);
    });

    test('wrong password cannot unwrap', () async {
      await signIn(w, password: 'not the password');
      await expectFailed(w, ImportFailure.unlock);
      expect(w.service.syncCalls, isEmpty);
    });

    test('persistence failure keeps the old state and can be retried', () async {
      w.vaultBackend.failWrites = true;
      await signIn(w);
      await expectFailed(w, ImportFailure.storage);
      expect(w.container.read(myTsProvider).status, MyTsStatus.signedIn);

      w.vaultBackend.failWrites = false;
      await w.container.read(myTsImportProvider.notifier).startFromStoredSession(fixturePassword);
      expect(w.container.read(myTsImportProvider).phase, ImportPhase.done);
      expect((await w.vault.load()).identities, hasLength(2));
      expect(await flag(), true);
    });

    test('a write that is silently lost is detected', () async {
      w.vaultBackend.dropWrites = true;
      await signIn(w);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.failed);
      expect(s.failure, ImportFailure.storage);
      expect(await w.vaultBackend.read(AccountVault.storageKey), isNull);
      expect(await flag(), isNull);
      expect(w.identities.creates, 0);
    });

    test('a corrupt vault blocks the import and is not overwritten', () async {
      await w.vaultBackend.write(AccountVault.storageKey, 'garbage');
      final writes = w.vaultBackend.writes;
      await w.container.read(myTsProvider.notifier).login(fixtureEmail, fixturePassword);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.failed);
      expect(s.failure, ImportFailure.storage);
      expect(await w.vaultBackend.read(AccountVault.storageKey), 'garbage');
      expect(w.vaultBackend.writes, writes);
    });

    test('retrying without a stored session reports it', () async {
      await w.container.read(myTsImportProvider.notifier).startFromStoredSession('x');
      expect(w.container.read(myTsImportProvider).failure, ImportFailure.noSession);
    });
  });

  group('app with existing data', () {
    test('download waits for confirmation and stores nothing before it', () async {
      w.identities.present = true;
      final s = await signIn(w);
      expect(s.phase, ImportPhase.awaitingConfirmation);
      expect(s.report!.addedIdentities, 2);
      expect(w.vaultBackend.writes, 0);
      expect(await w.vaultBackend.read(AccountVault.storageKey), isNull);
      expect(w.identities.creates, 0);
    });

    test('confirming adds the data and keeps the local identity', () async {
      w.identities.present = true;
      await signIn(w);
      await w.container.read(myTsImportProvider.notifier).confirm();
      expect(w.container.read(myTsImportProvider).phase, ImportPhase.done);
      expect((await w.vault.load()).identities, hasLength(2));
      expect(w.identities.present, isTrue);
      expect(w.identities.creates, 0);
    });

    test('cancelling stores nothing and drops the download', () async {
      w.identities.present = true;
      await signIn(w);
      w.container.read(myTsImportProvider.notifier).cancel();
      expect(w.container.read(myTsImportProvider).phase, ImportPhase.idle);
      await w.container.read(myTsImportProvider.notifier).confirm();
      expect(w.vaultBackend.writes, 0);
    });

    test('a key the device already has is not offered twice', () async {
      w.identities
        ..present = true
        ..localUid = fixtureUidA;
      final s = await signIn(w);
      expect(s.report!.addedIdentities, 1);
      expect(s.report!.duplicateIdentities, 1);
      await w.container.read(myTsImportProvider.notifier).confirm();
      expect((await w.vault.load()).identities.map((i) => i.uid), [fixtureUidB]);
    });

    test('existing local bookmarks alone also take the explicit path', () async {
      SharedPreferences.setMockInitialValues({
        'bookmarks_json': '[{"address":"local.example.invalid:9987","nickname":"Me"}]',
      });
      final s = await signIn(w);
      expect(s.phase, ImportPhase.awaitingConfirmation);
      expectNothingStored(w);
    });

    test('unreadable local data never imports silently', () async {
      w.identities.readFails = true;
      // Setup state itself cannot be read, so the app is not "known empty".
      await w.container.read(myTsProvider.notifier).login(fixtureEmail, fixturePassword);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.failed);
      expect(s.failure, ImportFailure.storage);
      expect(w.vaultBackend.writes, 0);
    });

    test('an import that fails on confirm leaves the vault as it was', () async {
      w.identities.present = true;
      await signIn(w);
      w.vaultBackend.failWrites = true;
      await w.container.read(myTsImportProvider.notifier).confirm();
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.awaitingConfirmation);
      expect(s.failure, ImportFailure.storage);
      expect(await w.vaultBackend.read(AccountVault.storageKey), isNull);
      w.vaultBackend.failWrites = false;
      await w.container.read(myTsImportProvider.notifier).confirm();
      expect(w.container.read(myTsImportProvider).phase, ImportPhase.done);
    });

    test('data that appears during the download turns auto-import into a confirmation', () async {
      w.service.sync = (_) async {
        w.identities.present = true; // the user skipped setup meanwhile
        return MyTsHttpResponse(200, fixturePullFull);
      };
      final s = await signIn(w);
      expect(s.phase, ImportPhase.awaitingConfirmation);
      expect(w.vaultBackend.writes, 0);
    });

    test('a changed cloud copy never replaces what is stored', () async {
      await signIn(w);
      final stored = await w.vault.load();
      w.service.sync = (_) async => MyTsHttpResponse(200, fixturePullChanged);
      await w.container.read(myTsImportProvider.notifier).startFromStoredSession(fixturePassword);
      final s = w.container.read(myTsImportProvider);
      expect(s.phase, ImportPhase.done);
      expect(s.report!.conflictBookmarks, 1);
      expect(s.report!.hasChanges, isFalse);
      final after = await w.vault.load();
      expect(after.bookmarks.map((b) => b.serverPassword), stored.bookmarks.map((b) => b.serverPassword));
    });
  });

  group('sign-out', () {
    test('keeps imported data and only removes the session keys', () async {
      await signIn(w);
      await w.container.read(myTsProvider.notifier).logout();
      expect(await w.sessionBackend.read('myts_session'), isNull);
      expect(await w.sessionBackend.read('myts_wrapped_key'), isNull);
      expect((await w.vault.load()).identities, hasLength(2));
      expect(w.container.read(myTsImportProvider).phase, ImportPhase.idle);
    });
  });
}
