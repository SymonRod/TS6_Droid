import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import 'chat_widgets.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  final _name = TextEditingController();
  final _status = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _status.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(chatProvider);
    final controller = ref.read(chatProvider.notifier);
    final me = s.account.me;
    final myName = s.account.names[s.account.user] ?? '';
    if (!_seeded && s.account.user.isNotEmpty) {
      _seeded = true;
      _name.text = myName;
      _status.text = me.status;
    }

    Future<void> setState0(int state) async {
      await controller.setPresence(state, _status.text);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ChatAvatar(
            matrixId: s.account.user,
            name: myName.isEmpty ? s.account.user : myName,
            radius: 48,
            presence: me.state,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: SelectableText(
            s.account.user,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l.chatProfileAvatarTitle),
            subtitle: Text(l.chatProfileAvatarNote),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 64,
          decoration: InputDecoration(
            labelText: l.chatProfileName,
            suffixIcon: IconButton(
              tooltip: l.chatSave,
              icon: const Icon(Icons.check),
              onPressed: () async {
                await controller.setDisplayName(_name.text);
                if (context.mounted) _toast(l.chatProfileSaved);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.chatProfileStatus,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in const [
              PresenceState.available,
              PresenceState.away,
              PresenceState.doNotDisturb,
              PresenceState.offline,
            ])
              ChoiceChip(
                avatar: Icon(
                  presenceIcon(state),
                  size: 16,
                  color: presenceColor(context, state),
                ),
                label: Text(
                  state == PresenceState.offline
                      ? l.chatStatusInvisible
                      : presenceLabel(l, state),
                ),
                selected: me.state == state,
                onSelected: (_) => setState0(state),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _status,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: l.chatProfileStatusMessage,
            hintText: l.chatProfileStatusHint,
            suffixIcon: IconButton(
              tooltip: l.chatSave,
              icon: const Icon(Icons.check),
              onPressed: () async {
                await controller.setPresence(me.state, _status.text);
                if (context.mounted) _toast(l.chatProfileSaved);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(l.chatSecurityNote, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.lock_outline),
          label: Text(l.chatLock),
          onPressed: controller.lock,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l.chatLockHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
