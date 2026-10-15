// Controller tests: pacing, OTP state, persistence and logout.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/onboarding_store.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/state/onboarding_controller.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';

import 'myts_helpers.dart';
import 'onboarding_helpers.dart';
import 'myts_rust.dart';

ProviderContainer containerWith({
  required Future<MyTsHttpResponse> Function(
    Uri,
    Map<String, String>,
    Uint8List,
  )
  post,
  MemoryMyTsSecureBackend? backend,
}) {
  final mem = backend ?? MemoryMyTsSecureBackend();
  return ProviderContainer(
    overrides: [
      myTsApiProvider.overrideWithValue(
        MyTsApi(
          post: (uri, headers, body, _) => post(uri, headers, body),
          deviceName: 'Test device',
        ),
      ),
      myTsSessionStoreProvider.overrideWithValue(MyTsSessionStore(mem)),
    ],
  );
}

void main() {
  setUpAll(initRustForTests);

  test('login persists the session and signs in', () async {
    final c = containerWith(
      post: (_, _, _) async => MyTsHttpResponse(
        200,
        loginSessionReply(
          error: 200,
          session: 'sess-1',
          uuid: 'u-1',
          username: 'bob',
        ),
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
      post: (_, _, _) async =>
          MyTsHttpResponse(200, loginSessionReply(error: 208)),
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
          loginSessionReply(
            error: 200,
            session: 'sess-9',
            uuid: 'u',
            username: 'z',
          ),
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

  group('sign-in that starts from scratch', () {
    late MemoryMyTsSecureBackend backend;

    ProviderContainer containerFor(int loginError) {
      SharedPreferences.setMockInitialValues({
        'bookmarks_json': '[{"address":"ts.example.org"}]',
      });
      backend = MemoryMyTsSecureBackend();
      return ProviderContainer(
        overrides: [
          myTsApiProvider.overrideWithValue(
            MyTsApi(
              post: (_, _, _, _) async => MyTsHttpResponse(
                200,
                loginSessionReply(
                  error: loginError,
                  session: 'sess-new',
                  uuid: 'u',
                  username: 'z',
                ),
              ),
              deviceName: 'Test device',
            ),
          ),
          myTsSessionStoreProvider.overrideWithValue(MyTsSessionStore(backend)),
          onboardingStoreProvider.overrideWithValue(
            OnboardingStore(
              identities: TestIdentityStore(),
              bookmarks: BookmarkStore(),
            ),
          ),
        ],
      );
    }

    test(
      'a successful login wipes the old data before storing the new session',
      () async {
        final c = containerFor(200);
        addTearDown(c.dispose);
        await backend.write('myts_history_v1_old', 'old chat keys');
        await backend.write('ts6_account_vault_v1', '{}');

        await c
            .read(myTsProvider.notifier)
            .login('a@b', 'pw', resetLocalData: true);

        expect(c.read(myTsProvider).status, MyTsStatus.signedIn);
        expect(await backend.read('myts_history_v1_old'), isNull);
        expect(await backend.read('ts6_account_vault_v1'), isNull);
        expect(
          (await c.read(myTsSessionStoreProvider).load())!.session,
          'sess-new',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('bookmarks_json'), isNull);
      },
    );

    test('a failed login deletes nothing', () async {
      final c = containerFor(202);
      addTearDown(c.dispose);
      await backend.write('myts_history_v1_old', 'old chat keys');

      await c
          .read(myTsProvider.notifier)
          .login('a@b', 'wrong', resetLocalData: true);

      expect(c.read(myTsProvider).status, MyTsStatus.signedOut);
      expect(await backend.read('myts_history_v1_old'), 'old chat keys');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bookmarks_json'), isNotNull);
    });

    test('without the flag the old data stays', () async {
      final c = containerFor(200);
      addTearDown(c.dispose);
      await backend.write('myts_history_v1_old', 'old chat keys');
      await c.read(myTsProvider.notifier).login('a@b', 'pw');
      expect(await backend.read('myts_history_v1_old'), 'old chat keys');
    });
  });
}
