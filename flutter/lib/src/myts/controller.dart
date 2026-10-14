import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'session_store.dart';

/// myTeamSpeak sign-in state (phase 6, milestone M1: password login only).
/// Sync, bookmark import, renewal and account-key unwrap are separate work.

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
final myTsSessionStoreProvider = Provider<MyTsSessionStore>((_) => MyTsSessionStore());

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
  /// When [otp] is null and the server requires it, state moves to
  /// [MyTsStatus.otpNeeded] and the caller retries with the code.
  Future<void> login(String rawEmail, String password, {String? otp}) async {
    final email = rawEmail.trim();
    if (email.isEmpty || password.isEmpty) {
      state = MyTsState(
        status: state.status == MyTsStatus.signedIn ? MyTsStatus.signedIn : MyTsStatus.signedOut,
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
    final outcome = await ref.read(myTsApiProvider).login(
          email: email,
          password: password,
          otp: otp,
        );
    if (!ref.mounted) return;
    final ok = outcome.success;
    if (ok != null) {
      await ref.read(myTsSessionStoreProvider).save(
            session: ok.session,
            uuid: ok.uuid,
            username: ok.username,
            email: email,
          );
      if (!ref.mounted) return;
      state = MyTsState(status: MyTsStatus.signedIn, username: ok.username, email: email);
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
    state = MyTsState(status: state.status, username: state.username, email: state.email);
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
    _lastAttemptStart = null;
    if (ref.mounted) state = const MyTsState();
  }
}

final myTsProvider = NotifierProvider<MyTsController, MyTsState>(MyTsController.new);
