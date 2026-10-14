import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_vault.dart';
import '../data/server_bookmark.dart';
import '../data/stores.dart';
import '../rust/api.dart';
import 'server_controller.dart';

/// One identity the user can pick for a connection.
class IdentityOption {
  /// Vault identity ID, or [AccountVault.legacyIdentityId].
  final String id;
  final String label;
  final String uid;

  const IdentityOption({required this.id, required this.label, required this.uid});
}

/// Result of resolving the identity for a connection.
class ResolvedIdentity {
  final TsIdentity identity;

  /// Nickname stored with an imported identity, used only when the bookmark
  /// has none.
  final String? nicknameHint;

  const ResolvedIdentity(this.identity, this.nicknameHint);
}

/// Picks the identity for a connection WITHOUT ever creating or guessing one.
///
/// The bookmark's cloud identity reference is not a proven matching key, so
/// it is never used to select anything. An imported bookmark connects with the
/// identity the user chose for it (a local link, kept apart from the cloud
/// data) and asks once if there is none. The app's own bookmarks and manual
/// addresses keep using the local identity file when it exists.
class IdentityResolver {
  /// Returned by the chooser to request a new local identity. Only an explicit
  /// user action can produce it.
  static const createLocal = 'create-local';

  final AccountVault vault;
  final IdentityStore legacy;

  IdentityResolver({required this.vault, required this.legacy});

  Future<List<IdentityOption>> options() async {
    final state = await vault.load();
    final local = await legacy.loadExisting();
    return [
      if (local != null)
        IdentityOption(
          id: AccountVault.legacyIdentityId,
          label: '',
          uid: local.uniqueId(),
        ),
      for (final i in state.identities)
        IdentityOption(id: i.id, label: i.label, uid: i.uid),
    ];
  }

  Future<ResolvedIdentity> _open(String id, VaultState state) async {
    if (id == AccountVault.legacyIdentityId) {
      final local = await legacy.loadExisting();
      if (local == null) throw StateError('Local identity is gone');
      return ResolvedIdentity(local, null);
    }
    final stored = state.identity(id);
    if (stored == null) throw StateError('Unknown identity');
    final identity = await TsIdentity.fromDesktopString(data: stored.desktopString);
    if (identity.uniqueId() != stored.uid) throw StateError('Identity changed');
    return ResolvedIdentity(identity, stored.nickname);
  }

  /// The identity to connect [bookmark] with. [ask] shows the chooser and
  /// returns an option ID, [createLocal] or null (cancelled); it is not called
  /// when [interactive] is false, so background reconnects never prompt.
  /// Returns null when no identity was settled: nothing is connected.
  Future<ResolvedIdentity?> resolve(
    ServerBookmark bookmark, {
    required Future<String?> Function(List<IdentityOption> options, {required bool canCreate}) ask,
    bool interactive = true,
  }) async {
    final state = await vault.load();
    final local = await legacy.loadExisting();
    final String linkKey;
    if (bookmark.vaultId != null) {
      linkKey = bookmark.vaultId!;
    } else if (local != null) {
      return ResolvedIdentity(local, null);
    } else {
      linkKey = AccountVault.localDefaultLink;
    }
    final opts = await options();
    final linked = state.links[linkKey];
    if (linked != null && opts.any((o) => o.id == linked)) {
      return _open(linked, state);
    }
    if (!interactive) return null;
    // The vault lock is not held while the user decides.
    final choice = await ask(opts, canCreate: local == null);
    if (choice == null) return null;
    var chosen = choice;
    if (choice == createLocal) {
      if (local != null) return null;
      await legacy.create();
      chosen = AccountVault.legacyIdentityId;
    } else if (!opts.any((o) => o.id == choice)) {
      return null;
    }
    return vault.synchronized(() async {
      final fresh = await vault.load();
      await vault.write(fresh.copyWith(links: {...fresh.links, linkKey: chosen}));
      return _open(chosen, fresh);
    });
  }

  /// Changes the stored choice for an imported bookmark.
  Future<void> choose(String bookmarkVaultId, String identityId) =>
      vault.setLink(bookmarkVaultId, identityId);
}

final identityResolverProvider = Provider(
  (ref) => IdentityResolver(
    vault: ref.read(accountVaultProvider),
    legacy: ref.read(identityStoreProvider),
  ),
);
