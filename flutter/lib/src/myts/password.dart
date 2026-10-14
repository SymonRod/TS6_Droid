import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// myTeamSpeak password derivation.
///
/// Demonstrated end to end against the desktop client and the live
/// `/authentication` endpoint (docs/myteamspeak-login-protocol.md, section 2):
///
/// ```text
/// salt = asciiLowercase(emailBytes) || ASCII("ts3Login") || passwordBytes
/// DK   = PBKDF2-HMAC-SHA512(passwordBytes, salt, iterations=10000, dkLen=48)
/// wire = standard_Base64(DK)   // 64 chars, no padding
/// ```
///
/// Rules that must not drift: the password is case- and whitespace-sensitive
/// (never trim, lowercase or normalize it); the email lowercasing is
/// ASCII-only and locale-independent; PBKDF2 takes the raw password bytes
/// (not a SHA-512 digest) with big-endian block counter `00 00 00 01`.
const int myTsPbkdf2Iterations = 10000;

/// Derived key length in bytes for the login credential (48, not 32: the
/// 32-byte `ts3Encryption` value is a separate derivation kept out of login).
const int myTsLoginKeyBytes = 48;

/// ASCII-only lowercase of UTF-8 bytes: `A..Z` map to `a..z`, every other
/// byte (including non-ASCII UTF-8 sequences) is left unchanged. This mirrors
/// the desktop's byte-wise `std::ctype<char>::tolower` helper and Python's
/// `bytes.lower()`. Do not replace it with locale-sensitive case folding:
/// e.g. a Turkish locale must not turn `I` into dotless `i`.
Uint8List asciiLowerBytes(Uint8List input) {
  final out = Uint8List(input.length);
  for (var i = 0; i < input.length; i++) {
    final b = input[i];
    out[i] = (b >= 0x41 && b <= 0x5a) ? b + 0x20 : b;
  }
  return out;
}

/// PBKDF2 with HMAC-SHA512. Only single-block output (`dkLen` <= 64) is
/// needed here, so the block counter is always the standard big-endian
/// `00 00 00 01` and the result is `U1 XOR ... XOR U_iterations`.
Uint8List _pbkdf2HmacSha512({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int dkLen,
}) {
  assert(dkLen > 0 && dkLen <= sha512.blockSize,
      'only single-block output is supported');
  final hmac = Hmac(sha512, password);
  final first = Uint8List(salt.length + 4)
    ..setAll(0, salt)
    ..setAll(salt.length, const [0, 0, 0, 1]);
  var u = Uint8List.fromList(hmac.convert(first).bytes);
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out.sublist(0, dkLen);
}

/// Raw 48-byte derived login key. Prefer [myTsWirePasswordAsync] on the UI
/// thread; this synchronous version is for tests and background callers.
Uint8List deriveMyTsLoginKey({required String email, required String password}) {
  final p = Uint8List.fromList(utf8.encode(password));
  final e = asciiLowerBytes(Uint8List.fromList(utf8.encode(email)));
  // ASCII("ts3Login"), no separators, no NUL, no length prefix.
  const label = [0x74, 0x73, 0x33, 0x4c, 0x6f, 0x67, 0x69, 0x6e];
  final salt = Uint8List(e.length + label.length + p.length)
    ..setAll(0, e)
    ..setAll(e.length, label)
    ..setAll(e.length + label.length, p);
  return _pbkdf2HmacSha512(
    password: p,
    salt: salt,
    iterations: myTsPbkdf2Iterations,
    dkLen: myTsLoginKeyBytes,
  );
}

/// The `LoginData.password` wire value: standard Base64 of the derived key.
/// Only this string (never the plaintext, salt or raw bytes) goes into the
/// protobuf request, logs or diagnostics.
String myTsWirePassword({required String email, required String password}) =>
    base64.encode(deriveMyTsLoginKey(email: email, password: password));

/// Same as [myTsWirePassword] but computed off the calling isolate, so the
/// ~10k HMAC-SHA512 rounds never block UI or audio work.
Future<String> myTsWirePasswordAsync({
  required String email,
  required String password,
}) =>
    Isolate.run(() => myTsWirePassword(email: email, password: password));
