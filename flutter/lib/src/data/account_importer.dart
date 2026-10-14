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

  AccountImporter({
    required this.vault,
    required this.identities,
    required this.onboarding,
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
        if (plan.next.hasData) {
          try {
            await onboarding.markComplete();
          } catch (_) {
            // The data is stored and isComplete() recognizes it on restart.
          }
        }
        return plan.report;
      });
}
