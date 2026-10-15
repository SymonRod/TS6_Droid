import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../myts/api.dart';
import '../myts/controller.dart';
import '../myts/import_controller.dart';
import '../myts/local_reset.dart';

/// myTeamSpeak sign-in with an optional OTP step, followed by the read-only
/// import of the account's identities and bookmarks. Nothing is written to the
/// account.
class MyTsLoginScreen extends ConsumerStatefulWidget {
  final bool initialSetup;

  const MyTsLoginScreen({super.key, this.initialSetup = false});

  @override
  ConsumerState<MyTsLoginScreen> createState() => _MyTsLoginScreenState();
}

class _MyTsLoginScreenState extends ConsumerState<MyTsLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _importPassword = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _importPassword.dispose();
    super.dispose();
  }

  String _failureText(AppLocalizations l, MyTsState s) {
    switch (s.failure) {
      case MyTsFailure.invalidInput:
        return l.mytsEmailPasswordRequired;
      case MyTsFailure.paced:
        return l.mytsErrorPaced;
      case MyTsFailure.network:
        return l.mytsErrorNetwork;
      case MyTsFailure.http:
        return l.mytsErrorHttp('${s.httpStatus ?? '?'}');
      case MyTsFailure.malformed:
        return l.mytsErrorMalformed;
      case MyTsFailure.credentials:
        return l.mytsErrorCredentials;
      case MyTsFailure.offline:
        return l.mytsErrorOffline;
      case MyTsFailure.emailPending:
        return l.mytsErrorEmailPending;
      case MyTsFailure.otpRequired:
        return l.mytsErrorOtpRequired;
      case MyTsFailure.otpInvalid:
        return l.mytsErrorOtpInvalid;
      case MyTsFailure.other:
      case null:
        return s.failure == null ? '' : l.mytsErrorOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(myTsProvider);
    ref.listen(myTsProvider, (_, next) {
      if (next.status == MyTsStatus.signedIn) {
        _password.clear();
        _otp.clear();
        _showPassword = false;
      }
    });
    final l = AppLocalizations.of(context);
    final signedIn = s.status == MyTsStatus.signedIn;
    final otpNeeded = s.status == MyTsStatus.otpNeeded;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.mytsTitle),
        leading: widget.initialSetup
            ? IconButton(
                tooltip: l.setupBack,
                icon: const Icon(Icons.arrow_back),
                onPressed: s.busy ? null : () => context.go('/setup'),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initialSetup ? l.setupAccountHint : l.mytsExistingDataHint,
            ),
            if (widget.initialSetup && !signedIn) ...[
              const SizedBox(height: 12),
              Text(l.setupImportPending),
            ],
            const SizedBox(height: 16),
            if (signedIn) ...[
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(l.mytsLoggedInAs(s.username)),
                subtitle: s.email.isEmpty ? null : Text(s.email),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: ref.watch(rememberPasswordProvider),
                onChanged: (v) =>
                    ref.read(rememberPasswordProvider.notifier).set(v ?? true),
                title: Text(l.mytsRememberPassword),
                subtitle: Text(l.mytsRememberPasswordHint),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              _ImportCard(
                initialSetup: widget.initialSetup,
                password: _importPassword,
              ),
              const SizedBox(height: 12),
              if (!widget.initialSetup) ...[
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.forum_outlined),
                  label: Text(l.chatOpen),
                  onPressed: () => context.push('/chat'),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.initialSetup)
                OutlinedButton(
                  onPressed: () => context.go('/setup'),
                  child: Text(l.setupBack),
                ),
              FilledButton(
                onPressed: () => ref.read(myTsProvider.notifier).logout(),
                child: Text(l.mytsLogout),
              ),
            ] else ...[
              TextField(
                controller: _email,
                decoration: InputDecoration(labelText: l.mytsEmail),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                enabled: !s.busy,
                onChanged: (_) => ref.read(myTsProvider.notifier).clearError(),
              ),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: l.mytsAccountPassword,
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? l.mytsHidePassword
                        : l.mytsShowPassword,
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                enabled: !s.busy,
                onSubmitted: (_) => _submit(),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: ref.watch(rememberPasswordProvider),
                onChanged: s.busy
                    ? null
                    : (v) => ref
                          .read(rememberPasswordProvider.notifier)
                          .set(v ?? true),
                title: Text(l.mytsRememberPassword),
                subtitle: Text(l.mytsRememberPasswordHint),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (otpNeeded) ...[
                const SizedBox(height: 8),
                Text(l.mytsOtpHint),
                TextField(
                  controller: _otp,
                  decoration: InputDecoration(labelText: l.mytsOtp),
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  enabled: !s.busy,
                  onSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 12),
              if (s.failure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _failureText(l, s),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: s.busy ? null : _submit,
                child: s.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.mytsLogin),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Every sign-in starts from scratch: warns first when there is data to lose.
  Future<bool> _confirmReset() async {
    final l = AppLocalizations.of(context);
    final reset = ref.read(localResetProvider);
    bool hasData;
    try {
      hasData = await reset.hasData();
    } catch (_) {
      hasData = true; // Unreadable storage: warn rather than delete silently.
    }
    if (!hasData || !mounted) return mounted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(l.mytsResetTitle),
        content: SingleChildScrollView(child: Text(l.mytsResetBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.mytsResetConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    // The OTP retry belongs to the attempt that was already confirmed.
    final firstAttempt = ref.read(myTsProvider).status != MyTsStatus.otpNeeded;
    if (firstAttempt && !await _confirmReset()) return;
    await ref
        .read(myTsProvider.notifier)
        .login(
          _email.text,
          _password.text,
          otp: _otp.text.trim().isEmpty ? null : _otp.text.trim(),
          resetLocalData: true,
        );
    if (mounted && ref.read(myTsProvider).status == MyTsStatus.signedIn) {
      _password.clear();
      _otp.clear();
    }
  }
}

class _ImportCard extends ConsumerWidget {
  final bool initialSetup;
  final TextEditingController password;

  const _ImportCard({required this.initialSetup, required this.password});

  String _failureText(AppLocalizations l, ImportFailure f) => switch (f) {
    ImportFailure.noSession => l.mytsImportErrNoSession,
    ImportFailure.unlock => l.mytsImportErrUnlock,
    ImportFailure.network => l.mytsImportErrNetwork,
    ImportFailure.service => l.mytsImportErrService,
    ImportFailure.sessionExpired => l.mytsImportErrExpired,
    ImportFailure.invalidData => l.mytsImportErrData,
    ImportFailure.integrity => l.mytsImportErrIntegrity,
    ImportFailure.storage => l.mytsImportErrStorage,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(myTsImportProvider);
    final notifier = ref.read(myTsImportProvider.notifier);
    final theme = Theme.of(context);
    final report = s.report;
    final error = s.failure;
    final hasSaved = ref.watch(hasSavedPasswordProvider).value ?? false;

    List<Widget> summary() => [
      if (report != null)
        Text(
          report.hasChanges
              ? l.mytsImportAdded(report.addedIdentities, report.addedBookmarks)
              : l.mytsImportUpToDate,
        ),
      if (report != null && report.hasSkips) ...[
        const SizedBox(height: 8),
        Text(l.mytsImportSkipped(report.skippedCount)),
      ],
    ];

    final List<Widget> children;
    switch (s.phase) {
      case ImportPhase.working:
        children = [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l.mytsImportWorking)),
            ],
          ),
        ];
      case ImportPhase.awaitingConfirmation:
        children = [
          Text(l.mytsImportConfirmTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (report != null)
            Text(
              l.mytsImportAdded(report.addedIdentities, report.addedBookmarks),
            ),
          if (report != null && report.hasSkips) ...[
            const SizedBox(height: 8),
            Text(l.mytsImportSkipped(report.skippedCount)),
          ],
          const SizedBox(height: 8),
          Text(l.mytsImportChooseIdentityNote),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              _failureText(l, error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: notifier.confirm,
                child: Text(l.mytsImportConfirm),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: notifier.cancel, child: Text(l.cancel)),
            ],
          ),
        ];
      case ImportPhase.done:
        children = [
          ...summary(),
          const SizedBox(height: 8),
          Text(l.mytsImportChooseIdentityNote),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go('/'),
            child: Text(l.mytsImportContinue),
          ),
        ];
      case ImportPhase.nothingToImport:
        children = [Text(l.mytsImportNothing)];
      case ImportPhase.idle || ImportPhase.failed:
        children = [
          Text(l.mytsImportPendingTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            initialSetup ? l.mytsSetupImportPending : l.mytsExistingDataHint,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              _failureText(l, error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          if (hasSaved)
            Text(l.mytsImportUsingSaved)
          else
            TextField(
              controller: password,
              decoration: InputDecoration(
                labelText: l.mytsAccountPassword,
                helperText: l.mytsImportPasswordNote,
                helperMaxLines: 3,
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              if (hasSaved) return notifier.startFromSavedPassword();
              final value = password.text;
              password.clear();
              if (value.isEmpty) return;
              await notifier.startFromStoredSession(value);
            },
            child: Text(l.mytsImportAction),
          ),
        ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
