import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/contact_store.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';

import 'myts_rust.dart';

List<int> field(int n, List<int> value) => [n << 3 | 2, value.length, ...value];

class CorruptibleBackend implements MyTsSecureBackend {
  final entries = <String, String>{};
  @override
  Future<String?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, String value) async {
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }

  @override
  Future<Set<String>> keys() async => entries.keys.toSet();

  @override
  Future<void> deleteAll() async => entries.clear();
}

void main() {
  setUpAll(initRustForTests);

  test('contacts use dedicated read-only tschat RPC and success code', () async {
    Uri? sent;
    final contact = [
      ...field(1, utf8.encode('synthetic-id')),
      ...field(3, utf8.encode('@MY======:example.org')),
    ];
    final body = Uint8List.fromList([
      ...field(1, contact),
      ...field(2, [8, 1]),
    ]);
    final api = MyTsApi(
      post: (uri, headers, request, limit) async {
        sent = uri;
        // Independent AuthenticatedUser wire golden, including the session.
        expect(
          request.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          '0e676574436f6e746163744c6973740a1173796e7468657469632d73657373696f6e',
        );
        expect(limit, 1024 * 1024);
        return MyTsHttpResponse(200, body);
      },
    );
    final roster = await api.contacts('synthetic-session');
    expect(sent, Uri.https('clientapi.myteamspeak.com', '/tschat'));
    expect(roster.single.identifier, 'synthetic-id');
    expect(roster.single.matrixId, '@MY======:example.org');
    await expectLater(
      MyTsApi(
        post: (uri, headers, body, limit) async =>
            MyTsHttpResponse(200, Uint8List(0)),
      ).contacts('s'),
      throwsA(
        isA<ContactRequestFailure>().having(
          (e) => e.kind,
          'kind',
          ContactFailure.invalid,
        ),
      ),
    );
  });

  test(
    'secure snapshot is account scoped and remains on failed refresh',
    () async {
      final backend = CorruptibleBackend();
      final store = ContactStore(backend);
      await store.save(
        ' Alice@Example.org ',
        const ContactSnapshot([
          StoredContact('id', 'note', '@id:example.org'),
        ], 'chat.example.org'),
      );
      expect(
        (await store.load('alice@example.org'))!.contacts.single.note,
        'note',
      );
      expect(await store.load('other@example.org'), isNull);
      expect(
        (await store.load('alice@example.org'))!.chatHost,
        'chat.example.org',
      );
      expect(backend.entries.values.single, isNot(contains('chat-password')));
      final key = backend.entries.keys.single;
      backend.entries[key] = '{corrupt';
      await expectLater(
        store.save('alice@example.org', const ContactSnapshot([], null)),
        throwsFormatException,
      );
      expect(backend.entries[key], '{corrupt');
    },
  );

  test('host validation rejects local and malformed names', () {
    expect(safePublicHttpsHost('chat.example.org'), isTrue);
    for (final host in [
      'localhost',
      '127.0.0.1',
      '192.168.1.1',
      'host.local',
      'a..org',
      'host.internal',
    ]) {
      expect(safePublicHttpsHost(host), isFalse);
    }
  });

  test('GET rejects local destinations before contacting them', () async {
    for (final address in [
      '127.0.0.1',
      '10.1.2.3',
      '169.254.1.1',
      '192.168.1.1',
      '::1',
      '2001:db8::1',
    ]) {
      expect(isPublicAddress(InternetAddress(address)), isFalse);
    }
    expect(isPublicAddress(InternetAddress('8.8.8.8')), isTrue);
    expect(isPublicAddress(InternetAddress('2606:4700:4700::1111')), isTrue);
    await expectLater(
      myTsHttpGet(Uri.https('127.0.0.1', '/versions'), 10),
      throwsFormatException,
    );
    await expectLater(
      myTsHttpGet(Uri.http('example.org', '/versions'), 10),
      throwsFormatException,
    );
  });

  test(
    'avatar case and padding variants send the same metadata request',
    () async {
      final requests = <Uint8List>[];
      final api = MyTsApi(
        post: (uri, headers, request, limit) async {
          expect(uri, Uri.https('clientapi.myteamspeak.com', '/user'));
          requests.add(request);
          // No avatar metadata: do not request a signed URL or image.
          return MyTsHttpResponse(200, Uint8List(0));
        },
      );
      for (final local in [
        'MY======',
        'MY',
        'my======',
        'my',
        'mY======',
        'My',
      ]) {
        expect(
          await api.contactAvatar(
            'session',
            '@$local:example.org',
            'example.org',
          ),
          isNull,
        );
      }
      expect(requests, hasLength(6));
      for (final request in requests.skip(1)) {
        expect(request, requests.first);
      }
    },
  );

  test(
    'avatar derivation skips unsupported homeservers and invalid Base32',
    () async {
      var calls = 0;
      final api = MyTsApi(
        post: (uri, headers, request, limit) async {
          calls++;
          throw StateError('unexpected avatar request');
        },
      );
      expect(
        await api.contactAvatar(
          'session',
          '@MY======:other.example.org',
          'chat.example.org',
        ),
        isNull,
      );
      expect(
        await api.contactAvatar(
          'session',
          // "somebody" itself is valid Base32 once lowercase is accepted.
          '@somebody0:chat.example.org',
          'chat.example.org',
        ),
        isNull,
      );
      expect(calls, 0);
    },
  );
}
