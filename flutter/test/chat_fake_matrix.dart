import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;

Uint8List hexBytes(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

Uint8List jsonBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// Wrapped account key and password of the history fixture.
const kWrappedKey =
    '02323ec445370cb098574647e56416e082000102030405060708090a0bdf3d396ab4b8ccefbfd431d67420448f56791f8f13c313943db655c533aaf63b';
const kChatPassword = 'correct horse battery staple';

const kFriend = '@friend:example.invalid';

/// The libolm peer written by `tools/myts/generate_e2ee_peer_fixture.py`.
Future<Map<String, dynamic>> loadPeerFixture() async =>
    jsonDecode(await File('test/fixtures/e2ee_peer.json').readAsString())
        as Map<String, dynamic>;

/// A tiny in-memory Matrix server answering the exact requests the Rust engine
/// builds. `encrypted` toggles the room state; [peer] (the libolm fixture) lets it
/// answer the end-to-end key requests too. It never decrypts anything: that is
/// proven by the Rust tests and the libolm interop test, these tests prove the
/// plumbing around them.
class FakeMatrix {
  final String room;
  bool encrypted;

  /// A third member: the room has no single peer (a group).
  final bool group;
  final Map<String, dynamic>? peer;

  /// Devices `keys/query` reports for the friend.
  List<String> peerDevices = ['FRIENDDEV'];

  /// Report the "changed" keys for FRIENDDEV instead of the original ones.
  bool changedKeys = false;

  /// Devices that have no one-time and no fallback key to give.
  final noKeys = <String>{};
  bool failState = false;

  final calls = <String>[];

  /// The engine action of every request, in order (including failed ones).
  final actions = <String>[];

  /// Every request body as text: nothing the user typed may appear in one.
  final bodies = <String>[];

  /// Accepted room events (plain or encrypted) with their transaction ID.
  final sent = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  final uploads = <Map<String, dynamic>>[];
  final claims = <Map<String, dynamic>>[];

  /// Every `sendToDevice` body that arrived, accepted or not.
  final shareAttempts = <String>[];
  final toDevice = <Map<String, dynamic>>[];
  Map<String, dynamic>? presenceBody;
  String user = '';
  String device = '';
  int failSendsWith = 0;
  int oneTimeKeys = 0;

  /// Before a request is handled: return a response to answer in its place, or
  /// throw to make the transport fail. Return null to carry on.
  Future<MyTsHttpResponse?> Function(String action, rs.MyTsHistoryRequest r)?
  intercept;

  final _roomTxns = <String, String>{};
  final _deviceTxns = <String>{};
  final _claimed = <String, int>{};

  FakeMatrix(this.room, {this.encrypted = false, this.group = false, this.peer}) {
    events.add({
      'event_id': r'$first',
      'type': 'm.room.message',
      'sender': kFriend,
      'origin_server_ts': 1000,
      'content': {'msgtype': 'm.text', 'body': 'ciao'},
    });
  }

  MyTsHttpResponse ok(Object? body) => MyTsHttpResponse(200, jsonBytes(body));

  Future<MyTsHttpResponse> handle(
    rs.MyTsHistoryRequest r,
    String action,
  ) async {
    calls.add('${r.method} ${r.segments.skip(3).join('/')}');
    actions.add(action);
    bodies.add(utf8.decode(r.body, allowMalformed: true));
    final early = await intercept?.call(action, r);
    return early ?? process(r, action);
  }

  /// The server's own behaviour, without any fault injection.
  Future<MyTsHttpResponse> process(
    rs.MyTsHistoryRequest r,
    String action,
  ) async {
    Map<String, dynamic> body() =>
        jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
    switch (action) {
      case 'login':
        final login = body();
        user = (login['identifier'] as Map)['user'] as String;
        device = login['device_id'] as String;
        return ok({
          'user_id': user,
          'device_id': device,
          'access_token': 'synthetic-token',
        });
      case 'whoami':
        return ok({'user_id': user, 'device_id': device});
      case 'rooms':
        return ok({
          'joined_rooms': [room],
        });
      case 'invites':
        return ok({});
      case 'direct':
        return MyTsHttpResponse(404, Uint8List(0));
      case 'presence_get':
        return MyTsHttpResponse(404, Uint8List(0));
      case 'profile':
        return ok({'displayname': 'Friendly'});
      case 'state':
        if (failState) return MyTsHttpResponse(500, Uint8List(0));
        return ok([
          {
            'type': 'm.room.member',
            'state_key': kFriend,
            'content': {'membership': 'join', 'displayname': 'Friend'},
          },
          {
            'type': 'm.room.member',
            'state_key': user,
            'content': {'membership': 'join'},
          },
          if (group)
            {
              'type': 'm.room.member',
              'state_key': '@third:example.invalid',
              'content': {'membership': 'join'},
            },
          if (encrypted) {'type': 'm.room.encryption', 'content': {}},
        ]);
      case 'messages':
        return ok({'chunk': events.reversed.toList(), 'end': 't1'});
      case 'send':
        if (failSendsWith != 0) {
          return MyTsHttpResponse(failSendsWith, Uint8List(0));
        }
        return _store(r, 'm.room.message', body());
      case 'send_encrypted':
        return _store(r, 'm.room.encrypted', body());
      case 'keys_upload':
        final upload = body();
        uploads.add(upload);
        oneTimeKeys += (upload['one_time_keys'] as Map?)?.length ?? 0;
        return ok({
          'one_time_key_counts': {'signed_curve25519': oneTimeKeys},
        });
      case 'keys_query':
        return _query(body());
      case 'keys_claim':
        return _claim(body());
      case 'share_keys':
        shareAttempts.add(utf8.decode(r.body));
        if (_deviceTxns.add(r.segments.last)) {
          toDevice.add({'txn': r.segments.last, ...body()});
        }
        return ok({});
      case 'presence_set':
        presenceBody = body();
        return ok({});
    }
    return MyTsHttpResponse(400, Uint8List(0));
  }

  /// A room event; a transaction ID the server has seen returns the first event
  /// again and stores nothing, as a real homeserver does.
  MyTsHttpResponse _store(
    rs.MyTsHistoryRequest r,
    String type,
    Map<String, dynamic> content,
  ) {
    final txn = r.segments.last;
    final seen = _roomTxns[txn];
    if (seen != null) return ok({'event_id': seen});
    sent.add({'txn': txn, ...content});
    final id = '\$sent${sent.length}';
    _roomTxns[txn] = id;
    events.add({
      'event_id': id,
      'type': type,
      'sender': user,
      'origin_server_ts': 2000 + sent.length,
      'content': content,
    });
    return ok({'event_id': id});
  }

  Map<String, dynamic> get _devices =>
      (peer!['devices'] as Map).cast<String, dynamic>();

  MyTsHttpResponse _query(Map<String, dynamic> body) {
    final asked = (body['device_keys'] as Map).keys;
    final reply = <String, Object?>{};
    if (peer != null && asked.contains(kFriend)) {
      reply[kFriend] = {
        for (final d in peerDevices)
          d: changedKeys && d == 'FRIENDDEV'
              ? (peer!['changed'] as Map)[d]
              : (_devices[d] as Map)['device_keys'],
      };
    }
    return ok({'device_keys': reply, 'failures': {}});
  }

  MyTsHttpResponse _claim(Map<String, dynamic> body) {
    claims.add(body);
    final wanted = ((body['one_time_keys'] as Map)[kFriend] as Map?) ?? {};
    final given = <String, Object?>{};
    for (final d in wanted.keys.cast<String>()) {
      final info = peer == null ? null : _devices[d] as Map?;
      if (info == null || noKeys.contains(d)) continue;
      final keys = (info['one_time_keys'] as Map).entries.toList();
      final used = _claimed[d] ?? 0;
      if (used < keys.length) {
        _claimed[d] = used + 1;
        given[d] = {keys[used].key: keys[used].value};
      } else {
        given[d] = info['fallback_key'];
      }
    }
    return ok({
      'one_time_keys': {kFriend: given},
      'failures': {},
    });
  }
}
