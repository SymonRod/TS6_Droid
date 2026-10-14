import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../myts/session_store.dart';

/// Identities and bookmarks imported from a myTeamSpeak account.
///
/// Everything lives in ONE secure-storage entry, written in one operation, so
/// an import is atomic: the vault holds either the old state or the complete
/// new state. Private identity strings and bookmark passwords therefore never
/// touch `shared_preferences`, files or logs. Nothing here is ever deleted by
/// a sign-out: the session store only removes its own keys.
///
/// Cloud references are kept exactly as received and are never rewritten. The
/// user's own identity choice for a bookmark is a separate local [links] entry.

/// Stable local ID of a cloud item, derived from account and cloud ID so that
/// importing again never creates a second copy.
String vaultItemId(String kind, String owner, String cloudId) {
  final digest = sha256.convert(utf8.encode('$kind\u0000$owner\u0000$cloudId'));
  return '${kind[0]}-${digest.toString().substring(0, 32)}';
}

/// Normalized account key used as the ownership label of imported items.
String vaultOwner(String email) => email.trim().toLowerCase();

Never _bad(String what) => throw FormatException('Invalid vault $what');

String _str(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! String) _bad(k);
  return v;
}

String? _optStr(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is! String) _bad(k);
  return v;
}

bool? _optBool(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is! bool) _bad(k);
  return v;
}

class VaultIdentity {
  final String id;
  final String owner;
  final String cloudId;
  final String cloudVersion;

  /// Public UID as verified by the strict validator at import time.
  final String uid;

  /// Hash-cash counter from the cloud string (u64, so a [BigInt]).
  final BigInt counter;

  /// The original cloud private identity (desktop format). A secret.
  final String desktopString;
  final String? name;
  final String? nickname;
  final String? phoneticNickname;

  /// Cloud flag as received. Several identities may carry `true`; it is not
  /// used to pick an identity.
  final bool? cloudDefault;

  const VaultIdentity({
    required this.id,
    required this.owner,
    required this.cloudId,
    required this.cloudVersion,
    required this.uid,
    required this.counter,
    required this.desktopString,
    this.name,
    this.nickname,
    this.phoneticNickname,
    this.cloudDefault,
  });

  String get label {
    for (final c in [name, nickname]) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return uid;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'cloudId': cloudId,
    'cloudVersion': cloudVersion,
    'uid': uid,
    'counter': counter.toString(),
    'key': desktopString,
    'name': name,
    'nickname': nickname,
    'phonetic': phoneticNickname,
    'cloudDefault': cloudDefault,
  };

  factory VaultIdentity.fromJson(Map<String, dynamic> j) {
    final counter = BigInt.tryParse(_str(j, 'counter'));
    if (counter == null || counter.isNegative) _bad('counter');
    final key = _str(j, 'key');
    if (key.isEmpty) _bad('key');
    return VaultIdentity(
      id: _str(j, 'id'),
      owner: _str(j, 'owner'),
      cloudId: _str(j, 'cloudId'),
      cloudVersion: _str(j, 'cloudVersion'),
      uid: _str(j, 'uid'),
      counter: counter,
      desktopString: key,
      name: _optStr(j, 'name'),
      nickname: _optStr(j, 'nickname'),
      phoneticNickname: _optStr(j, 'phonetic'),
      cloudDefault: _optBool(j, 'cloudDefault'),
    );
  }

  /// Same cloud identity material (UID, counter and key).
  bool sameKey(VaultIdentity o) =>
      uid == o.uid && counter == o.counter && desktopString == o.desktopString;
}

class VaultBookmark {
  final String id;
  final String owner;
  final String cloudId;
  final String cloudVersion;
  final String? name;

  /// Host as stored in the cloud, without the separate [port].
  final String address;
  final int? port;
  final String? nickname;

  /// Opaque cloud identity reference: `null` is absent, `''` is present but
  /// empty. No matching rule is established, so it is never resolved.
  final String? identityRef;
  final String? serverPassword;
  final String? defaultChannel;
  final String? defaultChannelPassword;
  final String? serverUid;
  final bool? autoconnect;
  final bool? connectMuted;

  const VaultBookmark({
    required this.id,
    required this.owner,
    required this.cloudId,
    required this.cloudVersion,
    required this.address,
    this.name,
    this.port,
    this.nickname,
    this.identityRef,
    this.serverPassword,
    this.defaultChannel,
    this.defaultChannelPassword,
    this.serverUid,
    this.autoconnect,
    this.connectMuted,
  });

  /// `host:port` for the connection layer; an address that already carries a
  /// port (or an IPv6 literal) is used as given.
  String get connectAddress {
    final p = port;
    if (p == null || address.contains(':')) return address;
    return '$address:$p';
  }

  String get title {
    for (final c in [name, address]) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return address;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'cloudId': cloudId,
    'cloudVersion': cloudVersion,
    'name': name,
    'address': address,
    'port': port,
    'nickname': nickname,
    'identityRef': identityRef,
    'serverPassword': serverPassword,
    'defaultChannel': defaultChannel,
    'defaultChannelPassword': defaultChannelPassword,
    'serverUid': serverUid,
    'autoconnect': autoconnect,
    'connectMuted': connectMuted,
  };

  factory VaultBookmark.fromJson(Map<String, dynamic> j) {
    final port = j['port'];
    if (port != null && (port is! int || port < 1 || port > 65535)) _bad('port');
    final address = _str(j, 'address');
    if (address.trim().isEmpty) _bad('address');
    return VaultBookmark(
      id: _str(j, 'id'),
      owner: _str(j, 'owner'),
      cloudId: _str(j, 'cloudId'),
      cloudVersion: _str(j, 'cloudVersion'),
      name: _optStr(j, 'name'),
      address: address,
      port: port as int?,
      nickname: _optStr(j, 'nickname'),
      identityRef: _optStr(j, 'identityRef'),
      serverPassword: _optStr(j, 'serverPassword'),
      defaultChannel: _optStr(j, 'defaultChannel'),
      defaultChannelPassword: _optStr(j, 'defaultChannelPassword'),
      serverUid: _optStr(j, 'serverUid'),
      autoconnect: _optBool(j, 'autoconnect'),
      connectMuted: _optBool(j, 'connectMuted'),
    );
  }

  /// Same cloud content, ignoring the local ID and ownership label.
  bool sameContent(VaultBookmark o) =>
      cloudVersion == o.cloudVersion &&
      name == o.name &&
      address == o.address &&
      port == o.port &&
      nickname == o.nickname &&
      identityRef == o.identityRef &&
      serverPassword == o.serverPassword &&
      defaultChannel == o.defaultChannel &&
      defaultChannelPassword == o.defaultChannelPassword &&
      serverUid == o.serverUid &&
      autoconnect == o.autoconnect &&
      connectMuted == o.connectMuted;
}

class VaultState {
  final List<VaultIdentity> identities;
  final List<VaultBookmark> bookmarks;

  /// Local identity choices: bookmark vault ID (or
  /// [AccountVault.localDefaultLink]) -> identity vault ID, or
  /// [AccountVault.legacyIdentityId] for the identity file of a Skip setup.
  /// Separate from the cloud reference, which stays untouched.
  final Map<String, String> links;

  const VaultState({
    this.identities = const [],
    this.bookmarks = const [],
    this.links = const {},
  });

  static const empty = VaultState();

  bool get hasData => identities.isNotEmpty || bookmarks.isNotEmpty;

  VaultIdentity? identity(String id) =>
      identities.where((i) => i.id == id).firstOrNull;

  VaultBookmark? bookmark(String id) =>
      bookmarks.where((b) => b.id == id).firstOrNull;

  VaultState copyWith({
    List<VaultIdentity>? identities,
    List<VaultBookmark>? bookmarks,
    Map<String, String>? links,
  }) => VaultState(
    identities: identities ?? this.identities,
    bookmarks: bookmarks ?? this.bookmarks,
    links: links ?? this.links,
  );

  String encode() => jsonEncode({
    'v': AccountVault.version,
    'identities': [for (final i in identities) i.toJson()],
    'bookmarks': [for (final b in bookmarks) b.toJson()],
    'links': links,
  });

  /// Strict: any malformed or inconsistent content throws instead of being
  /// repaired, so unreadable data is never mistaken for an empty vault.
  static VaultState decode(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['v'] != AccountVault.version) {
      _bad('version');
    }
    final identities = [
      for (final i in j['identities'] as List) VaultIdentity.fromJson(i as Map<String, dynamic>),
    ];
    final bookmarks = [
      for (final b in j['bookmarks'] as List) VaultBookmark.fromJson(b as Map<String, dynamic>),
    ];
    final links = <String, String>{};
    (j['links'] as Map<String, dynamic>).forEach((k, v) {
      if (v is! String) _bad('link');
      links[k] = v;
    });
    if (identities.map((i) => i.id).toSet().length != identities.length ||
        bookmarks.map((b) => b.id).toSet().length != bookmarks.length) {
      _bad('duplicate id');
    }
    return VaultState(identities: identities, bookmarks: bookmarks, links: links);
  }
}

class AccountVault {
  static const version = 1;
  static const storageKey = 'ts6_account_vault_v1';

  /// Link target meaning "the identity file of the local (Skip) setup".
  static const legacyIdentityId = 'legacy';

  /// Link key for connections that have no imported bookmark (manual address
  /// or legacy bookmark) while the app has no local identity file.
  static const localDefaultLink = 'local-default';

  final MyTsSecureBackend _backend;
  Future<void> _tail = Future.value();

  AccountVault([MyTsSecureBackend? backend])
    : _backend = backend ?? const FlutterMyTsSecureBackend();

  /// Serializes every read-modify-write, so concurrent imports or choices
  /// cannot interleave and lose each other's changes.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Throws if stored data exists but cannot be read: never an empty result.
  Future<VaultState> load() async {
    final raw = await _backend.read(storageKey);
    if (raw == null) return VaultState.empty;
    return VaultState.decode(raw);
  }

  Future<bool> hasData() async => (await load()).hasData;

  /// One write of the whole new state, read back to confirm what was stored.
  /// If the write fails or does not read back, the previous content is put
  /// back (best effort) so a failed import leaves the old vault in place.
  /// Callers hold [synchronized] while they read, plan and write.
  Future<void> write(VaultState next) async {
    final raw = next.encode();
    final previous = await _backend.read(storageKey);
    try {
      await _backend.write(storageKey, raw);
      if (await _backend.read(storageKey) != raw) {
        throw StateError('Vault write was not persisted');
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

  /// Records the user's own identity choice for [key] (an imported bookmark ID
  /// or [localDefaultLink]). Never touches the cloud reference.
  Future<void> setLink(String key, String identityId) => synchronized(() async {
    final state = await load();
    final knownKey =
        key == localDefaultLink || state.bookmark(key) != null;
    final knownIdentity =
        identityId == legacyIdentityId || state.identity(identityId) != null;
    if (!knownKey || !knownIdentity) throw StateError('Unknown link target');
    await write(state.copyWith(links: {...state.links, key: identityId}));
  });
}
