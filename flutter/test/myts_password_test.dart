// KDF golden tests: docs/myteamspeak-login-protocol.md, section 3.
// Synthetic vectors only; no account credentials.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/password.dart';

void main() {
  test('short ASCII vector', () {
    expect(
      myTsWirePassword(email: 'a@b', password: 'pw'),
      'jj4pMIxs3fEOw+NaR3mKjAY3hjGWUkBjkdvAzdLVa8X3G1XYWQ8gnz13hTOilOsi',
    );
  });

  test('ASCII golden, email case-insensitive', () {
    const expected =
        'rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw';
    for (final email in ['Alice@EXAMPLE.COM', 'alice@example.com']) {
      expect(myTsWirePassword(email: email, password: 'correct horse battery staple'),
          expected);
    }
  });

  test('UTF-8 password', () {
    expect(
      myTsWirePassword(email: 'I@EXAMPLE.COM', password: 'päss🔑'),
      'DyeSsvb4vLhbiBtn1NU+pj6EoR74H0A+xuNPWBWNo5EPUotPWEPyiCMI7jS93UUC',
    );
  });

  test('password whitespace is significant', () {
    expect(
      myTsWirePassword(email: 'alice@example.com', password: ' password '),
      'xgFgM9ArJRO+1hxCKGDaavzAmtO/gHwKNJEgCv/18DnWS2M4dWr0XJ3wZDZmlGXA',
    );
    expect(
      myTsWirePassword(email: 'alice@example.com', password: 'password'),
      isNot(myTsWirePassword(email: 'alice@example.com', password: ' password ')),
    );
  });

  test('empty password encodes (server acceptance is a separate question)', () {
    expect(
      myTsWirePassword(email: 'a@b', password: ''),
      'T5Ir2MZzYi7mdaVfjcMGo+Hbftrj5XZvGChm9YfkT05k4ZzTbWW1rByv8xpa+CKU',
    );
  });

  test('wire value is 64-char standard Base64', () {
    final w = myTsWirePassword(email: 'a@b', password: 'pw');
    expect(w.length, 64);
    expect(RegExp(r'^[A-Za-z0-9+/]{64}$').hasMatch(w), isTrue);
  });

  test('ASCII lowercasing leaves non-ASCII bytes unchanged', () {
    // 'I' and 'Z' fold; 'Ä', 'ß', 'é' and the emoji bytes pass through.
    // In particular this is byte-wise, not locale-sensitive folding.
    final input = utf8.encode('IÄßé🔑Z');
    final out = asciiLowerBytes(input);
    expect(out, [...utf8.encode('i'), ...utf8.encode('Äßé🔑'), ...utf8.encode('z')]);
  });

  test('async isolate version agrees with the sync version', () async {
    expect(
      await myTsWirePasswordAsync(email: 'Alice@EXAMPLE.COM', password: 'correct horse battery staple'),
      'rn8XzshqPQxIb7jPVZNLnVQrIpD42wx3qeo6uKVh7naW8LiH0ZEEtgUOA+4TZlIw',
    );
  });
}
