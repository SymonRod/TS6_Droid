// Plumbing of encrypted sending: the Dart loop around the Rust `send_step`, the
// durable state, the consent gate and the controller. The cryptography itself is
// proven elsewhere (Rust end-to-end tests with real vodozemac peers, and
// tools/myts/test_interop_rust_e2ee.py against libolm); the fake server here
// never decrypts anything.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/chat/chat_client.dart';
import 'package:ts6_flutter/src/chat/chat_controller.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/contact_store.dart';
import 'package:ts6_flutter/src/myts/controller.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';

import 'chat_fake_matrix.dart';
import 'myts_rust.dart';

Matcher _failure(ChatFailure f) =>
    isA<ChatException>().having((e) => e.failure, 'failure', f);

void main() {
  setUpAll(initRustForTests);

  late Map fixture;
  late Map<String, dynamic> peer;
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
    peer = await loadPeerFixture();
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

  Future<ChatClient> open(
    FakeMatrix server, {
    ChatStore? store,
    Map<String, dynamic> Function(Map<String, dynamic>)? planHook,
  }) => ChatClient.open(
    api: api,
    sessions: sessions,
    password: kChatPassword,
    store: store ?? ChatStore(MemoryMyTsSecureBackend()),
    http: server.handle,
    planHook: planHook,
  );

  FakeMatrix encryptedServer({bool group = false}) =>
      FakeMatrix(room, encrypted: true, group: group, peer: peer);

  /// Connected client whose user already agreed to encrypted sending.
  Future<ChatClient> ready(FakeMatrix server, {ChatStore? store}) async {
    final client = await open(server, store: store);
    addTearDown(client.close);
    await client.connect();
    await client.grantEncryptionConsent();
    return client;
  }

  Future<List<String>> bodies(ChatClient client, {bool poll = false}) async {
    if (poll) await client.poll(room);
    final messages = (await client.view(room))['messages'] as List;
    return [for (final m in messages) m['body'] as String];
  }

  group('client', () {
    test('the first message runs the whole chain, in order, and reads back as ours', () async {
      final server = encryptedServer();
      final client = await ready(server);
      final before = server.actions.length;
      final warnings = await client.send(room, 'hello secret', 'ts6d_e1');
      expect(warnings, isEmpty);
      expect(server.actions.sublist(before), [
        'keys_upload',
        'keys_query',
        'keys_claim',
        'share_keys',
        'send_encrypted',
      ]);

      final upload = server.uploads.single;
      expect(upload['device_keys']['device_id'], server.device);
      expect(upload['one_time_keys'], hasLength(50));
      expect(upload['fallback_keys'], hasLength(1));
      final key = server.toDevice.single['messages'][kFriend]['FRIENDDEV'];
      expect(key['algorithm'], 'm.olm.v1.curve25519-aes-sha2');

      final event = server.sent.single;
      expect(
        event.keys.toSet(),
        {'txn', 'algorithm', 'sender_key', 'device_id', 'session_id', 'ciphertext'},
        reason: 'a Megolm wrapper, no readable body',
      );
      expect(event['algorithm'], 'm.megolm.v1.aes-sha2');
      expect(event['device_id'], server.device);
      expect(
        server.bodies.where((b) => b.contains('hello secret')),
        isEmpty,
        reason: 'the text never leaves the phone in clear',
      );

      // The local echo decrypts through our own copy of the session...
      var messages = (await client.view(room))['messages'] as List;
      expect(messages.map((m) => m['body']), ['ciao', 'hello secret']);
      expect(messages.last['status'], 'decrypted');
      expect(messages.last['sender'], server.user);
      // ...and the same event fetched from the server is neither duplicated
      // nor flagged as a replay.
      await client.poll(room);
      messages = (await client.view(room))['messages'] as List;
      expect(messages.map((m) => m['body']), ['ciao', 'hello secret']);
      expect(messages.last['status'], 'decrypted');
    });

    test('the second message is a single send_encrypted in the same session', () async {
      final server = encryptedServer();
      final client = await ready(server);
      await client.send(room, 'one', 'ts6d_s1');
      final before = server.actions.length;
      await client.send(room, 'two', 'ts6d_s2');
      expect(server.actions.sublist(before), ['send_encrypted']);
      expect(server.shareAttempts, hasLength(1));
      expect(server.uploads, hasLength(1));
      expect(server.sent[1]['session_id'], server.sent[0]['session_id']);
      expect(await bodies(client, poll: true), ['ciao', 'one', 'two']);
    });

    test('a repeated send of a finished txn sends nothing more', () async {
      final server = encryptedServer();
      final client = await ready(server);
      await client.send(room, 'once', 'ts6d_r1');
      final before = server.actions.length;
      await client.send(room, 'once', 'ts6d_r1');
      expect(server.actions.length, before);
      expect(server.sent, hasLength(1));
    });

    test('a network failure mid-send is retried with the identical event, once', () async {
      final server = encryptedServer();
      final client = await ready(server);
      var armed = true;
      String? failedBody;
      server.intercept = (action, r) async {
        if (action == 'send_encrypted' && armed) {
          armed = false;
          failedBody = utf8.decode(r.body);
          throw const SocketException('reset');
        }
        return null;
      };
      await expectLater(
        client.send(room, 'later', 'ts6d_n1'),
        throwsA(_failure(ChatFailure.network)),
      );
      expect(server.sent, isEmpty);

      final before = server.actions.length;
      await client.send(room, 'later', 'ts6d_n1');
      expect(server.actions.sublist(before), ['send_encrypted']);
      expect(server.uploads, hasLength(1));
      expect(server.shareAttempts, hasLength(1));
      final event = server.sent.single;
      expect(
        event['ciphertext'],
        (jsonDecode(failedBody!) as Map)['ciphertext'],
        reason: 'a retry never encrypts again or uses another Megolm index',
      );
      expect(await bodies(client, poll: true), ['ciao', 'later']);
    });

    test('the built event survives a restart from the sealed snapshot', () async {
      final server = encryptedServer();
      final store = ChatStore(MemoryMyTsSecureBackend());
      final first = await ready(server, store: store);
      var armed = true;
      String? failedBody;
      server.intercept = (action, r) async {
        if (action == 'send_encrypted' && armed) {
          armed = false;
          failedBody = utf8.decode(r.body);
          throw const SocketException('reset');
        }
        return null;
      };
      await expectLater(
        first.send(room, 'survives', 'ts6d_rs'),
        throwsA(_failure(ChatFailure.network)),
      );
      first.close();

      final second = await open(server, store: store);
      addTearDown(second.close);
      expect(await second.hasEncryptionConsent(), isTrue);
      final before = server.actions.length;
      // Megolm is deterministic for one text at one index, so only a retry with
      // other text tells a stored event from a fresh encryption at the same index
      // (which would be a key-stream reuse): the stored one must go out unchanged.
      await second.send(room, 'a different draft', 'ts6d_rs');
      expect(server.actions.sublist(before), ['send_encrypted']);
      expect(
        server.sent.single['ciphertext'],
        (jsonDecode(failedBody!) as Map)['ciphertext'],
      );
      expect(await bodies(second, poll: true), ['ciao', 'survives']);
    });

    test('a lost reply does not duplicate the message on retry', () async {
      final server = encryptedServer();
      final client = await ready(server);
      var armed = true;
      server.intercept = (action, r) async {
        if (action == 'send_encrypted' && armed) {
          armed = false;
          await server.process(r, action); // the server got it, we never heard
          throw const SocketException('reply lost');
        }
        return null;
      };
      await expectLater(
        client.send(room, 'once only', 'ts6d_lr'),
        throwsA(_failure(ChatFailure.network)),
      );
      expect(server.sent, hasLength(1));
      await client.send(room, 'once only', 'ts6d_lr');
      expect(server.sent, hasLength(1), reason: 'the server de-duplicates the txn');
      expect(await bodies(client, poll: true), ['ciao', 'once only']);
    });

    test('a failed message does not block the next one and is retried later', () async {
      final server = encryptedServer();
      final client = await ready(server);
      server.intercept = (action, r) async {
        if (action == 'send_encrypted' && r.segments.last == 'ts6d_a') {
          throw const SocketException('reset');
        }
        return null;
      };
      await expectLater(
        client.send(room, 'message A', 'ts6d_a'),
        throwsA(_failure(ChatFailure.network)),
      );
      await client.send(room, 'message B', 'ts6d_b');
      expect(server.sent, hasLength(1));

      server.intercept = null;
      final before = server.actions.length;
      await client.send(room, 'message A', 'ts6d_a');
      expect(server.actions.sublist(before), ['send_encrypted']);
      expect(server.sent, hasLength(2));
      expect(
        await bodies(client, poll: true),
        unorderedEquals(['ciao', 'message A', 'message B']),
      );
      final messages = (await client.view(room))['messages'] as List;
      expect(messages.every((m) => m['status'] != 'invalid'), isTrue);
    });

    test('a permanent rejection of the key share resets it; a transient one keeps it', () async {
      final server = encryptedServer();
      final client = await ready(server);
      var status = 403;
      String? rejected;
      server.intercept = (action, r) async {
        if (action == 'share_keys' && rejected == null) {
          rejected = utf8.decode(r.body);
          return MyTsHttpResponse(status, Uint8List(0));
        }
        return null;
      };
      await expectLater(
        client.send(room, 'first try', 'ts6d_p1'),
        throwsA(
          isA<ChatException>()
              .having((e) => e.failure, 'failure', ChatFailure.http)
              .having((e) => e.status, 'status', 403),
        ),
      );
      await client.send(room, 'second try', 'ts6d_p2');
      expect(
        server.shareAttempts.single,
        isNot(rejected),
        reason: 'after a permanent refusal the share is built again',
      );
      expect(server.sent, hasLength(1));

      // Contrast: a 5xx is only retried, with the very same body.
      final transient = encryptedServer();
      final other = await ready(transient);
      status = 503;
      rejected = null;
      transient.intercept = server.intercept;
      await expectLater(
        other.send(room, 'first try', 'ts6d_p3'),
        throwsA(_failure(ChatFailure.http)),
      );
      await other.send(room, 'first try', 'ts6d_p3');
      expect(transient.shareAttempts.single, rejected);
    });

    test('a contact with no device gives noRecipients and the loop ends', () async {
      final server = encryptedServer()..peerDevices = [];
      final client = await ready(server);
      final before = server.actions.length;
      await expectLater(
        client.send(room, 'anyone?', 'ts6d_nr'),
        throwsA(_failure(ChatFailure.noRecipients)),
      );
      expect(server.actions.sublist(before), ['keys_upload', 'keys_query']);
      expect(server.sent, isEmpty);
    });

    test('a device with no keys to claim is skipped, the others still get the key', () async {
      final server = encryptedServer()
        ..peerDevices = ['FRIENDDEV', 'FRIENDDEV2']
        ..noKeys.add('FRIENDDEV2');
      final client = await ready(server);
      await client.send(room, 'partial', 'ts6d_pk');
      final delivered =
          (server.toDevice.single['messages'] as Map)[kFriend] as Map;
      expect(delivered.keys, ['FRIENDDEV']);
      expect(server.sent, hasLength(1));
    });

    test('an encrypted room whose state is unknown refuses before any request', () async {
      final server = encryptedServer()..failState = true;
      final client = await ready(server);
      final before = server.calls.length;
      await expectLater(
        client.send(room, 'who knows', 'ts6d_uk'),
        throwsA(_failure(ChatFailure.notSendable)),
      );
      expect(server.calls.length, before);
    });

    test('a changed device reported by the engine surfaces as a warning', () async {
      final server = encryptedServer();
      final client = await open(
        server,
        planHook: (plan) => plan['action'] == 'send_encrypted'
            ? {
                ...plan,
                'warnings': ['device_changed'],
              }
            : plan,
      );
      addTearDown(client.close);
      await client.connect();
      await client.grantEncryptionConsent();
      expect(await client.send(room, 'careful', 'ts6d_dc'), ['device_changed']);
    });

    test('an action the engine should never name is refused', () async {
      final server = encryptedServer();
      final client = await open(
        server,
        planHook: (plan) => {...plan, 'action': 'logout'},
      );
      addTearDown(client.close);
      await client.connect();
      final before = server.calls.length;
      await expectLater(
        client.send(room, 'x', 'ts6d_bad'),
        throwsA(_failure(ChatFailure.invalid)),
      );
      expect(server.calls.length, before);
    });
  });

  group('consent', () {
    test('without consent nothing is published or sent', () async {
      final server = encryptedServer();
      final client = await open(server);
      addTearDown(client.close);
      await client.connect();
      expect(await client.hasEncryptionConsent(), isFalse);
      final before = server.actions.length;
      await expectLater(
        client.send(room, 'not yet', 'ts6d_c1'),
        throwsA(_failure(ChatFailure.consentRequired)),
      );
      expect(server.actions.length, before);
      expect(server.uploads, isEmpty);
      expect(server.sent, isEmpty);
    });

    test('clear rooms never need it', () async {
      final server = FakeMatrix(room, peer: peer);
      final client = await open(server);
      addTearDown(client.close);
      await client.connect();
      await client.send(room, 'plain', 'ts6d_c2');
      expect(server.sent.single['body'], 'plain');
      expect(server.uploads, isEmpty);
    });

    test('once agreed it publishes once and is remembered across restarts', () async {
      final server = encryptedServer();
      final store = ChatStore(MemoryMyTsSecureBackend());
      final client = await ready(server, store: store);
      await client.send(room, 'one', 'ts6d_c3');
      await client.send(room, 'two', 'ts6d_c4');
      expect(server.uploads, hasLength(1));
      client.close();

      final again = await open(server, store: store);
      addTearDown(again.close);
      expect(await again.hasEncryptionConsent(), isTrue);
      await again.send(room, 'three', 'ts6d_c5');
      expect(server.uploads, hasLength(1));
      expect(server.sent, hasLength(3));
    });

    test('a consent without its snapshot is dropped: a new device is a new decision', () async {
      final store = ChatStore(MemoryMyTsSecureBackend());
      await store.grantEncryptionConsent('account-1');
      final client = await open(encryptedServer(), store: store);
      addTearDown(client.close);
      expect(await client.hasEncryptionConsent(), isFalse);
    });

    test('consent is per account', () async {
      final store = ChatStore(MemoryMyTsSecureBackend());
      await store.grantEncryptionConsent('account-1');
      expect(await store.hasEncryptionConsent('account-1'), isTrue);
      expect(await store.hasEncryptionConsent('account-2'), isFalse);
      expect(
        () => store.hasEncryptionConsent(''),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('controller', () {
    ProviderContainer container(
      FakeMatrix server, {
      Map<String, dynamic> Function(Map<String, dynamic>)? planHook,
    }) {
      final store = ChatStore(MemoryMyTsSecureBackend());
      final c = ProviderContainer(
        overrides: [
          myTsSessionStoreProvider.overrideWithValue(sessions),
          myTsApiProvider.overrideWithValue(
            MyTsApi(
              post: (uri, headers, request, limit) async {
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
              planHook: planHook,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<ChatController> unlocked(ProviderContainer c) async {
      c.listen(chatProvider, (_, _) {});
      final chat = c.read(chatProvider.notifier);
      await chat.unlock(kChatPassword);
      expect(c.read(chatProvider).phase, ChatPhase.ready);
      return chat;
    }

    test('consent gates the first encrypted send; then the message reads as ours', () async {
      final server = encryptedServer();
      final c = container(server);
      final chat = await unlocked(c);
      expect(c.read(chatProvider).rooms.single.encrypted, isTrue);
      expect(await chat.needsEncryptionConsent(room), isTrue);
      expect(await chat.grantEncryptionConsent(), isTrue);
      expect(await chat.needsEncryptionConsent(room), isFalse);

      await chat.send(room, '  sealed hello  ');
      final s = c.read(chatProvider);
      // The harness' contacts service always answers 503: that background
      // refresh is the only error that may show up here, never a send error.
      expect(s.error, anyOf(isNull, ChatError.contacts));
      expect(s.pending[room], isNull);
      final mine = s.messages[room]!.last;
      expect(mine.body, 'sealed hello');
      expect(mine.status, 'decrypted');
      expect(mine.sender, s.account.user);
      expect(server.sent.single.containsKey('body'), isFalse);
    });

    test('a clear room never asks', () async {
      final c = container(FakeMatrix(room, peer: peer));
      final chat = await unlocked(c);
      expect(await chat.needsEncryptionConsent(room), isFalse);
    });

    test('no recipients: the message stays failed with a specific error', () async {
      final server = encryptedServer()..peerDevices = [];
      final c = container(server);
      final chat = await unlocked(c);
      await chat.grantEncryptionConsent();
      await chat.send(room, 'hello?');
      final s = c.read(chatProvider);
      expect(s.error, ChatError.noRecipients);
      expect(s.pending[room]!.single.failed, isTrue);
    });

    test('a failed message neither blocks the next nor is lost on retry', () async {
      final server = encryptedServer();
      final c = container(server);
      final chat = await unlocked(c);
      await chat.grantEncryptionConsent();

      var armed = true;
      server.intercept = (action, r) async {
        if (action == 'send_encrypted' && armed) {
          armed = false;
          throw const SocketException('reset');
        }
        return null;
      };
      await chat.send(room, 'will fail');
      var s = c.read(chatProvider);
      expect(s.error, ChatError.network);
      final failed = s.pending[room]!.single;
      expect(failed.failed, isTrue);

      await chat.send(room, 'goes through');
      s = c.read(chatProvider);
      expect(s.pending[room]!.map((m) => m.text), ['will fail']);
      expect(server.sent, hasLength(1));

      await chat.retry(room, failed.txn);
      s = c.read(chatProvider);
      expect(s.pending[room], isNull);
      expect(server.sent, hasLength(2));
      expect(
        s.messages[room]!.map((m) => m.body),
        containsAll(['ciao', 'will fail', 'goes through']),
      );
    });

    test('a changed contact device raises a notice that can be cleared', () async {
      final c = container(
        encryptedServer(),
        planHook: (plan) => plan['action'] == 'send_encrypted'
            ? {
                ...plan,
                'warnings': ['device_changed'],
              }
            : plan,
      );
      final chat = await unlocked(c);
      await chat.grantEncryptionConsent();
      await chat.send(room, 'heads up');
      expect(c.read(chatProvider).notice, ChatNotice.deviceChanged);
      chat.clearNotice();
      expect(c.read(chatProvider).notice, isNull);
    });
  });
}
