import '../rust/myts.dart' as rs;
import 'account_vault.dart';

/// What an import did or would do. Counts only: no identity, UID, address or
/// password is ever put in a report, so it is safe to show and to log.
class ImportReport {
  final int addedIdentities;
  final int addedBookmarks;

  /// Same cloud item already stored with identical content.
  final int unchangedIdentities;
  final int unchangedBookmarks;

  /// Same cloud ID but different content. The stored copy is kept: an import
  /// never replaces local data silently.
  final int conflictIdentities;
  final int conflictBookmarks;

  /// New cloud identity whose UID is already present locally (another cloud
  /// item, another account, or the local identity file): not added twice.
  final int duplicateIdentities;

  /// Items the cloud sent that are not usable and were skipped, not repaired.
  final int invalidIdentities;
  final int invalidBookmarks;

  /// Items of classes this app does not import yet.
  final int unsupportedItems;

  /// True when the cloud held nothing importable (no valid identity or
  /// bookmark at all).
  final bool cloudEmpty;

  const ImportReport({
    this.addedIdentities = 0,
    this.addedBookmarks = 0,
    this.unchangedIdentities = 0,
    this.unchangedBookmarks = 0,
    this.conflictIdentities = 0,
    this.conflictBookmarks = 0,
    this.duplicateIdentities = 0,
    this.invalidIdentities = 0,
    this.invalidBookmarks = 0,
    this.unsupportedItems = 0,
    this.cloudEmpty = false,
  });

  bool get hasChanges => addedIdentities > 0 || addedBookmarks > 0;

  /// Items not added because they are invalid, duplicated or differ from the
  /// stored copy.
  int get skippedCount =>
      invalidIdentities +
      invalidBookmarks +
      conflictIdentities +
      conflictBookmarks +
      duplicateIdentities;

  bool get hasSkips => skippedCount > 0;
}

class ImportPlan {
  final VaultState next;
  final ImportReport report;

  const ImportPlan(this.next, this.report);
}

/// Pure merge of a validated cloud batch into the current vault. It never
/// removes or replaces a stored item, never invents an identity, and never
/// resolves a bookmark's cloud identity reference.
///
/// [localUids] are the UIDs of identities that exist outside the vault (the
/// identity file of a Skip setup), so the same key is not offered twice.
ImportPlan planImport({
  required VaultState current,
  required rs.MyTsImportBatch batch,
  required String owner,
  Set<String> localUids = const {},
}) {
  final identities = [...current.identities];
  final bookmarks = [...current.bookmarks];
  final uids = {...localUids, for (final i in identities) i.uid};

  var addedI = 0, sameI = 0, conflictI = 0, dupI = 0;
  for (final c in batch.identities) {
    final incoming = VaultIdentity(
      id: vaultItemId('identity', owner, c.cloudId),
      owner: owner,
      cloudId: c.cloudId,
      cloudVersion: c.itemVersion,
      uid: c.uid,
      counter: c.counter,
      desktopString: c.desktopString,
      name: c.idName,
      nickname: c.nickname,
      phoneticNickname: c.phoneticNickname,
      cloudDefault: c.isDefault,
    );
    final existing = identities.where((i) => i.id == incoming.id).firstOrNull;
    if (existing != null) {
      existing.sameKey(incoming) ? sameI++ : conflictI++;
    } else if (uids.contains(incoming.uid)) {
      dupI++;
    } else {
      identities.add(incoming);
      uids.add(incoming.uid);
      addedI++;
    }
  }

  var addedB = 0, sameB = 0, conflictB = 0;
  for (final c in batch.bookmarks) {
    final incoming = VaultBookmark(
      id: vaultItemId('bookmark', owner, c.cloudId),
      owner: owner,
      cloudId: c.cloudId,
      cloudVersion: c.itemVersion,
      name: c.name,
      address: c.address,
      port: c.port,
      nickname: c.nickname,
      identityRef: c.identity,
      serverPassword: c.serverPassword,
      defaultChannel: c.defaultChannel,
      defaultChannelPassword: c.defaultChannelPassword,
      serverUid: c.serverUid,
      autoconnect: c.autoconnect,
      connectMuted: c.connectMuted,
    );
    final existing = bookmarks.where((b) => b.id == incoming.id).firstOrNull;
    if (existing != null) {
      existing.sameContent(incoming) ? sameB++ : conflictB++;
    } else {
      bookmarks.add(incoming);
      addedB++;
    }
  }

  final report = ImportReport(
    addedIdentities: addedI,
    addedBookmarks: addedB,
    unchangedIdentities: sameI,
    unchangedBookmarks: sameB,
    conflictIdentities: conflictI,
    conflictBookmarks: conflictB,
    duplicateIdentities: dupI,
    invalidIdentities: batch.invalidIdentityIds.length,
    invalidBookmarks: batch.invalidBookmarkIds.length,
    unsupportedItems: batch.unsupportedItems,
    cloudEmpty: batch.identities.isEmpty && batch.bookmarks.isEmpty,
  );
  return ImportPlan(
    current.copyWith(identities: identities, bookmarks: bookmarks),
    report,
  );
}
