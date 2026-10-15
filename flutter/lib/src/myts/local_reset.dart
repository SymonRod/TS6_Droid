import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_controller.dart';
import '../data/onboarding_store.dart';
import '../state/imported_bookmarks.dart';
import '../state/server_controller.dart';
import '../state/onboarding_controller.dart';
import 'controller.dart';

/// "Start from scratch" before a new myTeamSpeak sign-in: removes everything
/// this phone keeps about the account and its imports. The local TeamSpeak
/// identity file and the general settings are not touched.
///
/// What goes: the session and saved password, imported identities and bookmark
/// passwords (account vault), the chat's device keys, conversations cache and
/// encryption consent, the contact cache, the saved server bookmarks and the
/// "setup done" marker.
class LocalReset {
  final Ref _ref;
  LocalReset(this._ref);

  /// Whether there is anything the reset would delete.
  Future<bool> hasData() async {
    if (await _ref.read(myTsSessionStoreProvider).hasStoredData()) return true;
    return _ref.read(bookmarkStoreProvider).hasAnyBookmarks();
  }

  Future<void> wipe() async {
    // Close the chat first, so a running client cannot write its snapshot back.
    _ref.read(chatProvider.notifier).lock();
    await _ref.read(myTsSessionStoreProvider).wipeAll();
    await _ref.read(bookmarkStoreProvider).clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(OnboardingStore.completeKey);
    _ref.invalidate(hasSavedPasswordProvider);
    _ref.invalidate(rememberPasswordProvider);
    _ref.invalidate(importedBookmarksProvider);
    _ref.invalidate(bookmarksProvider);
    _ref.invalidate(identityLinkRevision);
    // refresh() keeps the old state until the re-read ends, so the router
    // never sees a loading state and bounces the login screen to /setup.
    await _ref.read(onboardingProvider.notifier).refresh();
  }
}

final localResetProvider = Provider<LocalReset>(LocalReset.new);
