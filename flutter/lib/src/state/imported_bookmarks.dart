import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_vault.dart';
import '../data/server_bookmark.dart';
import '../myts/import_controller.dart';
import 'server_controller.dart';

/// A bookmark imported from the account, as the connection list shows it.
class ImportedBookmark {
  final ServerBookmark bookmark;

  /// Identity the user picked for it, if that choice still resolves.
  final String? identityLabel;
  final bool usesLocalIdentityFile;

  const ImportedBookmark(this.bookmark, {this.identityLabel, this.usesLocalIdentityFile = false});

  bool get identityChosen => identityLabel != null || usesLocalIdentityFile;
}

ServerBookmark toServerBookmark(VaultBookmark b) => ServerBookmark(
  name: b.title,
  address: b.connectAddress,
  nickname: (b.nickname ?? '').trim(),
  password: (b.serverPassword ?? '').isEmpty ? null : b.serverPassword,
  channel: (b.defaultChannel ?? '').isEmpty ? null : b.defaultChannel,
  vaultId: b.id,
);

/// Bookmarks stored by account imports, re-read whenever an import changes.
/// A read failure surfaces as an error state, never as an empty list.
final importedBookmarksProvider = FutureProvider<List<ImportedBookmark>>((ref) async {
  ref.watch(myTsImportProvider.select((s) => s.phase));
  ref.watch(identityLinkRevision);
  final state = await ref.read(accountVaultProvider).load();
  return [
    for (final b in state.bookmarks)
      ImportedBookmark(
        toServerBookmark(b),
        identityLabel: switch (state.links[b.id]) {
          final id? => state.identity(id)?.label,
          null => null,
        },
        usesLocalIdentityFile: state.links[b.id] == AccountVault.legacyIdentityId,
      ),
  ];
});

/// Bumped after a local identity choice so the list refreshes.
final identityLinkRevision = NotifierProvider<_Revision, int>(_Revision.new);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
