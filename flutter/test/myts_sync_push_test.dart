// Sync push tests: gated push against a fake transport with the real Rust
// codec (needs TSLIB_FRB_LIB, see myts_rust.dart). No live service.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ts6_flutter/src/data/stores.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/session_store.dart';
import 'package:ts6_flutter/src/myts/sync.dart';
import 'package:ts6_flutter/src/myts/sync_cursors.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;

import 'fixtures/synthetic_pull.dart';
import 'myts_helpers.dart';
import 'myts_rust.dart';

class _Call {
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
  final int maxBytes;
  _Call(this.uri, this.headers, this.body, this.maxBytes);
}

class _FakeTransport {
  Future<MyTsHttpResponse> Function(_Call call) handler =
      (_) async => MyTsHttpResponse(200, Uint8List(0));
  final calls = <_Call>[];

  Future<MyTsHttpResponse> post(
    Uri uri,
    Map<String, String> headers,
    Uint8List body,
    int maxBytes,
  ) {
    final c = _Call(uri, headers, body, maxBytes);
    calls.add(c);
    return handler(c);
  }
}

/// Bare `synchronizeItems` reply body (no method prefix on HTTP 200).
Uint8List pushReply({
  required int status,
  String global = '',
  Map<int, String> classes = const {},
}) {
  final b = BytesBuilder()..add(tvarintField(1, status));
  for (final e in classes.entries) {
    final c = BytesBuilder()
      ..add(tvarintField(1, e.key))
      ..add(tstring(2, e.value));
    b.add(tbytes(2, c.toBytes()));
  }
  b.add(tstring(3, global));
  return b.toBytes();
}

bool _containsSubsequence(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

SyncPushBookmark _probeBookmark({
  String uuid = 'item-uuid-1',
  String version = 'v2',
  int? port,
}) => SyncPushBookmark(
  itemUuid: uuid,
  itemVersion: version,
  content: rs.MyTsBookmarkContent(
    name: 'Probe',
    address: 'push-probe.invalid',
    port: port ?? 9987,
    nickname: 'Nick',
    identity: '',
    subscribedChannelIds: frb.Uint64List(0),
    channelPasswords: const [],
  ),
  metadata: const rs.MyTsItemMetadata(manipulated: 1, itemType: 0),
);

const _probeIdentity = SyncPushIdentity(
  itemUuid: 'identity-uuid-1',
  itemVersion: 'v3',
  content: rs.MyTsIdentityContent(
    uniqueIdentity: 'synthetic-material',
    idName: 'Name',
    isDefault: true,
  ),
  metadata: rs.MyTsItemMetadata(manipulated: 0),
);

const _owner = fixtureEmail;
const _session = 'synthetic-session';

SyncCursors _stored() => const SyncCursors(
  globalVersion: 'g1',
  classVersions: {0: 'c0', 1: 'c1'},
  itemVersions: {'older-item': 'v1'},
);

void main() {
  setUpAll(initRustForTests);

  late _FakeTransport transport;
  late MemoryMyTsSecureBackend cursorBackend;
  late MyTsApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transport = _FakeTransport();
    cursorBackend = MemoryMyTsSecureBackend();
    api = MyTsApi(post: transport.post, deviceName: 'Test');
  });

  Future<rs.MyTsAccountKey> unlock() async {
    final key = await api.unlockAccountKey(
      email: fixtureEmail,
      password: fixturePassword,
      wrappedKey: fixtureWrappedKey,
    );
    expect(key, isNotNull);
    addTearDown(key!.dispose);
    return key;
  }

  MyTsSync sync({bool pushEnabled = true}) => MyTsSync(
    api: api,
    settings: SettingsStore(),
    cursors: SyncCursorStore(cursorBackend),
    pushEnabled: pushEnabled,
  );

  Future<void> storeCursors() =>
      SyncCursorStore(cursorBackend).save(_owner, _stored());

  test('disabled flag sends nothing even with valid input', () async {
    await storeCursors();
    final key = await unlock();
    final result = await sync(pushEnabled: false).pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.isOk, isFalse);
    expect(result.failure, SyncPushStatus.disabled);
    expect(transport.calls, isEmpty);
  });

  test('opted-out account sends nothing', () async {
    SharedPreferences.setMockInitialValues({'myts_sync_enabled': false});
    await storeCursors();
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.isOk, isFalse);
    expect(result.failure, SyncPushStatus.optedOut);
    expect(transport.calls, isEmpty);
  });

  test('push without stored cursors sends nothing', () async {
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.failure, SyncPushStatus.invalidInput);
    expect(transport.calls, isEmpty);
  });

  test('empty session sends nothing', () async {
    await storeCursors();
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: '',
      key: key,
      item: _probeBookmark(),
    );
    expect(result.failure, SyncPushStatus.invalidInput);
    expect(transport.calls, isEmpty);
  });

  test('unencodable bookmark sends nothing', () async {
    await storeCursors();
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(port: 0),
    );
    expect(result.failure, SyncPushStatus.invalidInput);
    expect(transport.calls, isEmpty);
  });

  test('accepted push advances global, class and item cursors', () async {
    await storeCursors();
    transport.handler = (_) async => MyTsHttpResponse(
      200,
      pushReply(status: 300, global: 'g9', classes: {0: 'c0n', 1: 'c1n'}),
    );
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.isOk, isTrue);
    expect(result.cursors!.globalVersion, 'g9');
    expect(result.cursors!.classVersions, {0: 'c0n', 1: 'c1n'});
    expect(result.cursors!.itemVersions, {'older-item': 'v1', 'item-uuid-1': 'v2'});

    // Transport contract: one framed push to the sync path.
    expect(transport.calls.length, 1);
    final seen = transport.calls.single;
    expect(seen.uri, Uri.https('clientapi.myteamspeak.com', '/synchronization'));
    expect(seen.headers['content-type'], 'application/ts3cloud');
    expect(seen.maxBytes, 8 * 1024 * 1024);
    expect(seen.body[0], 'synchronizeItems'.length);
    expect(ascii.decode(seen.body.sublist(1, 17)), 'synchronizeItems');
    // The bookmark address travels encrypted, never in cleartext.
    expect(
      _containsSubsequence(seen.body, utf8.encode('push-probe.invalid')),
      isFalse,
    );

    // Cursors were persisted, not just returned.
    final reloaded = await SyncCursorStore(cursorBackend).load(_owner);
    expect(reloaded!.globalVersion, 'g9');
    expect(reloaded.itemVersions['item-uuid-1'], 'v2');
  });

  test('identity push records the class-1 cursor', () async {
    await storeCursors();
    transport.handler = (_) async => MyTsHttpResponse(
      200,
      pushReply(status: 300, global: 'g5', classes: {0: 'c0', 1: 'c1b'}),
    );
    final key = await unlock();
    final result = await sync().pushIdentity(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeIdentity,
    );
    expect(result.isOk, isTrue);
    expect(result.cursors!.classVersions[1], 'c1b');
    expect(result.cursors!.itemVersions['identity-uuid-1'], 'v3');
    expect(transport.calls.length, 1);
  });

  test('collision surfaces and leaves cursors untouched', () async {
    await storeCursors();
    transport.handler = (_) async => MyTsHttpResponse(
      200,
      pushReply(status: 303, global: 'gX'),
    );
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.isOk, isFalse);
    expect(result.failure, SyncPushStatus.conflict);
    expect(result.serverStatus, 303);
    final reloaded = await SyncCursorStore(cursorBackend).load(_owner);
    expect(reloaded!.globalVersion, 'g1');
    expect(reloaded.itemVersions.containsKey('item-uuid-1'), isFalse);
  });

  test('expired session and http failures map without cursor writes', () async {
    await storeCursors();
    final key = await unlock();
    transport.handler = (_) async =>
        MyTsHttpResponse(200, pushReply(status: 102));
    expect(
      (await sync().pushBookmark(
        owner: _owner,
        session: _session,
        key: key,
        item: _probeBookmark(),
      )).failure,
      SyncPushStatus.sessionExpired,
    );
    transport.handler = (_) async => MyTsHttpResponse(503, Uint8List(0));
    final http = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(http.failure, SyncPushStatus.http);
    expect(http.httpStatus, 503);
    final reloaded = await SyncCursorStore(cursorBackend).load(_owner);
    expect(reloaded!.globalVersion, 'g1');
  });

  test('transport failure maps to network without cursor writes', () async {
    await storeCursors();
    transport.handler = (_) async => throw const SocketException('down');
    final key = await unlock();
    final result = await sync().pushBookmark(
      owner: _owner,
      session: _session,
      key: key,
      item: _probeBookmark(),
    );
    expect(result.failure, SyncPushStatus.network);
    final reloaded = await SyncCursorStore(cursorBackend).load(_owner);
    expect(reloaded!.globalVersion, 'g1');
  });
}
