// Choosing the identity for a connection: never generated, never guessed, the
// cloud reference never used as a key. Real Rust identity code, synthetic data.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/import_plan.dart';
import 'package:ts6_flutter/src/data/server_bookmark.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;
import 'package:ts6_flutter/src/state/identity_resolver.dart';

import 'fixtures/synthetic_pull.dart';
import 'myts_rust.dart';

void main() {
  setUpAll(initRustForTests);
  late Directory dir;
  late MemoryMyTsSecureBackend backend;
  late AccountVault vault;
  late IdentityStore legacy;
  late IdentityResolver resolver;
  late VaultState imported;
  late ServerBookmark bookmark; // imported, cloud reference points at B

  rs.MyTsCloudIdentity cloud(String id, String desktop, String uid, BigInt counter, String? nick) =>
      rs.MyTsCloudIdentity(
        cloudId: id,
        itemVersion: 'v',
        desktopString: desktop,
        uid: uid,
        counter: counter,
        nickname: nick,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('ts6-resolver-');
    addTearDown(() => dir.delete(recursive: true));
    backend = MemoryMyTsSecureBackend();
    vault = AccountVault(backend);
    legacy = IdentityStore(supportDirectory: () async => dir);
    resolver = IdentityResolver(vault: vault, legacy: legacy);
    final plan = planImport(
      current: VaultState.empty,
      owner: 'alice@example.com',
      batch: rs.MyTsImportBatch(
        identities: [
          cloud('cloud-identity-a', fixtureDesktopA, fixtureUidA, BigInt.zero, 'Alice'),
          cloud('cloud-identity-b', fixtureDesktopB, fixtureUidB, fixtureCounterB, null),
        ],
        bookmarks: [
          rs.MyTsCloudBookmark(
            cloudId: 'cloud-bookmark-3',
            itemVersion: 'v',
            address: 'three.example.invalid',
            identity: 'cloud-identity-b',
          ),
        ],
        invalidIdentityIds: [],
        invalidBookmarkIds: [],
        tombstones: 0,
        unsupportedItems: 0,
        globalVersion: '',
        classVersions: const [],
      ),
    );
    imported = plan.next;
    await vault.write(imported);
    bookmark = ServerBookmark(
      address: 'three.example.invalid',
      nickname: 'Me',
      vaultId: imported.bookmarks.single.id,
    );
  });

  Future<String?> never(List<IdentityOption> o, {required bool canCreate}) async =>
      fail('must not ask');

  test('options list the imported identities without choosing one', () async {
    final options = await resolver.options();
    expect(options.map((o) => o.uid), [fixtureUidA, fixtureUidB]);
  });

  test('an imported bookmark asks, even though its reference names identity B', () async {
    List<IdentityOption>? offered;
    final r = await resolver.resolve(
      bookmark,
      ask: (o, {required canCreate}) async {
        offered = o;
        return null; // the user cancels
      },
    );
    expect(r, isNull);
    expect(offered!.map((o) => o.uid), [fixtureUidA, fixtureUidB]);
    expect((await vault.load()).links, isEmpty);
    expect(await File('${dir.path}/identity.txt').exists(), isFalse);
  });

  test('background reconnect never prompts and never connects', () async {
    final r = await resolver.resolve(bookmark, ask: never, interactive: false);
    expect(r, isNull);
  });

  test('the choice is kept as a local link and reused without asking', () async {
    final b = imported.identities[0];
    final first = await resolver.resolve(
      bookmark,
      ask: (o, {required canCreate}) async => b.id,
    );
    expect(first!.identity.uniqueId(), fixtureUidA);
    expect(first.nicknameHint, 'Alice');

    final state = await vault.load();
    expect(state.links[bookmark.vaultId], b.id);
    // The cloud reference is untouched by the local choice.
    expect(state.bookmarks.single.identityRef, 'cloud-identity-b');

    final second = AccountVault(backend); // restart
    final again = await IdentityResolver(vault: second, legacy: legacy)
        .resolve(bookmark, ask: never);
    expect(again!.identity.uniqueId(), fixtureUidA);
  });

  test('the counter and UID of the chosen identity are preserved', () async {
    final r = await resolver.resolve(
      bookmark,
      ask: (o, {required canCreate}) async => imported.identities[1].id,
    );
    expect(r!.identity.uniqueId(), fixtureUidB);
    expect(r.identity.keyOffset(), fixtureCounterB);
  });

  test('changing the choice replaces only the local link', () async {
    await resolver.resolve(bookmark, ask: (o, {required canCreate}) async => imported.identities[0].id);
    await resolver.choose(bookmark.vaultId!, imported.identities[1].id);
    final r = await resolver.resolve(bookmark, ask: never);
    expect(r!.identity.uniqueId(), fixtureUidB);
  });

  test('a link to an identity that is gone asks again instead of falling back', () async {
    final b = imported.identities[0];
    await resolver.resolve(bookmark, ask: (o, {required canCreate}) async => b.id);
    final trimmed = (await vault.load());
    await vault.write(trimmed.copyWith(identities: [imported.identities[1]]));
    var asked = 0;
    final r = await resolver.resolve(
      bookmark,
      ask: (o, {required canCreate}) async {
        asked++;
        expect(o.map((x) => x.uid), [fixtureUidB]);
        return null;
      },
    );
    expect(r, isNull);
    expect(asked, 1);
  });

  test('an unknown choice from the chooser is rejected', () async {
    final r = await resolver.resolve(bookmark, ask: (o, {required canCreate}) async => 'made-up');
    expect(r, isNull);
    expect((await vault.load()).links, isEmpty);
  });

  test('a stored key that no longer matches its UID is refused', () async {
    final s = await vault.load();
    final swapped = VaultIdentity(
      id: s.identities[0].id,
      owner: s.identities[0].owner,
      cloudId: s.identities[0].cloudId,
      cloudVersion: 'v',
      uid: fixtureUidA,
      counter: BigInt.zero,
      desktopString: fixtureDesktopB, // a different, valid key
    );
    await vault.write(s.copyWith(identities: [swapped, s.identities[1]]));
    await expectLater(
      resolver.resolve(bookmark, ask: (o, {required canCreate}) async => swapped.id),
      throwsStateError,
    );
  });

  test('a corrupt stored key fails without a fallback identity', () async {
    final s = await vault.load();
    final broken = VaultIdentity(
      id: s.identities[0].id,
      owner: s.identities[0].owner,
      cloudId: s.identities[0].cloudId,
      cloudVersion: 'v',
      uid: fixtureUidA,
      counter: BigInt.zero,
      desktopString: 'synthetic-invalid',
    );
    await vault.write(s.copyWith(identities: [broken]));
    await expectLater(
      resolver.resolve(bookmark, ask: (o, {required canCreate}) async => broken.id),
      throwsA(anything),
    );
    expect(await File('${dir.path}/identity.txt').exists(), isFalse);
  });

  group('with a local identity file', () {
    test('own bookmarks and manual addresses use it without asking', () async {
      final local = await legacy.create();
      final r = await resolver.resolve(
        const ServerBookmark(address: 'manual.example.invalid', nickname: 'Me'),
        ask: never,
      );
      expect(r!.identity.uniqueId(), local.uniqueId());
    });

    test('an imported bookmark still asks, and the local identity is an option', () async {
      final local = await legacy.create();
      List<IdentityOption>? offered;
      await resolver.resolve(
        bookmark,
        ask: (o, {required canCreate}) async {
          offered = o;
          expect(canCreate, isFalse);
          return AccountVault.legacyIdentityId;
        },
      );
      expect(offered!.first.id, AccountVault.legacyIdentityId);
      expect(offered!.first.uid, local.uniqueId());
      final again = await resolver.resolve(bookmark, ask: never);
      expect(again!.identity.uniqueId(), local.uniqueId());
    });

    test('a corrupt local identity file is an error, not an absent one', () async {
      await File('${dir.path}/identity.txt').writeAsString('synthetic-invalid');
      await expectLater(
        resolver.resolve(
          const ServerBookmark(address: 'manual.example.invalid', nickname: 'Me'),
          ask: never,
        ),
        throwsA(anything),
      );
      expect(await File('${dir.path}/identity.txt').readAsString(), 'synthetic-invalid');
    });
  });

  group('without any identity', () {
    setUp(() async => backend.write(AccountVault.storageKey, VaultState.empty.encode()));

    test('a manual connection asks and can create one only on request', () async {
      const manual = ServerBookmark(address: 'manual.example.invalid', nickname: 'Me');
      var offeredCreate = false;
      expect(
        await resolver.resolve(manual, ask: (o, {required canCreate}) async {
          offeredCreate = canCreate;
          return null;
        }),
        isNull,
      );
      expect(offeredCreate, isTrue);
      expect(await File('${dir.path}/identity.txt').exists(), isFalse);

      final r = await resolver.resolve(
        manual,
        ask: (o, {required canCreate}) async => IdentityResolver.createLocal,
      );
      expect(r!.identity.uniqueId(), isNotEmpty);
      expect(await File('${dir.path}/identity.txt').exists(), isTrue);
      expect((await vault.load()).links[AccountVault.localDefaultLink],
          AccountVault.legacyIdentityId);
    });
  });
}
