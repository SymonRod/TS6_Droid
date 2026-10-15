// Session storage tests (acceptance item 5): secure persistence,
// restore and logout wipe using the memory backend.
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';

void main() {
  test('empty store loads null', () async {
    expect(await MyTsSessionStore(MemoryMyTsSecureBackend()).load(), isNull);
  });

  test('save/load round trip', () async {
    final store = MyTsSessionStore(MemoryMyTsSecureBackend());
    await store.save(session: 'sess', uuid: 'uuid', username: 'bob', email: 'a@b');
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.session, 'sess');
    expect(loaded.uuid, 'uuid');
    expect(loaded.username, 'bob');
    expect(loaded.email, 'a@b');
  });

  test('clear wipes everything', () async {
    final store = MyTsSessionStore(MemoryMyTsSecureBackend());
    await store.save(session: 'sess', uuid: 'u', username: 'b', email: 'a@b');
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('empty session is never a session', () async {
    final backend = MemoryMyTsSecureBackend();
    await backend.write(MyTsSessionStore.kSession, '');
    expect(await MyTsSessionStore(backend).load(), isNull);
  });

  test('wrapped key round trip; absent or unreadable key loads as empty', () async {
    final backend = MemoryMyTsSecureBackend();
    final store = MyTsSessionStore(backend);
    await store.save(session: 's', uuid: 'u', username: 'b', email: 'a@b', wrappedKey: [1, 2, 3]);
    expect((await store.load())!.wrappedKey, [1, 2, 3]);
    await backend.write(MyTsSessionStore.kWrappedKey, '***not base64***');
    expect((await store.load())!.wrappedKey, isEmpty);
    await store.save(session: 's', uuid: 'u', username: 'b', email: 'a@b');
    expect((await store.load())!.wrappedKey, isEmpty);
  });

  test('clear removes only the session keys, never imported data', () async {
    final backend = MemoryMyTsSecureBackend();
    await backend.write('ts6_account_vault_v1', 'imported identities and passwords');
    final store = MyTsSessionStore(backend);
    await store.save(session: 's', uuid: 'u', username: 'b', email: 'a@b', wrappedKey: [9]);
    await store.clear();
    expect(await store.load(), isNull);
    expect(await backend.read(MyTsSessionStore.kWrappedKey), isNull);
    expect(await backend.read('ts6_account_vault_v1'), 'imported identities and passwords');
  });

  group('saved password', () {
    test('remembering is on by default and the password round-trips', () async {
      final store = MyTsSessionStore(MemoryMyTsSecureBackend());
      expect(await store.rememberPassword(), isTrue);
      expect(await store.loadPassword(), isNull);
      await store.savePassword('pw');
      expect(await store.loadPassword(), 'pw');
    });

    test('opting out stores nothing and wipes what was saved', () async {
      final backend = MemoryMyTsSecureBackend();
      final store = MyTsSessionStore(backend);
      await store.savePassword('pw');
      await store.setRememberPassword(false);
      expect(await backend.read(MyTsSessionStore.kPassword), isNull);
      await store.savePassword('pw');
      expect(await backend.read(MyTsSessionStore.kPassword), isNull);
      expect(await store.loadPassword(), isNull);
      await store.setRememberPassword(true);
      await store.savePassword('pw');
      expect(await store.loadPassword(), 'pw');
    });

    test('an empty password is never saved', () async {
      final store = MyTsSessionStore(MemoryMyTsSecureBackend());
      await store.savePassword('pw');
      await store.savePassword('');
      expect(await store.loadPassword(), isNull);
    });

    test('signing out forgets the password but keeps the choice', () async {
      final store = MyTsSessionStore(MemoryMyTsSecureBackend());
      await store.setRememberPassword(false);
      await store.save(session: 's', uuid: 'u', username: 'b', email: 'a@b');
      await store.clear();
      expect(await store.rememberPassword(), isFalse);
      final on = MyTsSessionStore(MemoryMyTsSecureBackend());
      await on.savePassword('pw');
      await on.clear();
      expect(await on.loadPassword(), isNull);
      expect(await on.rememberPassword(), isTrue);
    });
  });
}
