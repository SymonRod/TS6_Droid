// Framing/codec tests: docs/myteamspeak-login-protocol.md, sections 4-6.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/proto.dart';

import 'myts_helpers.dart';

/// Fully synthetic framing golden (section 5): first KDF vector,
// device_name="TS6 Droid test", sync version 1, 109 framed bytes.
const _framingHex = '05 6c6f67696e'
    ' 0a11 416c696365404558414d504c452e434f4d'
    ' 1240 726e38587a7368715051784962376a50565a4e4c6e5651724970443432777833'
    '71656f36754b5668376e6157384c6948305a45457467554f412b34545a6c4977'
    ' 2801'
    ' 4a0e 5453362044726f69642074657374';

void main() {
  test('synthetic framed LoginData golden is 109 bytes', () {
    const wire = 'rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw';
    final body = encodeMyTsLoginData(
      email: 'Alice@EXAMPLE.COM',
      wirePassword: wire,
      deviceName: 'TS6 Droid test',
    );
    final framed = frameMyTsRpc('login', body);
    expect(framed.length, 109);
    expect(
      framed.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      _framingHex.replaceAll(' ', ''),
    );
  });

  test('LoginData carries sync_version 1, not the proto3 default', () {
    final body = encodeMyTsLoginData(email: 'a@b', wirePassword: 'x' * 64);
    final f = scanFields(body);
    expect(scannedVarint(f, 5), 1);
    expect(scannedString(f, 1), 'a@b');
    expect(scannedString(f, 2), 'x' * 64);
  });

  test('LoginData omits unset optionals, includes OTP when given', () {
    final plain = scanFields(encodeMyTsLoginData(email: 'a@b', wirePassword: 'x' * 64));
    expect(plain.containsKey(3), isFalse); // skipSession
    expect(plain.containsKey(4), isFalse); // origin
    expect(plain.containsKey(6), isFalse); // otp
    expect(plain.containsKey(7), isFalse); // device_id
    final withOtp =
        scanFields(encodeMyTsLoginData(email: 'a@b', wirePassword: 'x' * 64, otp: '123456'));
    expect(scannedString(withOtp, 6), '123456');
  });

  test('LoginSession decodes independent of field order', () {
    final shuffled = BytesBuilder()
      ..add(tstring(8, 'bob'))
      ..add(tstring(2, 'sess-1'))
      ..add(tvarintField(5, 200))
      ..add(tstring(4, 'uuid-1'))
      ..add(tvarintField(99, 7)) // unknown field tolerated
      ..add(tstring(100, 'future'));
    final s = decodeMyTsLoginSession(shuffled.toBytes());
    expect(s.error, 200);
    expect(s.session, 'sess-1');
    expect(s.uuid, 'uuid-1');
    expect(s.username, 'bob');
  });

  test('empty reply decodes to defaults, never success', () {
    final s = decodeMyTsLoginSession(Uint8List(0));
    expect(s.error, 0);
    expect(s.session, isEmpty);
  });

  test('malformed protobuf throws', () {
    expect(() => decodeMyTsLoginSession(Uint8List.fromList([0xff, 0xff, 0xff])),
        throwsFormatException);
    expect(() => decodeMyTsLoginStatus(Uint8List.fromList([0x0a])), throwsFormatException);
  });

  test('deleteSession frame is length + name + Session{session}', () {
    final framed = frameMyTsRpc('deleteSession', encodeMyTsSession('abc'));
    expect(framed[0], 'deleteSession'.length); // 0x0d
    expect(ascii.decode(framed.sublist(1, 14)), 'deleteSession');
    final f = scanFields(framed.sublist(14));
    expect(scannedString(f, 1), 'abc');
  });

  test('method names are validated', () {
    expect(() => frameMyTsRpc('', Uint8List(0)), throwsArgumentError);
    expect(() => frameMyTsRpc('x' * 128, Uint8List(0)), throwsArgumentError);
  });

  test('LoginStatus golden: 204 reply is 3 bytes 08 cc 01', () {
    expect(loginStatusReply(204), [0x08, 0xcc, 0x01]);
    final st = decodeMyTsLoginStatus(loginStatusReply(204));
    expect(st.error, 204);
  });
}
