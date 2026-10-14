import 'dart:convert';
import 'dart:typed_data';

/// Minimal proto3 codec for the myTeamSpeak login RPCs.
///
/// Field numbers mirror the recovered schemas in `docs/proto/` (older
/// verified snapshot): `LoginData`/`LoginSession`/`Session`/`LoginStatus`
/// from `myteamspeak_common.proto`, `Sync_Version` from
/// `synchronization_common.proto`. The current build adds `recovery_key`
/// (10) and reply fields the app does not need; unknown fields are skipped
/// on decode, so both schema vintages parse.
///
/// Only the demonstrated password-login subset is encoded; renewal/OTP/
/// sync messages are separate work (docs/myteamspeak-login-protocol.md).

/// Device description sent as `LoginData.device_name` in the demonstrated
/// password login. The server accepted a research description; this is the
/// app's equivalent. There is no demonstrated requirement to invent a
/// `device_id` for a basic login: successful requests omitted it.
const defaultMyTsDeviceName = 'TS6 Droid (Android)';

/// Handler for `POST /authentication` framing:
/// `u8 method_name_length || ASCII(method) || serialized_protobuf`.
/// Method names here are short ASCII; the server rejects names >= 128 bytes.
Uint8List frameMyTsRpc(String method, Uint8List payload) {
  final name = ascii.encode(method);
  if (name.isEmpty || name.length >= 128) {
    throw ArgumentError('invalid RPC method name: $method');
  }
  return Uint8List(name.length + 1 + payload.length)
    ..[0] = name.length
    ..setAll(1, name)
    ..setAll(1 + name.length, payload);
}

class _Writer {
  final _b = BytesBuilder();

  void _varint(int v) {
    assert(v >= 0, 'proto3 field values here are never negative');
    while (v >= 0x80) {
      _b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _b.addByte(v);
  }

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void stringField(int field, String value) {
    if (value.isEmpty) return; // proto3: default scalars need not be emitted
    final bytes = utf8.encode(value);
    _tag(field, 2);
    _varint(bytes.length);
    _b.add(bytes);
  }

  void varintField(int field, int value) {
    if (value == 0) return; // proto3 default
    _tag(field, 0);
    _varint(value);
  }

  Uint8List bytes() => _b.toBytes();
}

/// Encodes `LoginData` for the demonstrated password login.
///
/// [wirePassword] is the 64-char Base64 KDF output, never plaintext.
/// `sync_version` must be `V1_1 (1)`, not the proto3 default 0. Optional
/// scalars the successful request omits (`skipSession`, `origin`,
/// `device_id`, `otp_renewal_token`, `recovery_key`) are never emitted.
Uint8List encodeMyTsLoginData({
  required String email,
  required String wirePassword,
  int syncVersion = 1,
  String deviceName = defaultMyTsDeviceName,
  String? otp,
}) {
  final w = _Writer()
    ..stringField(1, email)
    ..stringField(2, wirePassword)
    ..varintField(5, syncVersion);
  if (otp != null) w.stringField(6, otp);
  w.stringField(9, deviceName);
  return w.bytes();
}

/// Encodes `Session{session}` for `session`/`deleteSession`.
Uint8List encodeMyTsSession(String session) {
  final w = _Writer()..stringField(1, session);
  return w.bytes();
}

class _Reader {
  final Uint8List data;
  int o = 0;

  _Reader(this.data);

  bool get done => o >= data.length;

  int readVarint() {
    var shift = 0;
    var v = 0;
    for (var i = 0; i < 10; i++) {
      if (o >= data.length) throw const FormatException('truncated varint');
      final b = data[o++];
      v |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return v;
      shift += 7;
    }
    throw const FormatException('varint overflow');
  }

  Uint8List readBytes() {
    final n = readVarint();
    if (n < 0 || o + n > data.length) {
      throw const FormatException('truncated field');
    }
    final out = data.sublist(o, o + n);
    o += n;
    return out;
  }

  String readString() => utf8.decode(readBytes(), allowMalformed: true);

  void skipField(int wire) {
    switch (wire) {
      case 0:
        readVarint();
      case 1:
        _skip(8);
      case 2:
        _skip(readVarint());
      case 5:
        _skip(4);
      default:
        throw FormatException('unknown wire type $wire');
    }
  }

  void _skip(int n) {
    if (n < 0 || o + n > data.length) {
      throw const FormatException('truncated field');
    }
    o += n;
  }
}

/// Field bag tolerant to reordering and unknown fields/enum values.
Map<int, List<Object>> _readFields(Uint8List body) {
  final r = _Reader(body);
  final fields = <int, List<Object>>{};
  while (!r.done) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 0) throw const FormatException('field 0 is invalid');
    final Object value;
    switch (wire) {
      case 0:
        value = r.readVarint();
      case 2:
        value = r.readString();
      case 1:
      case 5:
        // Fixed-width fields this app never needs: skip, keep nothing.
        r.skipField(wire);
        continue;
      default:
        throw FormatException('unknown wire type $wire');
    }
    (fields[field] ??= []).add(value);
  }
  return fields;
}

int _firstVarint(Map<int, List<Object>> fields, int field) {
  final v = fields[field];
  if (v == null || v.isEmpty) return 0; // proto3 default
  final x = v.first;
  if (x is! int) throw const FormatException('wrong type for varint field');
  return x;
}

String _firstString(Map<int, List<Object>> fields, int field) {
  final v = fields[field];
  if (v == null || v.isEmpty) return '';
  final x = v.first;
  if (x is! String) throw const FormatException('wrong type for string field');
  return x;
}

/// Decoded `LoginSession` subset the app acts on. Presence/lengths beyond
/// these fields describe one tested request mode, not invariants.
class MyTsLoginSession {
  /// `ErrorCommon` numeric value; success is 200 (`ERROR_LOGIN_OK`).
  /// 0 is the proto3 default and is never success.
  final int error;
  final String session;
  final String uuid;
  final String username;

  const MyTsLoginSession({
    required this.error,
    required this.session,
    required this.uuid,
    required this.username,
  });
}

/// Parses a bare HTTP-200 reply body as `LoginSession` (no method prefix,
/// no envelope). Throws [FormatException] on malformed protobuf.
MyTsLoginSession decodeMyTsLoginSession(Uint8List body) {
  final f = _readFields(body);
  return MyTsLoginSession(
    error: _firstVarint(f, 5),
    session: _firstString(f, 2),
    uuid: _firstString(f, 4),
    username: _firstString(f, 8),
  );
}

/// Decoded `LoginStatus` subset (`session`/`deleteSession` replies).
class MyTsLoginStatus {
  final int error;
  final String uuid;

  const MyTsLoginStatus({required this.error, required this.uuid});
}

/// Throws [FormatException] on malformed protobuf.
MyTsLoginStatus decodeMyTsLoginStatus(Uint8List body) {
  final f = _readFields(body);
  return MyTsLoginStatus(
    error: _firstVarint(f, 1),
    uuid: _firstString(f, 2),
  );
}
