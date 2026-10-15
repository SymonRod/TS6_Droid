import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../myts/api.dart';
import '../myts/controller.dart';
import '../myts/import_controller.dart';
import '../myts/contact_store.dart';
import 'myts_history_screen.dart';

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
              const SizedBox(height: 12),
              _ImportCard(
                initialSetup: widget.initialSetup,
                password: _importPassword,
              ),
              const SizedBox(height: 12),
              _ContactsCard(key: ValueKey(s.email), email: s.email),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.forum_outlined),
                label: Text(l.mytsHistoryTitle),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MyTsHistoryScreen(),
                  ),
                ),
              ),
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

  Future<void> _submit() async {
    await ref
        .read(myTsProvider.notifier)
        .login(
          _email.text,
          _password.text,
          otp: _otp.text.trim().isEmpty ? null : _otp.text.trim(),
        );
    if (mounted && ref.read(myTsProvider).status == MyTsStatus.signedIn) {
      _password.clear();
      _otp.clear();
    }
  }
}

class _ContactsCard extends ConsumerStatefulWidget {
  final String email;
  const _ContactsCard({super.key, required this.email});
  @override
  ConsumerState<_ContactsCard> createState() => _ContactsCardState();
}

class _ContactsCardState extends ConsumerState<_ContactsCard> {
  final _password = TextEditingController();
  ContactSnapshot? _snapshot;
  bool _busy = false;
  String? _error;
  String? _check;
  final _avatars = <String, Uint8List>{};
  int _avatarGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await ref.read(contactStoreProvider).load(widget.email);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) setState(() => _error = 'storage');
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref.read(myTsSessionStoreProvider).load();
      if (session == null ||
          session.email.trim().toLowerCase() !=
              widget.email.trim().toLowerCase()) {
        throw const FormatException('session changed');
      }
      final api = ref.read(myTsApiProvider);
      final contacts = await api.contacts(session.session);
      String? host = _snapshot?.chatHost;
      if (_password.text.isNotEmpty && session.wrappedKey.isNotEmpty) {
        final key = await api.unlockAccountKey(
          email: session.email,
          password: _password.text,
          wrappedKey: session.wrappedKey,
        );
        if (key == null) throw const FormatException('unlock failed');
        try {
          host = await api.chatHost(session.session, key);
        } finally {
          key.dispose();
        }
      }
      if (!mounted) return;
      _password.clear();
      final snapshot = ContactSnapshot(
        contacts
            .map((c) => StoredContact(c.identifier, c.note, c.matrixId))
            .toList(),
        host,
      );
      // Never let an in-flight refresh from a previous login overwrite another account.
      final current = await ref.read(myTsSessionStoreProvider).load();
      if (!mounted || current?.session != session.session) return;
      await ref.read(contactStoreProvider).save(widget.email, snapshot);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _avatars.clear();
      });
      final generation = ++_avatarGeneration;
      unawaited(
        _loadAvatars(
          api,
          session.session,
          contacts.map((c) => c.matrixId).toList(),
          host,
          generation,
        ),
      );
    } on HttpException catch (e) {
      if (mounted) setState(() => _error = 'HTTP ${e.message.split(' ').last}');
    } on ContactRequestFailure catch (e) {
      if (mounted) setState(() => _error = e.kind.name);
    } catch (_) {
      if (mounted) setState(() => _error = 'request');
    } finally {
      if (mounted) _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAvatars(
    MyTsApi api,
    String session,
    List<String> matrixIds,
    String? accountHost,
    int generation,
  ) async {
    // Avatar failures never invalidate a successfully saved roster.
    if (accountHost == null) return;
    for (final id in matrixIds.where((id) => id.isNotEmpty).take(8)) {
      if (!mounted || generation != _avatarGeneration) return;
      try {
        final bytes = await api.contactAvatar(session, id, accountHost);
        if (!mounted) return;
        final current = await ref.read(myTsSessionStoreProvider).load();
        if (!mounted ||
            generation != _avatarGeneration ||
            current?.session != session) {
          return;
        }
        if (bytes != null) setState(() => _avatars[id] = bytes);
      } catch (_) {
        // Placeholder remains.
      }
    }
  }

  Future<void> _probe() async {
    final host = _snapshot?.chatHost;
    if (host == null) return;
    setState(() {
      _busy = true;
      _check = null;
    });
    try {
      final status = await checkChatVersions(host);
      if (mounted) {
        setState(() => _check = status == 200 ? 'ok' : 'HTTP $status');
      }
    } on FormatException {
      if (mounted) setState(() => _check = 'invalid');
    } catch (_) {
      if (mounted) setState(() => _check = 'network');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snapshot = _snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.mytsContactsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(l.mytsContactsReadOnly),
            if (snapshot == null)
              Text(l.mytsContactsNotLoaded)
            else if (snapshot.contacts.isEmpty)
              Text(l.mytsContactsEmpty)
            else
              for (final c in snapshot.contacts)
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: _avatars[c.matrixId] == null
                        ? null
                        : ResizeImage(
                            MemoryImage(_avatars[c.matrixId]!),
                            width: 128,
                            height: 128,
                          ),
                    onBackgroundImageError: _avatars[c.matrixId] == null
                        ? null
                        : (_, _) {
                            if (mounted) {
                              setState(() => _avatars.remove(c.matrixId));
                            }
                          },
                    child: _avatars[c.matrixId] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(
                    c.note.isNotEmpty
                        ? c.note
                        : c.identifier.isNotEmpty
                        ? c.identifier
                        : c.matrixId,
                  ),
                  subtitle: Text(c.matrixId),
                ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.mytsContactsPasswordHint,
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _refresh,
              child: Text(l.mytsContactsRefresh),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(switch (_error) {
                'storage' => l.mytsContactsStorageError,
                'network' => l.mytsErrorNetwork,
                'expired' => l.mytsImportErrExpired,
                _ when _error!.startsWith('HTTP') => l.mytsErrorHttp(
                  _error!.substring(5),
                ),
                _ => l.mytsContactsLoadError,
              }),
            if (snapshot?.chatHost != null) ...[
              Text(l.mytsChatHost(snapshot!.chatHost!)),
              Text(l.mytsChatProbeHint),
              OutlinedButton(
                onPressed: _busy || !safePublicHttpsHost(snapshot.chatHost!)
                    ? null
                    : _probe,
                child: Text(l.mytsChatProbe),
              ),
              if (_check != null)
                Text(
                  _check == 'ok'
                      ? l.mytsChatProbeOk
                      : _check!.startsWith('HTTP')
                      ? l.mytsChatProbeHttp(_check!.substring(5))
                      : _check == 'invalid'
                      ? l.mytsErrorMalformed
                      : l.mytsChatProbeNetwork,
                ),
            ] else
              Text(l.mytsChatHostMissing),
          ],
        ),
      ),
    );
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
