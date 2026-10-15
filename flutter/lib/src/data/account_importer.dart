import '../myts/sync_cursors.dart';
import '../rust/myts.dart' as rs;
import 'account_vault.dart';
import 'import_plan.dart';
import 'onboarding_store.dart';
import 'stores.dart';

/// The app stopped being empty between the download and the commit (for
/// example the user skipped setup meanwhile). The automatic path must not
/// proceed; the explicit, confirmed path applies.
class ImportBlocked implements Exception {
  const ImportBlocked();
}

/// Persists a validated cloud batch. Read-only towards the cloud; the only
/// thing it writes is the local vault, in a single atomic operation, and the
/// setup marker afterwards.
class AccountImporter {
  final AccountVault vault;
  final IdentityStore identities;
  final OnboardingStore onboarding;

  /// Sync cursors recorded from every committed batch, so a later push can
  /// send the last-known versions back. Local bookkeeping only: no network,
  /// no key use, never gated by the push feature flag.
  final SyncCursorStore cursors;

  AccountImporter({
    required this.vault,
    required this.identities,
    required this.onboarding,
    required this.cursors,
  });

  Future<Set<String>> _localUids() async {
    final local = await identities.loadExisting();
    return {if (local != null) local.uniqueId()};
  }

  /// What importing [batch] would do right now. Writes nothing. Unreadable
  /// local data throws.
  Future<ImportPlan> preview(rs.MyTsImportBatch batch, String owner) =>
      vault.synchronized(() async => planImport(
            current: await vault.load(),
            batch: batch,
            owner: owner,
            localUids: await _localUids(),
          ));

  /// Merges [batch] into the vault. Existing items are never replaced; the
  /// same batch applied again changes nothing. When [onlyIfEmptyApp] is set
  /// (automatic first-setup import) the app is re-checked inside the same
  /// critical section and [ImportBlocked] is thrown if it holds data.
  ///
  /// Setup is marked complete only once imported data is stored, so a failed
  /// import, an unusable cloud or an empty cloud never completes it.
  Future<ImportReport> commit(
    rs.MyTsImportBatch batch,
    String owner, {
    required bool onlyIfEmptyApp,
  }) => vault.synchronized(() async {
        if (onlyIfEmptyApp && await onboarding.isComplete()) {
          throw const ImportBlocked();
        }
        final plan = planImport(
          current: await vault.load(),
          batch: batch,
          owner: owner,
          localUids: await _localUids(),
        );
        if (plan.report.hasChanges) await vault.write(plan.next);
        await _recordCursors(batch, owner);
        if (plan.next.hasData) {
          try {
            await onboarding.markComplete();
          } catch (_) {
            // The data is stored and isComplete() recognizes it on restart.
          }
        }
        return plan.report;
      });

  /// Records the batch cursors for a later push. Runs on every commit —
  /// including a no-change re-import, which still refreshes versions — but
  /// never wipes stored cursors from a cursorless (synthetic) batch.
  Future<void> _recordCursors(rs.MyTsImportBatch batch, String owner) =>
      cursors.synchronized(() async {
        if (batch.globalVersion.isEmpty && batch.classVersions.isEmpty) return;
        final items = <String, String>{
          for (final i in batch.identities) i.cloudId: i.itemVersion,
          for (final b in batch.bookmarks) b.cloudId: b.itemVersion,
        };
        await cursors.save(
          owner,
          SyncCursors(
            globalVersion: batch.globalVersion,
            classVersions: {
              for (final c in batch.classVersions) c.classNumber: c.version,
            },
            itemVersions: items,
          ),
        );
      });
}
