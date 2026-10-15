// Planner and vault: merge rules, atomic persistence, restart. Synthetic data
// only, no Rust library and no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/data/account_vault.dart';
import 'package:ts6_flutter/src/data/import_plan.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;

rs.MyTsCloudIdentity ident(
  String id,
  String uid, {
  int counter = 0,
  String key = 'synthetic-key',
  bool? isDefault,
  String? nickname,
}) => rs.MyTsCloudIdentity(
  cloudId: id,
  itemVersion: 'v1',
  desktopString: '$key-$id',
  uid: uid,
  counter: BigInt.from(counter),
  idName: 'name $id',
  nickname: nickname,
  isDefault: isDefault,
);

rs.MyTsCloudBookmark mark(
  String id, {
  String address = 'host.example.invalid',
  String? identity,
  String? password,
  String version = 'v1',
  int? port,
}) => rs.MyTsCloudBookmark(
  cloudId: id,
  itemVersion: version,
  address: address,
  port: port,
  identity: identity,
  serverPassword: password,
);

rs.MyTsImportBatch batch({
  List<rs.MyTsCloudIdentity> identities = const [],
  List<rs.MyTsCloudBookmark> bookmarks = const [],
  List<String> badIdentities = const [],
  List<String> badBookmarks = const [],
}) => rs.MyTsImportBatch(
  identities: identities,
  bookmarks: bookmarks,
  invalidIdentityIds: badIdentities,
  invalidBookmarkIds: badBookmarks,
  tombstones: 0,
  unsupportedItems: 0,
  globalVersion: '',
  classVersions: const [],
);

class RecordingBackend extends MemoryMyTsSecureBackend {
  int writes = 0;
  bool failWrites = false;
  bool dropWrites = false; // reports success but stores nothing
  bool corruptReadBack = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Synthetic write failure');
    writes++;
    if (dropWrites) return;
    await super.write(key, corruptReadBack ? '$value ' : value);
  }
}

const owner = 'alice@example.com';

void main() {
  group('planImport', () {
    test('several identities keep UID, counter, cloud ID and ownership', () {
      final plan = planImport(
        current: VaultState.empty,
        batch: batch(
          identities: [
            ident('a', 'uid-a', counter: 0, isDefault: true),
            ident('b', 'uid-b', counter: 2792354, isDefault: true),
          ],
        ),
        owner: owner,
      );
      expect(plan.report.addedIdentities, 2);
      final ids = plan.next.identities;
      expect(ids.map((i) => i.uid), ['uid-a', 'uid-b']);
      expect(ids[1].counter, BigInt.from(2792354));
      expect(ids.map((i) => i.cloudId), ['a', 'b']);
      expect(ids.every((i) => i.owner == owner), isTrue);
      // Both flagged default: nothing is picked, the flags stay as received.
      expect(ids.map((i) => i.cloudDefault), [true, true]);
      expect(ids[0].id, vaultItemId('identity', owner, 'a'));
    });

    test('the largest u64 counter survives', () {
      final max = BigInt.parse('18446744073709551615');
      final c = rs.MyTsCloudIdentity(
        cloudId: 'a',
        itemVersion: 'v',
        desktopString: 'k',
        uid: 'u',
        counter: max,
      );
      final plan = planImport(
        current: VaultState.empty,
        batch: batch(identities: [c]),
        owner: owner,
      );
      final restored = VaultState.decode(plan.next.encode());
      expect(restored.identities.single.counter, max);
    });

    test('bookmark references: absent, empty and opaque stay distinct', () {
      final plan = planImport(
        current: VaultState.empty,
        batch: batch(
          identities: [ident('a', 'uid-a')],
          bookmarks: [
            mark('absent'),
            mark('empty', identity: ''),
            mark('opaque', identity: 'a'),
          ],
        ),
        owner: owner,
      );
      final refs = plan.next.bookmarks.map((b) => b.identityRef).toList();
      expect(refs, [null, '', 'a']);
      final restored = VaultState.decode(plan.next.encode());
      expect(restored.bookmarks.map((b) => b.identityRef), [null, '', 'a']);
      // No link is invented from a reference, even one equal to a cloud ID.
      expect(plan.next.links, isEmpty);
    });

    test('importing the same batch twice changes nothing', () {
      final b = batch(
        identities: [ident('a', 'uid-a')],
        bookmarks: [mark('x', password: 'pw')],
      );
      final first = planImport(current: VaultState.empty, batch: b, owner: owner);
      final second = planImport(current: first.next, batch: b, owner: owner);
      expect(second.report.hasChanges, isFalse);
      expect(second.report.unchangedIdentities, 1);
      expect(second.report.unchangedBookmarks, 1);
      expect(second.next.encode(), first.next.encode());
    });

    test('changed cloud content never replaces the stored copy', () {
      final first = planImport(
        current: VaultState.empty,
        batch: batch(
          identities: [ident('a', 'uid-a', key: 'k1')],
          bookmarks: [mark('x', password: 'old')],
        ),
        owner: owner,
      );
      final second = planImport(
        current: first.next,
        batch: batch(
          identities: [ident('a', 'uid-a', key: 'k2')],
          bookmarks: [mark('x', password: 'new', version: 'v2')],
        ),
        owner: owner,
      );
      expect(second.report.conflictIdentities, 1);
      expect(second.report.conflictBookmarks, 1);
      expect(second.report.hasChanges, isFalse);
      expect(second.next.bookmarks.single.serverPassword, 'old');
      expect(second.next.identities.single.desktopString, 'k1-a');
    });

    test('an existing local identity is not duplicated by UID', () {
      final plan = planImport(
        current: VaultState.empty,
        batch: batch(
          identities: [ident('a', 'uid-local'), ident('b', 'uid-b'), ident('c', 'uid-b')],
        ),
        owner: owner,
        localUids: {'uid-local'},
      );
      expect(plan.next.identities.map((i) => i.cloudId), ['b']);
      expect(plan.report.duplicateIdentities, 2);
    });

    test('invalid items are only counted, never repaired or imported', () {
      final plan = planImport(
        current: VaultState.empty,
        batch: batch(
          identities: [ident('a', 'uid-a')],
          badIdentities: ['bad1', 'bad2'],
          badBookmarks: ['badb'],
        ),
        owner: owner,
      );
      expect(plan.report.invalidIdentities, 2);
      expect(plan.report.invalidBookmarks, 1);
      expect(plan.next.identities, hasLength(1));
      expect(plan.report.skippedCount, 3);
    });

    test('an empty cloud is reported and adds nothing', () {
      final plan = planImport(current: VaultState.empty, batch: batch(), owner: owner);
      expect(plan.report.cloudEmpty, isTrue);
      expect(plan.report.hasChanges, isFalse);
      expect(plan.next.hasData, isFalse);
    });

    test('items of another account are kept apart by ownership', () {
      final mine = planImport(
        current: VaultState.empty,
        batch: batch(bookmarks: [mark('x')]),
        owner: owner,
      );
      final other = planImport(
        current: mine.next,
        batch: batch(bookmarks: [mark('x')]),
        owner: 'bob@example.com',
      );
      expect(other.next.bookmarks, hasLength(2));
      expect(other.next.bookmarks.map((b) => b.owner).toSet(), {owner, 'bob@example.com'});
    });

    test('connect address adds the port only when it is not already there', () {
      VaultBookmark b(String address, int? port) => VaultBookmark(
        id: 'i',
        owner: owner,
        cloudId: 'c',
        cloudVersion: 'v',
        address: address,
        port: port,
      );
      expect(b('h.example.invalid', 9988).connectAddress, 'h.example.invalid:9988');
      expect(b('h.example.invalid', null).connectAddress, 'h.example.invalid');
      expect(b('h.example.invalid:9999', 9988).connectAddress, 'h.example.invalid:9999');
    });
  });

  group('AccountVault', () {
    late RecordingBackend backend;
    late AccountVault vault;

    setUp(() {
      backend = RecordingBackend();
      vault = AccountVault(backend);
    });

    ImportPlan plan(VaultState current) => planImport(
      current: current,
      batch: batch(
        identities: [ident('a', 'uid-a'), ident('b', 'uid-b')],
        bookmarks: [mark('x', password: 'pw', identity: '')],
      ),
      owner: owner,
    );

    test('a missing entry is an empty vault; data survives a restart', () async {
      expect((await vault.load()).hasData, isFalse);
      await vault.write(plan(VaultState.empty).next);
      final restarted = AccountVault(backend);
      final state = await restarted.load();
      expect(state.identities, hasLength(2));
      expect(state.bookmarks.single.serverPassword, 'pw');
      expect(state.bookmarks.single.identityRef, '');
    });

    test('private strings and passwords are only in the secure backend', () async {
      await vault.write(plan(VaultState.empty).next);
      expect(backend.writes, 1, reason: 'the whole import is one write');
    });

    test('unreadable stored data is an error, never an empty vault', () async {
      for (final raw in ['broken', '{}', '{"v":2}', '[]', '{"v":1,"identities":[{}],"bookmarks":[],"links":{}}']) {
        await backend.write(AccountVault.storageKey, raw);
        await expectLater(vault.load(), throwsA(anything), reason: raw);
        await expectLater(vault.hasData(), throwsA(anything), reason: raw);
      }
    });

    test('a failed write leaves the previous vault in place', () async {
      final first = plan(VaultState.empty).next;
      await vault.write(first);
      final before = await backend.read(AccountVault.storageKey);
      backend.failWrites = true;
      await expectLater(
        vault.write(first.copyWith(bookmarks: [])),
        throwsStateError,
      );
      backend.failWrites = false;
      expect(await backend.read(AccountVault.storageKey), before);
    });

    test('a write that does not read back is reported and rolled back', () async {
      backend.dropWrites = true;
      await expectLater(vault.write(plan(VaultState.empty).next), throwsStateError);
      expect(await backend.read(AccountVault.storageKey), isNull);
    });

    test('a link is the user choice and never changes the cloud reference', () async {
      final p = plan(VaultState.empty).next;
      await vault.write(p);
      final bookmark = p.bookmarks.single;
      await vault.setLink(bookmark.id, p.identities[1].id);
      final state = await vault.load();
      expect(state.links[bookmark.id], p.identities[1].id);
      expect(state.bookmarks.single.identityRef, '');
      await expectLater(vault.setLink('nope', p.identities[0].id), throwsStateError);
      await expectLater(vault.setLink(bookmark.id, 'nope'), throwsStateError);
    });

    test('concurrent updates are serialized and none is lost', () async {
      final p = plan(VaultState.empty).next;
      await vault.write(p);
      final bookmark = p.bookmarks.single;
      await Future.wait([
        vault.setLink(bookmark.id, p.identities[0].id),
        vault.setLink(AccountVault.localDefaultLink, p.identities[1].id),
        vault.setLink(bookmark.id, AccountVault.legacyIdentityId),
      ]);
      final links = (await vault.load()).links;
      expect(links[AccountVault.localDefaultLink], p.identities[1].id);
      expect(links[bookmark.id], AccountVault.legacyIdentityId);
    });
  });
}
