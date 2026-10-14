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
}
