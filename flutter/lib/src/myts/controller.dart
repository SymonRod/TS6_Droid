import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'import_controller.dart';
import 'local_reset.dart';
import 'session_store.dart';

/// myTeamSpeak sign-in state. A successful sign-in hands the still-available
/// password to [MyTsImportController] for the read-only account import;
/// ongoing sync and token renewal are separate work.

enum MyTsStatus {
  /// No stored session.
  signedOut,

  /// A login POST is in flight (exactly one attempt, never retried).
  signingIn,

  /// The server answered `ERROR_AUTH_REQUIRES_OTP` (208): the UI shows
  /// the OTP field instead of reporting a wrong password.
  otpNeeded,

  /// A stored session token is held (possibly restored from secure
  /// storage without network validation, so it also covers offline start).
  signedIn,
}

class MyTsState {
  final MyTsStatus status;
  final String username;
  final String email;
  final MyTsFailure? failure;
  final int? httpStatus;
  final int? appError;

  const MyTsState({
    this.status = MyTsStatus.signedOut,
    this.username = '',
    this.email = '',
    this.failure,
    this.httpStatus,
    this.appError,
  });

  bool get busy => status == MyTsStatus.signingIn;
}

final myTsApiProvider = Provider<MyTsApi>((_) => MyTsApi());
final myTsSessionStoreProvider = Provider<MyTsSessionStore>(
  (_) => MyTsSessionStore(),
);

/// Whether a saved account password is available (remembering on and a
/// password stored). Invalidate after anything that saves or forgets it.
final hasSavedPasswordProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      await ref.read(myTsSessionStoreProvider).loadPassword() != null,
);

/// The "remember password on this device" option (on by default). Switching
/// it off wipes the saved password immediately.
class RememberPasswordController extends Notifier<bool> {
  @override
  bool build() {
    ref.read(myTsSessionStoreProvider).rememberPassword().then((v) {
      if (ref.mounted) state = v;
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(myTsSessionStoreProvider).setRememberPassword(value);
    ref.invalidate(hasSavedPasswordProvider);
  }

  /// Drops the saved password only (a wrong or outdated one); the option stays.
  Future<void> forget() async {
    await ref.read(myTsSessionStoreProvider).clearPassword();
    ref.invalidate(hasSavedPasswordProvider);
  }

  /// Saves [password] after it was just proven correct, if the option is on.
  Future<void> remember(String password) async {
    await ref.read(myTsSessionStoreProvider).savePassword(password);
    ref.invalidate(hasSavedPasswordProvider);
  }
}

final rememberPasswordProvider =
    NotifierProvider<RememberPasswordController, bool>(
      RememberPasswordController.new,
    );

class MyTsController extends Notifier<MyTsState> {
  DateTime? _lastAttemptStart;

  @override
  MyTsState build() {
    // Offline-first restore: a stored session returns without validation.
    // Expiry is surfaced by the next server call, never by wiping here.
    ref.read(myTsSessionStoreProvider).load().then((s) {
      if (ref.mounted && s != null) {
        state = MyTsState(
          status: MyTsStatus.signedIn,
          username: s.username,
          email: s.email,
        );
      }
    });
    return const MyTsState();
  }

  /// One login attempt. [rawEmail] is trimmed once here and the same
  /// trimmed value feeds both the KDF and the request (protocol doc 2.5).
  /// The password is always used byte-for-byte, never trimmed.
  ///
  /// With [resetLocalData] (the user confirmed the warning) every local
  /// account/chat/bookmark datum is deleted once the credentials are proven
  /// right, before the new session is stored; a failed attempt deletes nothing.
  /// When [otp] is null and the server requires it, state moves to
  /// [MyTsStatus.otpNeeded] and the caller retries with the code.
  Future<void> login(
    String rawEmail,
    String password, {
    String? otp,
    bool resetLocalData = false,
  }) async {
    final email = rawEmail.trim();
    if (email.isEmpty || password.isEmpty) {
      state = MyTsState(
        status: state.status == MyTsStatus.signedIn
            ? MyTsStatus.signedIn
            : MyTsStatus.signedOut,
        username: state.username,
        email: state.email,
        failure: MyTsFailure.invalidInput,
      );
      return;
    }
    final now = DateTime.now();
    if (_lastAttemptStart != null &&
        now.difference(_lastAttemptStart!) < MyTsApi.minRetryGap) {
      state = MyTsState(
        status: state.status,
        username: state.username,
        email: state.email,
        failure: MyTsFailure.paced,
      );
      return;
    }
    _lastAttemptStart = now;
    final wasSignedIn = state.status == MyTsStatus.signedIn;
    state = MyTsState(
      status: MyTsStatus.signingIn,
      username: state.username,
      email: email,
    );
    final outcome = await ref
        .read(myTsApiProvider)
        .login(email: email, password: password, otp: otp);
    if (!ref.mounted) return;
    final ok = outcome.success;
    if (ok != null) {
      if (resetLocalData) {
        final old = await ref.read(myTsSessionStoreProvider).load();
        if (old != null && old.session != ok.session) {
          try {
            await ref.read(myTsApiProvider).deleteSession(old.session);
          } catch (_) {
            // Best effort, like on sign-out.
          }
        }
        ref.read(myTsImportProvider.notifier).reset();
        await ref.read(localResetProvider).wipe();
        if (!ref.mounted) return;
      }
      await ref
          .read(myTsSessionStoreProvider)
          .save(
            session: ok.session,
            uuid: ok.uuid,
            username: ok.username,
            email: email,
            wrappedKey: ok.wrappedKey,
          );
      // Kept in secure storage only if the user did not opt out, so the chat
      // and later imports can unlock without asking again.
      await ref.read(rememberPasswordProvider.notifier).remember(password);
      if (!ref.mounted) return;
      state = MyTsState(
        status: MyTsStatus.signedIn,
        username: ok.username,
        email: email,
      );
      await ref
          .read(myTsImportProvider.notifier)
          .startAfterLogin(email: email, password: password, login: ok);
      return;
    }
    state = MyTsState(
      status: outcome.failure == MyTsFailure.otpRequired
          ? MyTsStatus.otpNeeded
          : (wasSignedIn ? MyTsStatus.signedIn : MyTsStatus.signedOut),
      username: state.username,
      email: email,
      failure: outcome.failure,
      httpStatus: outcome.httpStatus,
      appError: outcome.appError,
    );
  }

  void clearError() {
    if (state.failure == null) return;
    state = MyTsState(
      status: state.status,
      username: state.username,
      email: state.email,
    );
  }

  /// Best-effort server-side session deletion, then the local wipe always
  /// runs: logout ends signed out, offline or not. Only the session this
  /// app created is ever deleted.
  Future<void> logout() async {
    final stored = await ref.read(myTsSessionStoreProvider).load();
    if (stored != null) {
      try {
        await ref.read(myTsApiProvider).deleteSession(stored.session);
      } catch (_) {
        // Best effort: the local wipe below still runs.
      }
    }
    await ref.read(myTsSessionStoreProvider).clear();
    ref.invalidate(hasSavedPasswordProvider);
    // Pending downloaded data is dropped; already imported data stays.
    ref.read(myTsImportProvider.notifier).reset();
    _lastAttemptStart = null;
    if (ref.mounted) state = const MyTsState();
  }
}

final myTsProvider = NotifierProvider<MyTsController, MyTsState>(
  MyTsController.new,
);
