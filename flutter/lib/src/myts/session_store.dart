import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// OS-backed persistence for the myTeamSpeak session.
///
/// The session, account identifier and username are secrets: they live in
/// `flutter_secure_storage` (Keystore/Keychain), never in ordinary
/// `shared_preferences`, bookmark JSON, logs or backups. KDF outputs are never
/// persisted: restoring a session reuses the stored session token.
///
/// The account password itself is kept only while the user leaves "remember
/// password" on (the default; opting out stores nothing). It is what unlocks
/// the chat and import without asking again, and is wiped on sign-out, when
/// the option is switched off, and when it stops working.
///
/// A successful reply without `alternative_login_info` (the demonstrated
/// no-device-ID mode) is fully supported: renewal tokens are simply absent.

/// Key-value backend so unit tests can substitute a memory map for the
/// platform secure storage (which needs method channels). Signing out never
/// uses [deleteAll]: the same store also holds imported identities, bookmark
/// passwords and chat keys. Only the explicit "start from scratch" reset that
/// the user confirms before signing in again does.
abstract class MyTsSecureBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Set<String>> keys();
  Future<void> deleteAll();
}

class FlutterMyTsSecureBackend implements MyTsSecureBackend {
  final FlutterSecureStorage _storage;

  const FlutterMyTsSecureBackend([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Set<String>> keys() async => (await _storage.readAll()).keys.toSet();

  @override
  Future<void> deleteAll() => _storage.deleteAll();
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

  @override
  Future<Set<String>> keys() async => _map.keys.toSet();

  @override
  Future<void> deleteAll() async => _map.clear();
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
  static const kPassword = 'myts_saved_password';
  static const kRememberPassword = 'myts_remember_password';
  // The remember preference is deliberately not listed: signing out forgets
  // the password but keeps the user's choice.
  static const _keys = [
    kSession,
    kUuid,
    kUsername,
    kEmail,
    kWrappedKey,
    kPassword,
  ];

  final MyTsSecureBackend _backend;

  MyTsSessionStore([MyTsSecureBackend? backend])
    : _backend = backend ?? const FlutterMyTsSecureBackend();

  /// Whether the account password may be kept on this device. Defaults to on
  /// (the user can opt out for maximum security); only an explicit `0` turns
  /// it off.
  Future<bool> rememberPassword() async =>
      await _backend.read(kRememberPassword) != '0';

  /// Turning it off also wipes any password already saved.
  Future<void> setRememberPassword(bool value) async {
    await _backend.write(kRememberPassword, value ? '1' : '0');
    if (!value) await clearPassword();
  }

  /// The saved account password, or null when none is stored or remembering
  /// is switched off. Lives in the OS-backed secure storage only.
  Future<String?> loadPassword() async {
    if (!await rememberPassword()) return null;
    final p = await _backend.read(kPassword);
    return p == null || p.isEmpty ? null : p;
  }

  /// Saves [password] if remembering is on; otherwise makes sure none is kept.
  Future<void> savePassword(String password) async {
    if (password.isNotEmpty && await rememberPassword()) {
      await _backend.write(kPassword, password);
    } else {
      await clearPassword();
    }
  }

  Future<void> clearPassword() => _backend.delete(kPassword);

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

  /// Whether anything but the remember-password preference is stored in the
  /// secure storage (session, imported vault, chat keys, contact cache).
  Future<bool> hasStoredData() async =>
      (await _backend.keys()).any((k) => k != kRememberPassword);

  /// Deletes EVERYTHING in the secure storage, including imported identities,
  /// bookmark passwords and the chat's encryption keys. Only for the confirmed
  /// reset before a new sign-in; never part of a normal sign-out.
  Future<void> wipeAll() => _backend.deleteAll();
}
