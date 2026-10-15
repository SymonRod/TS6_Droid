import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_importer.dart';
import '../data/account_vault.dart' show vaultOwner;
import '../data/import_plan.dart';
import '../rust/myts.dart' as rs;
import '../state/onboarding_controller.dart';
import '../state/server_controller.dart';
import 'api.dart';
import 'controller.dart'
    show myTsSessionStoreProvider, myTsApiProvider, rememberPasswordProvider;

/// Account import: sign-in credentials -> unwrap -> read-only download ->
/// validation -> local secure storage. Read-only towards the cloud.

enum ImportPhase {
  /// Nothing running.
  idle,

  /// Unwrapping, downloading, validating or writing.
  working,

  /// Existing local data: the download is ready and waits for an explicit
  /// choice. Nothing has been stored.
  awaitingConfirmation,

  /// Imported (or already up to date); see [ImportState.report].
  done,

  /// The cloud held nothing importable. Nothing was stored and setup is not
  /// marked complete.
  nothingToImport,

  /// Nothing was changed; see [ImportState.failure].
  failed,
}

enum ImportFailure {
  /// No stored session (signed out).
  noSession,

  /// The wrapped account key is missing or does not unwrap.
  unlock,

  /// TLS, DNS, connection or timeout failure.
  network,

  /// The service answered with an HTTP or service error.
  service,

  /// The session is no longer accepted: sign in again.
  sessionExpired,

  /// Oversized, malformed or inconsistent reply.
  invalidData,

  /// An item failed decryption or integrity.
  integrity,

  /// Local data could not be read or written; nothing was replaced.
  storage,
}

class ImportState {
  final ImportPhase phase;
  final ImportFailure? failure;

  /// Final report, or the preview computed for [ImportPhase.awaitingConfirmation].
  final ImportReport? report;

  const ImportState({this.phase = ImportPhase.idle, this.failure, this.report});

  bool get busy => phase == ImportPhase.working;
}

final accountImporterProvider = Provider<AccountImporter>(
  (ref) => AccountImporter(
    vault: ref.read(accountVaultProvider),
    identities: ref.read(identityStoreProvider),
    onboarding: ref.read(onboardingStoreProvider),
    cursors: ref.read(syncCursorStoreProvider),
  ),
);

class MyTsImportController extends Notifier<ImportState> {
  // Held only while waiting for confirmation, then dropped. Contains secrets.
  rs.MyTsImportBatch? _pending;
  String _pendingOwner = '';

  @override
  ImportState build() {
    ref.onDispose(_forget);
    return const ImportState();
  }

  void _forget() {
    _pending = null;
    _pendingOwner = '';
  }

  /// Right after a successful sign-in, while the password is still at hand.
  /// On an empty app the supported data is imported automatically; otherwise
  /// the download waits for [confirm].
  Future<void> startAfterLogin({
    required String email,
    required String password,
    required MyTsLoginSuccess login,
  }) => _run(
    email: email,
    password: password,
    session: login.session,
    wrappedKey: login.wrappedKey,
  );

  /// Explicit import or retry for a stored session. The password is needed
  /// again to unwrap the account key: the caller passes the one saved on this
  /// device (if the user allows that) or asks for it.
  Future<void> startFromStoredSession(
    String password, {
    bool fromSaved = false,
  }) async {
    if (state.busy) return;
    final stored = await ref.read(myTsSessionStoreProvider).load();
    if (stored == null) {
      state = const ImportState(
        phase: ImportPhase.failed,
        failure: ImportFailure.noSession,
      );
      return;
    }
    await _run(
      email: stored.email,
      password: password,
      session: stored.session,
      wrappedKey: stored.wrappedKey,
    );
    if (!ref.mounted) return;
    // A saved password that no longer unwraps the key is dropped, so the
    // field comes back; a typed one that worked is kept unless opted out.
    final remember = ref.read(rememberPasswordProvider.notifier);
    if (fromSaved) {
      if (state.failure == ImportFailure.unlock) await remember.forget();
    } else if (state.phase != ImportPhase.failed) {
      await remember.remember(password);
    }
  }

  /// Same as [startFromStoredSession], with the password kept on this device.
  Future<void> startFromSavedPassword() async {
    final saved = await ref.read(myTsSessionStoreProvider).loadPassword();
    if (saved == null)
      return ref.read(rememberPasswordProvider.notifier).forget();
    await startFromStoredSession(saved, fromSaved: true);
  }

  Future<void> _run({
    required String email,
    required String password,
    required String session,
    required List<int> wrappedKey,
  }) async {
    if (state.busy) return;
    _forget();
    state = const ImportState(phase: ImportPhase.working);
    final api = ref.read(myTsApiProvider);
    final owner = vaultOwner(email);
    rs.MyTsAccountKey? key;
    try {
      key = await api.unlockAccountKey(
        email: email,
        password: password,
        wrappedKey: wrappedKey,
      );
      if (key == null) return _fail(ImportFailure.unlock);
      final pulled = await api.pull(session: session, key: key);
      final batch = pulled.batch;
      if (batch == null) return _fail(_failureOf(pulled.failure));
      await _decide(batch, owner);
    } catch (_) {
      // Native or storage errors may mention material: never surface them.
      _fail(ImportFailure.storage);
    } finally {
      key?.dispose();
    }
  }

  Future<void> _decide(rs.MyTsImportBatch batch, String owner) async {
    final setupDone = ref.read(onboardingProvider).asData?.value.complete;
    final importer = ref.read(accountImporterProvider);
    // Anything but a known-empty app takes the explicit path, so an
    // unreadable state can never import silently.
    if (setupDone == false) {
      try {
        final report = await importer.commit(
          batch,
          owner,
          onlyIfEmptyApp: true,
        );
        return await _finish(report);
      } on ImportBlocked {
        // Became non-empty meanwhile: fall through to explicit confirmation.
      }
    }
    final plan = await importer.preview(batch, owner);
    if (!plan.report.hasChanges) {
      return _finish(plan.report);
    }
    _pending = batch;
    _pendingOwner = owner;
    if (!ref.mounted) return;
    state = ImportState(
      phase: ImportPhase.awaitingConfirmation,
      report: plan.report,
    );
  }

  /// Applies the downloaded batch after the user confirmed.
  Future<void> confirm() async {
    final batch = _pending;
    if (batch == null || state.phase != ImportPhase.awaitingConfirmation)
      return;
    state = ImportState(phase: ImportPhase.working, report: state.report);
    try {
      final report = await ref
          .read(accountImporterProvider)
          .commit(batch, _pendingOwner, onlyIfEmptyApp: false);
      _forget();
      await _finish(report);
    } catch (_) {
      // The vault is unchanged; the download is still available to retry.
      if (ref.mounted) {
        state = ImportState(
          phase: ImportPhase.awaitingConfirmation,
          failure: ImportFailure.storage,
          report: state.report,
        );
      }
    }
  }

  /// Drops a pending download without storing anything.
  void cancel() {
    if (state.busy) return;
    _forget();
    state = const ImportState();
  }

  Future<void> _finish(ImportReport report) async {
    // Tell the router that setup state changed (it re-reads the stores).
    await ref.read(onboardingProvider.notifier).refresh();
    if (!ref.mounted) return;
    state = ImportState(
      phase: report.cloudEmpty ? ImportPhase.nothingToImport : ImportPhase.done,
      report: report,
    );
  }

  void _fail(ImportFailure failure) {
    if (ref.mounted)
      state = ImportState(phase: ImportPhase.failed, failure: failure);
  }

  static ImportFailure _failureOf(MyTsPullKind? kind) => switch (kind) {
    MyTsPullKind.invalidInput => ImportFailure.noSession,
    MyTsPullKind.network => ImportFailure.network,
    MyTsPullKind.http || MyTsPullKind.server => ImportFailure.service,
    MyTsPullKind.sessionExpired => ImportFailure.sessionExpired,
    MyTsPullKind.tooLarge ||
    MyTsPullKind.invalid ||
    null => ImportFailure.invalidData,
    MyTsPullKind.integrity => ImportFailure.integrity,
  };

  /// Sign-out ends any download in flight or waiting.
  void reset() {
    _forget();
    state = const ImportState();
  }
}

final myTsImportProvider = NotifierProvider<MyTsImportController, ImportState>(
  MyTsImportController.new,
);
