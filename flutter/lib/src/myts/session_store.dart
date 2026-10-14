import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// OS-backed persistence for the myTeamSpeak session.
///
/// The session, account identifier and username are secrets: they live in
/// `flutter_secure_storage` (Keystore/Keychain), never in ordinary
/// `shared_preferences`, bookmark JSON, logs or backups. The password and
/// KDF outputs are never persisted: restoring a session reuses the stored
/// session token, it never re-derives credentials.
///
/// A successful reply without `alternative_login_info` (the demonstrated
/// no-device-ID mode) is fully supported: renewal tokens are simply absent.

/// Key-value backend so unit tests can substitute a memory map for the
/// platform secure storage (which needs method channels). There is no
/// delete-all operation on purpose: the same store also holds imported
/// identities and bookmark passwords, which signing out must never wipe.
abstract class MyTsSecureBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterMyTsSecureBackend implements MyTsSecureBackend {
  final FlutterSecureStorage _storage;

  const FlutterMyTsSecureBackend([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryMyTsSecureBackend implements MyTsSecureBackend {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}

class MyTsStoredSession {
  final String session;
  final String uuid;
  final String username;
  final String email;

  /// Binary `LoginSession.key` exactly as the service sent it. It is the
  /// *wrapped* account key: ciphertext that is useless without the account
  /// password, so a later import can unwrap it again. Empty when absent.
  final Uint8List wrappedKey;

  const MyTsStoredSession({
    required this.session,
    required this.uuid,
    required this.username,
    required this.email,
    required this.wrappedKey,
  });
}

class MyTsSessionStore {
  static const kSession = 'myts_session';
  static const kUuid = 'myts_uuid';
  static const kUsername = 'myts_username';
  static const kEmail = 'myts_email';
  static const kWrappedKey = 'myts_wrapped_key';
  static const _keys = [kSession, kUuid, kUsername, kEmail, kWrappedKey];

  final MyTsSecureBackend _backend;

  MyTsSessionStore([MyTsSecureBackend? backend])
      : _backend = backend ?? const FlutterMyTsSecureBackend();

  Future<void> save({
    required String session,
    required String uuid,
    required String username,
    required String email,
    List<int> wrappedKey = const [],
  }) async {
    await _backend.write(kSession, session);
    await _backend.write(kUuid, uuid);
    await _backend.write(kUsername, username);
    await _backend.write(kEmail, email);
    await _backend.write(kWrappedKey, base64.encode(wrappedKey));
  }

  /// Null when no session was stored, or when the stored session is empty
  /// (an empty/default reply is never treated as a session).
  Future<MyTsStoredSession?> load() async {
    final session = await _backend.read(kSession);
    if (session == null || session.isEmpty) return null;
    return MyTsStoredSession(
      session: session,
      uuid: await _backend.read(kUuid) ?? '',
      username: await _backend.read(kUsername) ?? '',
      email: await _backend.read(kEmail) ?? '',
      wrappedKey: _decodeKey(await _backend.read(kWrappedKey)),
    );
  }

  static Uint8List _decodeKey(String? stored) {
    if (stored == null || stored.isEmpty) return Uint8List(0);
    try {
      return base64.decode(stored);
    } on FormatException {
      return Uint8List(0); // Unreadable key: unwrap then fails closed.
    }
  }

  /// Local wipe of the session keys only. Server-side deletion is attempted
  /// first by the controller but logout always ends here, offline or not.
  /// Never `deleteAll()`: the secure storage also holds imported identities
  /// and bookmark passwords, which signing out must not destroy.
  Future<void> clear() async {
    for (final key in _keys) {
      await _backend.delete(key);
    }
  }
}
