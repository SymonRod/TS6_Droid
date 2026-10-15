import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/chat_controller.dart';
import '../../myts/controller.dart';
import 'chat_widgets.dart';
import 'chats_tab.dart';
import 'contacts_tab.dart';
import 'profile_tab.dart';

/// Account chat: conversations, contacts and profile behind one unlock.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  int _tab = 0;
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(chatProvider.notifier);
    _controller.setForeground(true);
    // With a saved password the chat opens without a prompt; without one (or
    // if it fails) the password form below is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.unlockWithSaved();
    });
  }

  @override
  void dispose() {
    _controller.setForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final signedIn = ref.watch(
      myTsProvider.select((s) => s.status == MyTsStatus.signedIn),
    );
    final s = ref.watch(chatProvider);
    final invites = s.account.invites.length;

    final Widget body;
    if (!signedIn) {
      body = _SignInRequired(l: l);
    } else if (s.phase == ChatPhase.locked || s.phase == ChatPhase.unlocking) {
      body = const _UnlockView();
    } else if (s.phase == ChatPhase.connecting) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.chatConnecting),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          const ChatErrorBanner(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [ChatsTab(), ContactsTab(), ProfileTab()],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chatTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          if (s.ready && _tab != 2)
            s.refreshing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: l.chatRefresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: _controller.refresh,
                  ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: s.ready && signedIn
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: invites > 0,
                    label: Text('$invites'),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  selectedIcon: const Icon(Icons.chat_bubble),
                  label: l.chatTabChats,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.people_outline),
                  selectedIcon: const Icon(Icons.people),
                  label: l.chatTabContacts,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_circle_outlined),
                  selectedIcon: const Icon(Icons.account_circle),
                  label: l.chatTabProfile,
                ),
              ],
            )
          : null,
    );
  }
}

class _SignInRequired extends StatelessWidget {
  final AppLocalizations l;
  const _SignInRequired({required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 56),
            const SizedBox(height: 16),
            Text(l.chatSignInRequired, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/myts'),
              child: Text(l.chatSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockView extends ConsumerStatefulWidget {
  const _UnlockView();

  @override
  ConsumerState<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends ConsumerState<_UnlockView> {
  final _password = TextEditingController();
  bool _own = false;
  bool _show = false;
  bool _manual = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _password.text;
    if (value.isEmpty) return;
    _password.clear();
    await ref.read(chatProvider.notifier).unlock(value, allowOwnEmpty: _own);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(chatProvider);
    final busy = s.phase == ChatPhase.unlocking;
    final remember = ref.watch(rememberPasswordProvider);
    final hasSaved = ref.watch(hasSavedPasswordProvider).value ?? false;
    final useSaved = hasSaved && !_manual;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.lock_outline, size: 56),
        const SizedBox(height: 16),
        Text(
          l.chatUnlockTitle,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          useSaved ? l.chatUnlockSavedBody : l.chatUnlockBody,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (!useSaved) ...[
          TextField(
            controller: _password,
            enabled: !busy,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: l.mytsAccountPassword,
              suffixIcon: IconButton(
                tooltip: _show ? l.mytsHidePassword : l.mytsShowPassword,
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: remember,
            onChanged: busy
                ? null
                : (v) => ref
                      .read(rememberPasswordProvider.notifier)
                      .set(v ?? true),
            title: Text(l.mytsRememberPassword),
            subtitle: Text(l.mytsRememberPasswordHint),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          ExpansionTile(
            title: Text(l.chatAdvanced),
            tilePadding: EdgeInsets.zero,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _own,
                onChanged: busy
                    ? null
                    : (v) => setState(() => _own = v ?? false),
                title: Text(l.chatAllowOwnEmpty),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ],
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              chatErrorText(l, s),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: busy
              ? null
              : useSaved
              ? ref.read(chatProvider.notifier).unlockWithSaved
              : _submit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.chatUnlock),
        ),
        if (useSaved)
          TextButton(
            onPressed: busy ? null : () => setState(() => _manual = true),
            child: Text(l.chatUnlockManual),
          ),
      ],
    );
  }
}
