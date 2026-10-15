import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/chat/chat_client.dart';
import 'package:ts6_flutter/src/chat/chat_controller.dart';
import 'package:ts6_flutter/src/chat/chat_models.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/contact_store.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;

import 'chat_fake_matrix.dart';
import 'myts_rust.dart';

void main() {
  setUpAll(initRustForTests);

  late Map fixture;
  late MyTsSessionStore sessions;
  late MyTsApi api;
  late String room;

  setUp(() async {
    fixture =
        jsonDecode(
              await File(
                Platform.environment['TSLIB_HISTORY_FIXTURE']!,
              ).readAsString(),
            )
            as Map;
    room = fixture['room'] as String;
    sessions = MyTsSessionStore(MemoryMyTsSecureBackend());
    await sessions.save(
      session: 'sess',
      uuid: 'account-1',
      username: 'alice',
      email: 'alice@example.com',
      wrappedKey: hexBytes(kWrappedKey),
    );
    api = MyTsApi(
      post: (uri, headers, request, limit) async => MyTsHttpResponse(
        200,
        base64Decode(fixture['config_reply'] as String),
      ),
    );
  });

  Future<ChatClient> open(FakeMatrix server, {ChatStore? store}) =>
      ChatClient.open(
        api: api,
        sessions: sessions,
        password: kChatPassword,
        store: store ?? ChatStore(MemoryMyTsSecureBackend()),
        http: server.handle,
      );

  test('connect logs in once, loads rooms and sends only in clear rooms', () async {
    final server = FakeMatrix(room);
    final client = await open(server);
    addTearDown(client.close);
    await client.connect();
    expect(server.calls.where((c) => c.startsWith('POST login')).length, 1);

    var view = await client.view();
    final rooms = view['rooms'] as List;
    expect(rooms, hasLength(1));
    expect(rooms.single['encrypted'], false);
    expect(rooms.single['peer'], '@friend:example.invalid');
    expect(rooms.single['last_body'], 'ciao');

    await client.send(room, 'hello there', 'ts6d_test1');
    expect(server.sent.single['body'], 'hello there');
    expect(server.sent.single['txn'], 'ts6d_test1');
    view = await client.view(room);
    final messages = view['messages'] as List;
    expect(messages.map((m) => m['body']), ['ciao', 'hello there']);

    // A second connect reuses the stored token: no second login.
    await client.connect();
    expect(server.calls.where((c) => c.startsWith('POST login')).length, 1);
  });

  test('encrypted rooms without a single peer refuse sends before any request', () async {
    final server = FakeMatrix(room, encrypted: true, group: true);
    final client = await open(server);
    addTearDown(client.close);
    await client.connect();
    final before = server.calls.length;
    await expectLater(
      client.send(room, 'secret', 'ts6d_test2'),
      throwsA(
        isA<ChatException>().having(
          (e) => e.failure,
          'failure',
          ChatFailure.unsupportedRoom,
        ),
      ),
    );
    expect(server.calls.length, before);
    expect(server.sent, isEmpty);
  });

  test('HTTP failures are classified and never trigger a new login', () async {
    final server = FakeMatrix(room);
    final client = await open(server);
    addTearDown(client.close);
    await client.connect();
    server.failSendsWith = 429;
    await expectLater(
      client.send(room, 'x', 'ts6d_test3'),
      throwsA(
        isA<ChatException>().having(
          (e) => e.failure,
          'failure',
          ChatFailure.rateLimited,
        ),
      ),
    );
    server.failSendsWith = 401;
    await expectLater(
      client.send(room, 'x', 'ts6d_test4'),
      throwsA(
        isA<ChatException>().having(
          (e) => e.failure,
          'failure',
          ChatFailure.authentication,
        ),
      ),
    );
    expect(server.calls.where((c) => c.startsWith('POST login')).length, 1);
  });

  test('presence is sent in the desktop extended encoding', () async {
    final server = FakeMatrix(room);
    final client = await open(server);
    addTearDown(client.close);
    await client.connect();
    await client.setPresence(1, 'Back shortly');
    expect(server.presenceBody!['presence'], 'online');
    expect(jsonDecode(server.presenceBody!['status_msg'] as String), {
      'presence': 1,
      'status_msg': 'Back shortly',
    });
    final view = await client.view();
    expect((view['account'] as Map)['me']['state'], 1);
  });

  test('state survives a sealed restart and the same device is reused', () async {
    final server = FakeMatrix(room);
    final store = ChatStore(MemoryMyTsSecureBackend());
    final first = await open(server, store: store);
    await first.connect();
    first.close();
    final second = await open(server, store: store);
    addTearDown(second.close);
    // Cached conversations are readable before any network call.
    final view = await second.view();
    expect((view['rooms'] as List), hasLength(1));
    await second.connect();
    expect(server.calls.where((c) => c.startsWith('POST login')).length, 1);
  });

  test('an interrupted first login is fenced, then retried on the same device', () async {
    final server = FakeMatrix(room);
    final store = ChatStore(MemoryMyTsSecureBackend());
    var failLogin = true;
    final devices = <String>[];
    Future<MyTsHttpResponse> http(rs.MyTsHistoryRequest r, String action) {
      if (action == 'login') {
        devices.add(
          (jsonDecode(utf8.decode(r.body)) as Map)['device_id'] as String,
        );
        if (failLogin) throw const SocketException('reset');
      }
      return server.handle(r, action);
    }

    final first = await ChatClient.open(
      api: api,
      sessions: sessions,
      password: kChatPassword,
      store: store,
      http: http,
    );
    await expectLater(
      first.connect(),
      throwsA(isA<ChatException>().having((e) => e.failure, 'f', ChatFailure.network)),
    );
    first.close();

    // Restart: the interrupted login must not repeat by itself, and every other
    // call must say that nothing is logged in (not "token rejected").
    failLogin = false;
    final second = await ChatClient.open(
      api: api,
      sessions: sessions,
      password: kChatPassword,
      store: store,
      http: http,
    );
    addTearDown(second.close);
    await expectLater(
      second.connect(),
      throwsA(isA<ChatException>().having((e) => e.failure, 'f', ChatFailure.loginUncertain)),
    );
    await expectLater(
      second.send(room, 'x', 'ts6d_t'),
      throwsA(isA<ChatException>().having((e) => e.failure, 'f', ChatFailure.notLoggedIn)),
    );
    await expectLater(
      second.startDirect('@friend:example.invalid'),
      throwsA(isA<ChatException>().having((e) => e.failure, 'f', ChatFailure.notLoggedIn)),
    );
    expect(devices, hasLength(1));

    await second.retryLogin();
    expect(devices, hasLength(2));
    expect(devices[1], devices[0], reason: 'same Matrix device, no duplicate');
    expect(((await second.view())['rooms'] as List), hasLength(1));
  });

  group('controller', () {
    ProviderContainer container(FakeMatrix server, ChatStore store) {
      final c = ProviderContainer(
        overrides: [
          myTsSessionStoreProvider.overrideWithValue(sessions),
          myTsApiProvider.overrideWithValue(
            MyTsApi(
              post: (uri, headers, request, limit) async {
                // Config pull and (failing) contacts RPC share this fake.
                if (uri.path.contains('chat')) {
                  return MyTsHttpResponse(503, Uint8List(0));
                }
                return MyTsHttpResponse(
                  200,
                  base64Decode(fixture['config_reply'] as String),
                );
              },
            ),
          ),
          contactStoreProvider.overrideWithValue(
            ContactStore(MemoryMyTsSecureBackend()),
          ),
          chatClientOpenerProvider.overrideWithValue(
            (password, own) => ChatClient.open(
              api: api,
              sessions: sessions,
              password: password,
              allowOwnEmpty: own,
              store: store,
              http: server.handle,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('wrong password stays locked with a specific error', () async {
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      await c.read(chatProvider.notifier).unlock('wrong');
      expect(c.read(chatProvider).phase, ChatPhase.locked);
      expect(c.read(chatProvider).error, ChatError.wrongPassword);
    });

    test('a typed password is saved once it unlocks; a wrong one is not', () async {
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      final chat = c.read(chatProvider.notifier);
      await chat.unlock('wrong');
      expect(await sessions.loadPassword(), isNull);
      await chat.unlock(kChatPassword);
      expect(c.read(chatProvider).phase, ChatPhase.ready);
      expect(await sessions.loadPassword(), kChatPassword);
    });

    test('opted out: nothing is saved', () async {
      await sessions.setRememberPassword(false);
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      await c.read(chatProvider.notifier).unlock(kChatPassword);
      expect(c.read(chatProvider).phase, ChatPhase.ready);
      expect(await sessions.loadPassword(), isNull);
    });

    test('the saved password unlocks without asking', () async {
      await sessions.savePassword(kChatPassword);
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      await c.read(chatProvider.notifier).unlockWithSaved();
      expect(c.read(chatProvider).phase, ChatPhase.ready);
    });

    test('a saved password that stopped working is dropped and explained', () async {
      await sessions.savePassword('outdated');
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      await c.read(chatProvider.notifier).unlockWithSaved();
      expect(c.read(chatProvider).phase, ChatPhase.locked);
      expect(c.read(chatProvider).error, ChatError.savedPasswordRejected);
      expect(await sessions.loadPassword(), isNull);
    });

    test('without a saved password nothing happens', () async {
      final c = container(FakeMatrix(room), ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      await c.read(chatProvider.notifier).unlockWithSaved();
      expect(c.read(chatProvider).phase, ChatPhase.locked);
      expect(c.read(chatProvider).error, isNull);
    });

    test('unlock, send with pending state, failure and retry, lock', () async {
      final server = FakeMatrix(room);
      final c = container(server, ChatStore(MemoryMyTsSecureBackend()));
      c.listen(chatProvider, (_, _) {});
      final chat = c.read(chatProvider.notifier);
      await chat.unlock(kChatPassword);
      var s = c.read(chatProvider);
      expect(s.phase, ChatPhase.ready);
      expect(s.rooms.single.id, room);
      expect(s.rooms.single.encrypted, false);
      expect(s.account.user, startsWith('@'));
      expect(chat.directRoomWith('@friend:example.invalid'), room);
      expect(chat.directRoomWith('@stranger:example.invalid'), isNull);

      await chat.openRoom(room);
      s = c.read(chatProvider);
      expect(s.messages[room]!.map((m) => m.body), ['ciao']);
      chat.closeRoom(room);

      server.failSendsWith = 503;
      await chat.send(room, 'will fail');
      s = c.read(chatProvider);
      expect(s.pending[room]!.single.failed, isTrue);
      expect(s.error, ChatError.server);
      final txn = s.pending[room]!.single.txn;

      server.failSendsWith = 0;
      await chat.retry(room, txn);
      s = c.read(chatProvider);
      expect(s.pending[room], isNull);
      expect(server.sent.single['txn'], txn, reason: 'retry keeps the txn id');
      expect(s.messages[room]!.map((m) => m.body), ['ciao', 'will fail']);

      await chat.setPresence(PresenceState.doNotDisturb, 'Busy');
      expect(c.read(chatProvider).account.me.state, 2);

      chat.lock();
      s = c.read(chatProvider);
      expect(s.phase, ChatPhase.locked);
      expect(s.rooms, isEmpty);
      expect(s.messages, isEmpty);
    });
  });
}
