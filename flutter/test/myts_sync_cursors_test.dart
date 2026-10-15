// Sync cursor store tests: account scoping, atomic writes and strict
// decoding. No Rust, no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/myts/sync_cursors.dart';

class _FailBackend extends MemoryMyTsSecureBackend {
  bool failWrites = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Synthetic write failure');
    await super.write(key, value);
  }
}

const _owner = 'Alice@EXAMPLE.COM';

SyncCursors _cursors() => const SyncCursors(
  globalVersion: 'g1',
  classVersions: {0: 'c0', 1: 'c1'},
  itemVersions: {'item-a': 'v2'},
);

void main() {
  test('empty store loads null', () async {
    expect(
      await SyncCursorStore(MemoryMyTsSecureBackend()).load(_owner),
      isNull,
    );
  });

  test('save/load round trip keeps versions and owner scope', () async {
    final store = SyncCursorStore(MemoryMyTsSecureBackend());
    await store.save(_owner, _cursors());
    final loaded = await store.load(_owner);
    expect(loaded, isNotNull);
    expect(loaded!.globalVersion, 'g1');
    expect(loaded.classVersions, {0: 'c0', 1: 'c1'});
    expect(loaded.itemVersions, {'item-a': 'v2'});
    // Owner matching ignores email case, like the vault owner.
    expect((await store.load('alice@example.com'))!.globalVersion, 'g1');
  });

  test('another account sees no cursors', () async {
    final store = SyncCursorStore(MemoryMyTsSecureBackend());
    await store.save(_owner, _cursors());
    expect(await store.load('bob@example.com'), isNull);
  });

  test('saving for a new owner replaces the entry', () async {
    final backend = MemoryMyTsSecureBackend();
    final store = SyncCursorStore(backend);
    await store.save(_owner, _cursors());
    await store.save('bob@example.com', const SyncCursors());
    expect(await store.load(_owner), isNull);
    expect(await store.load('bob@example.com'), isNotNull);
  });

  test('unreadable content throws instead of looking empty', () async {
    final backend = MemoryMyTsSecureBackend();
    final store = SyncCursorStore(backend);
    for (final raw in [
      'not json',
      '{"v":1}',
      '{"v":999,"owner":"a","cursors":{"globalVersion":"","classes":{},"items":{}}}',
      '{"v":1,"owner":"a","cursors":{"globalVersion":1,"classes":{},"items":{}}}',
      '{"v":1,"owner":"a","cursors":{"globalVersion":"","classes":{"x":"c"},"items":{}}}',
      '{"v":1,"owner":"a","cursors":{"globalVersion":"","classes":{"9":"c"},"items":{}}}',
      '{"v":1,"owner":"a","cursors":{"globalVersion":"","classes":{},"items":{"i":7}}}',
    ]) {
      await backend.write(SyncCursorStore.storageKey, raw);
      expect(() => store.load('a'), throwsFormatException, reason: raw);
    }
  });

  test('failed save keeps the previous cursors', () async {
    final backend = _FailBackend();
    final store = SyncCursorStore(backend);
    await store.save(_owner, _cursors());
    backend.failWrites = true;
    await expectLater(
      store.save(_owner, const SyncCursors(globalVersion: 'g2')),
      throwsStateError,
    );
    backend.failWrites = false;
    expect((await store.load(_owner))!.globalVersion, 'g1');
  });

  test('failed first save leaves no entry', () async {
    final backend = _FailBackend()..failWrites = true;
    final store = SyncCursorStore(backend);
    await expectLater(store.save(_owner, _cursors()), throwsStateError);
    backend.failWrites = false;
    expect(await store.load(_owner), isNull);
  });

  test('clear drops the cursors', () async {
    final backend = MemoryMyTsSecureBackend();
    final store = SyncCursorStore(backend);
    await store.save(_owner, _cursors());
    await store.clear();
    expect(await store.load(_owner), isNull);
  });

  test('concurrent saves serialize without losing advances', () async {
    final store = SyncCursorStore(MemoryMyTsSecureBackend());
    await Future.wait([
      for (var i = 0; i < 5; i++)
        store.synchronized(() async {
          final current = await store.load(_owner);
          final next = (current?.itemVersions.length ?? 0) + 1;
          await store.save(
            _owner,
            SyncCursors(itemVersions: {'item-$next': 'v$next'}),
          );
        }),
    ]);
    final loaded = await store.load(_owner);
    expect(loaded!.itemVersions.length, 1);
    expect(loaded.itemVersions.keys.single, startsWith('item-'));
  });
}
