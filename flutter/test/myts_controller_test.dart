// Controller tests: pacing, OTP state, persistence and logout.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';

import 'myts_helpers.dart';

ProviderContainer containerWith({
  required Future<MyTsHttpResponse> Function(Uri, Map<String, String>, Uint8List) post,
  MemoryMyTsSecureBackend? backend,
}) {
  final mem = backend ?? MemoryMyTsSecureBackend();
  return ProviderContainer(overrides: [
    myTsApiProvider.overrideWithValue(MyTsApi(
      post: (uri, headers, body) => post(uri, headers, body),
      deviceName: 'Test device',
    )),
    myTsSessionStoreProvider.overrideWithValue(MyTsSessionStore(mem)),
  ]);
}

void main() {
  test('login persists the session and signs in', () async {
    final c = containerWith(
      post: (_, _, _) async => MyTsHttpResponse(
        200,
        loginSessionReply(error: 200, session: 'sess-1', uuid: 'u-1', username: 'bob'),
      ),
    );
    addTearDown(c.dispose);

    expect(c.read(myTsProvider).status, MyTsStatus.signedOut);
    await c.read(myTsProvider.notifier).login(' Alice@Example.COM ', 'pw');
    final s = c.read(myTsProvider);
    expect(s.status, MyTsStatus.signedIn);
    expect(s.username, 'bob');
    expect(s.email, 'Alice@Example.COM'); // trimmed once, same value everywhere

    final stored = await c.read(myTsSessionStoreProvider).load();
    expect(stored!.session, 'sess-1');
    expect(stored.email, 'Alice@Example.COM');
  });

  test('a second immediate attempt is paced, not sent', () async {
    var posts = 0;
    final c = containerWith(
      post: (_, _, _) async {
        posts++;
        return MyTsHttpResponse(200, loginSessionReply(error: 202));
      },
    );
    addTearDown(c.dispose);

    await c.read(myTsProvider.notifier).login('a@b', 'wrong');
    expect(posts, 1);
    await c.read(myTsProvider.notifier).login('a@b', 'wrong');
    expect(posts, 1); // paced: no second POST
    expect(c.read(myTsProvider).failure, MyTsFailure.paced);
  });

  test('OTP requirement moves to the OTP step', () async {
    final c = containerWith(
      post: (_, _, _) async => MyTsHttpResponse(200, loginSessionReply(error: 208)),
    );
    addTearDown(c.dispose);

    await c.read(myTsProvider.notifier).login('a@b', 'pw');
    expect(c.read(myTsProvider).status, MyTsStatus.otpNeeded);
    expect(c.read(myTsProvider).failure, MyTsFailure.otpRequired);
  });

  test('logout deletes only its own session, then wipes local state', () async {
    String? deleted;
    final backend = MemoryMyTsSecureBackend();
    final c = containerWith(
      backend: backend,
      post: (uri, _, body) async {
        if (body.length > 14 && body[0] == 'deleteSession'.length) {
          deleted = scannedString(scanFields(body.sublist(14)), 1);
          return MyTsHttpResponse(200, loginStatusReply(204));
        }
        return MyTsHttpResponse(
          200,
          loginSessionReply(error: 200, session: 'sess-9', uuid: 'u', username: 'z'),
        );
      },
    );
    addTearDown(c.dispose);

    await c.read(myTsProvider.notifier).login('a@b', 'pw');
    expect(c.read(myTsProvider).status, MyTsStatus.signedIn);
    await c.read(myTsProvider.notifier).logout();
    expect(deleted, 'sess-9');
    expect(c.read(myTsProvider).status, MyTsStatus.signedOut);
    expect(await c.read(myTsSessionStoreProvider).load(), isNull);
  });
}
