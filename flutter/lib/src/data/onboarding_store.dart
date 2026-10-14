import 'package:shared_preferences/shared_preferences.dart';

import 'account_vault.dart';
import 'stores.dart';

/// Local setup only. Authentication does not complete setup: the account
/// path completes it only after a validated import was persisted.
class OnboardingStore {
  static const completeKey = 'initial_setup_complete';

  final IdentityStore identities;
  final BookmarkStore bookmarks;

  /// Imported account data. Null only for callers that predate the import.
  final AccountVault? vault;

  OnboardingStore({
    required this.identities,
    required this.bookmarks,
    this.vault,
  });

  /// True when setup was completed or any local data exists. Unreadable data
  /// throws: it is never evidence of an empty app.
  Future<bool> isComplete() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(completeKey) == true) return true;
    // Check every store even if one has data: unreadable data must not
    // accidentally route through fresh setup or be overwritten.
    final hasIdentity = await identities.hasIdentity();
    final hasBookmarks = await bookmarks.hasSavedBookmarks();
    final hasImported = await vault?.hasData() ?? false;
    return hasIdentity || hasBookmarks || hasImported;
  }

  /// Records that setup is done. Called only after an import was persisted;
  /// if this write fails the imported data is still recognized as setup by
  /// [isComplete] on the next start.
  Future<void> markComplete() async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setBool(completeKey, true)) {
      throw StateError('Could not persist initial setup');
    }
  }

  Future<void> skip() async {
    // Recheck before creating anything; a storage failure or concurrent change
    // must not silently replace existing local data.
    await isComplete();
    await identities.getOrCreate();
    await markComplete();
  }
}
