import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../myts/api.dart';
import '../myts/controller.dart';

/// myTeamSpeak sign-in (milestone M1: password login, optional OTP step).
/// No sync, import or account mutation happens here.
class MyTsLoginScreen extends ConsumerStatefulWidget {
  const MyTsLoginScreen({super.key});

  @override
  ConsumerState<MyTsLoginScreen> createState() => _MyTsLoginScreenState();
}

class _MyTsLoginScreenState extends ConsumerState<MyTsLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
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
    final l = AppLocalizations.of(context);
    final signedIn = s.status == MyTsStatus.signedIn;
    final otpNeeded = s.status == MyTsStatus.otpNeeded;

    return Scaffold(
      appBar: AppBar(title: Text(l.mytsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (signedIn) ...[
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(l.mytsLoggedInAs(s.username)),
              subtitle: s.email.isEmpty ? null : Text(s.email),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(myTsProvider.notifier).logout(),
              child: Text(l.mytsLogout),
            ),
          ] else ...[
            TextField(
              controller: _email,
              decoration: InputDecoration(labelText: l.mytsEmail),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              enabled: !s.busy,
              onChanged: (_) => ref.read(myTsProvider.notifier).clearError(),
            ),
            TextField(
              controller: _password,
              decoration: InputDecoration(labelText: l.mytsAccountPassword),
              obscureText: true,
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: s.busy ? null : _submit,
              child: s.busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.mytsLogin),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() => ref.read(myTsProvider.notifier).login(
        _email.text,
        _password.text,
        otp: _otp.text.trim().isEmpty ? null : _otp.text.trim(),
      );
}
