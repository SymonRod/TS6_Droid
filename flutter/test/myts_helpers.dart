// Independent protobuf builders/scanner for myTS tests.
//
// Deliberately hand-rolled here (not via lib/src/myts/proto.dart) so the
// tests verify the app codec against the documented field numbers instead
// of echoing its own implementation.
import 'dart:convert';
import 'dart:typed_data';

Uint8List tvarint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return Uint8List.fromList(out);
}

Uint8List _field(int field, int wire, List<int> payload) => Uint8List.fromList(
      [...tvarint((field << 3) | wire), ...payload],
    );

Uint8List tstring(int field, String s) {
  if (s.isEmpty) return Uint8List(0); // proto3: defaults are not emitted
  final b = utf8.encode(s);
  return _field(field, 2, [...tvarint(b.length), ...b]);
}

Uint8List tvarintField(int field, int v) => _field(field, 0, tvarint(v));

/// Bare `LoginSession` reply body (no method prefix on HTTP 200).
Uint8List loginSessionReply({
  required int error,
  String session = '',
  String uuid = '',
  String username = '',
}) {
  final b = BytesBuilder()
    ..add(tvarintField(5, error))
    ..add(tstring(2, session))
    ..add(tstring(4, uuid))
    ..add(tstring(8, username));
  return b.toBytes();
}

/// Bare `LoginStatus` reply body.
Uint8List loginStatusReply(int error, {String uuid = ''}) {
  final b = BytesBuilder()
    ..add(tvarintField(1, error))
    ..add(tstring(2, uuid));
  return b.toBytes();
}

/// Minimal field scanner: field number -> values (int for varint wire
/// type, String for length-delimited). Unknown wire types throw.
Map<int, List<Object>> scanFields(Uint8List body) {
  int o = 0;
  int readVarint() {
    var shift = 0;
    var v = 0;
    for (;;) {
      final byte = body[o++];
      v |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return v;
      shift += 7;
    }
  }

  final fields = <int, List<Object>>{};
  while (o < body.length) {
    final tag = readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    final Object value;
    if (wire == 0) {
      value = readVarint();
    } else if (wire == 2) {
      final n = readVarint();
      value = utf8.decode(body.sublist(o, o + n));
      o += n;
    } else {
      throw FormatException('wire $wire');
    }
    (fields[field] ??= []).add(value);
  }
  return fields;
}

String scannedString(Map<int, List<Object>> f, int field) {
  final v = f[field];
  if (v == null || v.isEmpty) return '';
  return v.first as String;
}

int scannedVarint(Map<int, List<Object>> f, int field) {
  final v = f[field];
  if (v == null || v.isEmpty) return 0;
  return v.first as int;
}
