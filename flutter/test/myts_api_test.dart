// Transport + error-mapping tests (no real network):
// docs/myteamspeak-login-protocol.md, sections 4-7 acceptance items 3-4.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/api.dart';

import 'myts_helpers.dart';

class _Call {
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
  _Call(this.uri, this.headers, this.body);
}

class _FakeTransport {
  final Future<MyTsHttpResponse> Function(_Call call) handler;
  final calls = <_Call>[];
  _FakeTransport(this.handler);

  Future<MyTsHttpResponse> post(Uri uri, Map<String, String> headers, Uint8List body) {
    final c = _Call(uri, headers, body);
    calls.add(c);
    return handler(c);
  }
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

MyTsApi apiWith(_FakeTransport t, {String deviceName = 'Test device'}) =>
    MyTsApi(post: t.post, deviceName: deviceName);

void main() {
  test('successful login: endpoint, headers, framing, reply decoding', () async {
    late _Call seen;
    final t = _FakeTransport((c) async {
      seen = c;
      return MyTsHttpResponse(
        200,
        loginSessionReply(error: 200, session: 'sess-36-chars-padded--------x', uuid: 'uuid-1', username: 'bob'),
      );
    });
    final api = apiWith(t);
    final outcome = await api.login(email: 'alice@example.com', password: 'secret pw');

    expect(outcome.isOk, isTrue);
    expect(outcome.success!.session, 'sess-36-chars-padded--------x');
    expect(outcome.success!.uuid, 'uuid-1');
    expect(outcome.success!.username, 'bob');

    // Transport contract.
    expect(seen.uri, Uri.https('clientapi.myteamspeak.com', '/authentication'));
    expect(seen.headers['content-type'], 'application/ts3cloud');
    expect(seen.body[0], 5);
    expect(ascii.decode(seen.body.sublist(1, 6)), 'login');

    // Request protobuf: same email for KDF and request, 64-char derived
    // password (never plaintext), sync_version 1, device name present.
    final f = scanFields(seen.body.sublist(6));
    expect(scannedString(f, 1), 'alice@example.com');
    final sentPw = scannedString(f, 2);
    expect(sentPw.length, 64);
    expect(sentPw, isNot(contains('secret pw')));
    expect(_containsSubsequence(seen.body, utf8.encode('secret pw')), isFalse);
    expect(scannedVarint(f, 5), 1);
    expect(scannedString(f, 9), 'Test device');
    expect(f.containsKey(6), isFalse); // no OTP on the first step
  });

  test('OTP is only sent on the explicit second step', () async {
    Uint8List? body;
    final t = _FakeTransport((c) async {
      body = c.body;
      return MyTsHttpResponse(200, loginSessionReply(error: 200, session: 's', uuid: 'u'));
    });
    final api = apiWith(t);
    await api.login(email: 'a@b', password: 'pw', otp: '123456');
    final f = scanFields(body!.sublist(6));
    expect(scannedString(f, 6), '123456');
  });

  test('error mapping for application codes', () async {
    final cases = {
      202: MyTsFailure.credentials,
      201: MyTsFailure.offline,
      203: MyTsFailure.emailPending,
      208: MyTsFailure.otpRequired,
      209: MyTsFailure.otpInvalid,
      999: MyTsFailure.other, // unknown enum: safe, informative, not success
    };
    for (final entry in cases.entries) {
      final t = _FakeTransport(
          (_) async => MyTsHttpResponse(200, loginSessionReply(error: entry.key)));
      final outcome = await apiWith(t).login(email: 'a@b', password: 'pw');
      expect(outcome.isOk, isFalse, reason: 'code ${entry.key}');
      expect(outcome.failure, entry.value, reason: 'code ${entry.key}');
      expect(outcome.appError, entry.key, reason: 'code ${entry.key}');
    }
  });

  test('no success without HTTP 200, parseable reply and nonempty session', () async {
    // Non-200 body is never parsed (it may be an HTML gateway page).
    var parsed = false;
    final http = _FakeTransport((_) async {
      parsed = true;
      return MyTsHttpResponse(500, utf8.encode('<html>gateway</html>'));
    });
    final o500 = await apiWith(http).login(email: 'a@b', password: 'pw');
    expect(o500.failure, MyTsFailure.http);
    expect(o500.httpStatus, 500);
    expect(parsed, isTrue); // transport ran; decoding must not.

    final malformed =
        _FakeTransport((_) async => MyTsHttpResponse(200, Uint8List.fromList([0xff])));
    expect((await apiWith(malformed).login(email: 'a@b', password: 'pw')).failure,
        MyTsFailure.malformed);

    final empty =
        _FakeTransport((_) async => MyTsHttpResponse(200, Uint8List(0)));
    expect((await apiWith(empty).login(email: 'a@b', password: 'pw')).failure,
        MyTsFailure.malformed);

    // error=200 with an empty session is not a session.
    final noSession = _FakeTransport(
        (_) async => MyTsHttpResponse(200, loginSessionReply(error: 200)));
    final o = await apiWith(noSession).login(email: 'a@b', password: 'pw');
    expect(o.isOk, isFalse);
    expect(o.failure, MyTsFailure.malformed);
  });

  test('network failures are distinct from application errors', () async {
    for (final err in [const SocketException('down'), TimeoutException('t'), TlsException('tls')]) {
      final t = _FakeTransport((_) => Future.error(err));
      final o = await apiWith(t).login(email: 'a@b', password: 'pw');
      expect(o.failure, MyTsFailure.network, reason: '$err');
    }
  });

  test('empty email or password sends nothing', () async {
    var called = false;
    final t = _FakeTransport((_) async {
      called = true;
      return MyTsHttpResponse(200, loginSessionReply(error: 200, session: 's'));
    });
    final api = apiWith(t);
    expect((await api.login(email: '', password: 'pw')).failure, MyTsFailure.invalidInput);
    expect((await api.login(email: 'a@b', password: '')).failure, MyTsFailure.invalidInput);
    expect(called, isFalse);
  });

  test('deleteSession confirms only on 204', () async {
    _Call? seen;
    final ok = _FakeTransport((c) async {
      seen = c;
      return MyTsHttpResponse(200, loginStatusReply(204));
    });
    expect(await apiWith(ok).deleteSession('sess'), isTrue);
    expect(seen!.body[0], 'deleteSession'.length);
    expect(ascii.decode(seen!.body.sublist(1, 14)), 'deleteSession');

    final wrong = _FakeTransport((_) async => MyTsHttpResponse(200, loginStatusReply(202)));
    expect(await apiWith(wrong).deleteSession('sess'), isFalse);

    final http = _FakeTransport((_) async => MyTsHttpResponse(500, Uint8List(0)));
    expect(await apiWith(http).deleteSession('sess'), isFalse);

    final down = _FakeTransport((_) => Future.error(const SocketException('x')));
    expect(await apiWith(down).deleteSession('sess'), isFalse);

    expect(await apiWith(ok).deleteSession(''), isFalse);
  });
}
