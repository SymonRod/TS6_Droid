import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_store.dart';
import 'server_controller.dart';

class OnboardingState {
  final bool complete;
  final bool busy;
  final bool failed;

  const OnboardingState({
    this.complete = false,
    this.busy = false,
    this.failed = false,
  });
}

final onboardingStoreProvider = Provider(
  (ref) => OnboardingStore(
    identities: ref.read(identityStoreProvider),
    bookmarks: ref.read(bookmarkStoreProvider),
    vault: ref.read(accountVaultProvider),
  ),
);

class OnboardingController extends AsyncNotifier<OnboardingState> {
  @override
  Future<OnboardingState> build() async => OnboardingState(
    complete: await ref.read(onboardingStoreProvider).isComplete(),
  );

  /// Re-reads the stores after an import changed them, so the router leaves
  /// first setup only when data was really stored. A read failure keeps the
  /// previous state instead of pretending the app is empty or complete.
  Future<void> refresh() async {
    try {
      final complete = await ref.read(onboardingStoreProvider).isComplete();
      if (ref.mounted) state = AsyncData(OnboardingState(complete: complete));
    } catch (_) {
      if (ref.mounted) state = AsyncData(const OnboardingState(failed: true));
    }
  }

  Future<void> skip() async {
    final current = state.asData?.value;
    if (current == null || current.complete || current.busy) return;
    state = const AsyncData(OnboardingState(busy: true));
    try {
      await ref.read(onboardingStoreProvider).skip();
      if (ref.mounted) state = const AsyncData(OnboardingState(complete: true));
    } catch (_) {
      // Never expose underlying storage/native errors (possibly containing
      // identity data), and never mark a failed choice complete.
      if (ref.mounted) state = const AsyncData(OnboardingState(failed: true));
    }
  }
}

final onboardingProvider =
    AsyncNotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
