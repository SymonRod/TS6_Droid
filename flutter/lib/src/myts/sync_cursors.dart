import 'dart:async';
import 'dart:convert';

import 'session_store.dart';

/// Sync cursors for myTeamSpeak write-back.
///
/// The service hands out opaque version strings (`globalversion`, per-class
/// versions, per-item `item_version`s) on every pull and accepted push. A
/// later push must send the last-known ones back, so they are persisted here:
/// one secure-storage entry, written atomically, scoped to the normalized
/// account email. Versions are opaque protocol metadata, not secrets, but
/// they share the vault's storage and write discipline so a cursor update
/// can never be half applied.
///
/// Cursors advance ONLY on an accepted push (`IN_SYNC`): every other outcome
/// — collision, expiry, transport failure — leaves them untouched. A load
/// for a different account returns null instead of leaking cursors across
/// accounts. Unreadable content throws; it is never treated as empty.
class SyncCursors {
  /// Last accepted `globalversion`, empty before the first stored pull/push.
  final String globalVersion;

  /// Sync class number (0 = bookmark, 1 = identity) -> last-known version.
  final Map<int, String> classVersions;

  /// Cloud item UUID -> last-known outer `item_version`.
  final Map<String, String> itemVersions;

  const SyncCursors({
    this.globalVersion = '',
    this.classVersions = const {},
    this.itemVersions = const {},
  });

  Map<String, dynamic> toJson() => {
    'globalVersion': globalVersion,
    'classes': {for (final e in classVersions.entries) '${e.key}': e.value},
    'items': itemVersions,
  };

  factory SyncCursors.fromJson(Map<String, dynamic> j) {
    final globalVersion = j['globalVersion'];
    if (globalVersion is! String) _bad('globalVersion');
    final classes = j['classes'];
    if (classes is! Map) _bad('classes');
    final classVersions = <int, String>{};
    classes.forEach((k, v) {
      final number = int.tryParse('$k');
      if (number == null || number < 0 || number > 8) _bad('class');
      if (v is! String) _bad('class version');
      classVersions[number] = v;
    });
    final items = j['items'];
    if (items is! Map) _bad('items');
    final itemVersions = <String, String>{};
    items.forEach((k, v) {
      if (v is! String) _bad('item version');
      itemVersions['$k'] = v;
    });
    return SyncCursors(
      globalVersion: globalVersion,
      classVersions: classVersions,
      itemVersions: itemVersions,
    );
  }
}

Never _bad(String what) => throw FormatException('Invalid sync cursors $what');

/// Normalized account key scoping the cursors (same rule as the vault owner).
String syncOwner(String email) => email.trim().toLowerCase();

class SyncCursorStore {
  static const version = 1;
  static const storageKey = 'ts6_sync_cursors_v1';

  final MyTsSecureBackend _backend;
  Future<void> _tail = Future.value();

  SyncCursorStore([MyTsSecureBackend? backend])
    : _backend = backend ?? const FlutterMyTsSecureBackend();

  /// Serializes every read-modify-write, so concurrent pushes cannot
  /// interleave and lose each other's cursor advances.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Stored cursors for [email], or null when none were saved for this
  /// account. Throws when stored data exists but cannot be read.
  Future<SyncCursors?> load(String email) async {
    final raw = await _backend.read(storageKey);
    if (raw == null) return null;
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> ||
        j['v'] != version ||
        j['owner'] is! String) {
      _bad('envelope');
    }
    if (j['owner'] != syncOwner(email)) return null;
    final cursors = j['cursors'];
    if (cursors is! Map<String, dynamic>) _bad('cursors');
    return SyncCursors.fromJson(cursors);
  }

  /// One write of the whole new cursor state, read back to confirm what was
  /// stored. On failure the previous content is put back (best effort), so a
  /// failed advance keeps the old cursors. Callers hold [synchronized]
  /// while they load, push and save.
  Future<void> save(String email, SyncCursors cursors) async {
    final raw = jsonEncode({
      'v': version,
      'owner': syncOwner(email),
      'cursors': cursors.toJson(),
    });
    final previous = await _backend.read(storageKey);
    try {
      await _backend.write(storageKey, raw);
      if (await _backend.read(storageKey) != raw) {
        throw StateError('Cursor write was not persisted');
      }
    } catch (_) {
      try {
        if (previous == null) {
          await _backend.delete(storageKey);
        } else {
          await _backend.write(storageKey, previous);
        }
      } catch (_) {
        // Nothing more can be done; the original error is what matters.
      }
      rethrow;
    }
  }

  /// Drops the stored cursors (sign-out of the owning account). The vault
  /// and session keys are untouched; see their own `clear()`.
  Future<void> clear() => _backend.delete(storageKey);
}
