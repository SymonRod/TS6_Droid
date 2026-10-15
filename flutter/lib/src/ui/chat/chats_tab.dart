import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import 'chat_widgets.dart';
import 'contacts_tab.dart';
import 'conversation_screen.dart';

String roomTitle(ChatState s, ChatRoom room) {
  if (room.isDirect) {
    final name = s.account.names[room.peer];
    if (name != null) return name;
    final contact = s.contacts
        .where((c) => c.matrixId == room.peer)
        .firstOrNull;
    if (contact != null && contact.note.isNotEmpty) return contact.note;
  }
  return room.title.isEmpty ? room.id : room.title;
}

class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(chatProvider);
    final controller = ref.read(chatProvider.notifier);
    final invites = s.account.invites.values.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_outlined),
        label: Text(l.chatNewChat),
        onPressed: () => pickContactAndOpen(context, ref),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: s.rooms.isEmpty && invites.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 96),
                  const Icon(Icons.chat_bubble_outline, size: 56),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.chatNoChats, textAlign: TextAlign.center),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  if (invites.isNotEmpty) ...[
                    _SectionLabel(l.chatInvites),
                    for (final invite in invites)
                      _InviteTile(invite: invite, state: s),
                    const Divider(),
                  ],
                  for (final room in s.rooms) _RoomTile(room: room, state: s),
                ],
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _InviteTile extends ConsumerWidget {
  final ChatInvite invite;
  final ChatState state;
  const _InviteTile({required this.invite, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(chatProvider.notifier);
    final who = invite.inviter.isEmpty
        ? invite.name
        : state.account.nameOf(invite.inviter);
    return ListTile(
      leading: ChatAvatar(matrixId: invite.inviter, name: who),
      title: Text(l.chatInvitedBy(who)),
      subtitle: invite.name.isEmpty ? null : Text(invite.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.chatDecline,
            icon: const Icon(Icons.close),
            onPressed: () => controller.leaveRoom(invite.room),
          ),
          IconButton.filledTonal(
            tooltip: l.chatAccept,
            icon: const Icon(Icons.check),
            onPressed: () => controller.acceptInvite(invite.room),
          ),
        ],
      ),
    );
  }
}

class _RoomTile extends ConsumerWidget {
  final ChatRoom room;
  final ChatState state;
  const _RoomTile({required this.room, required this.state});

  String _preview(AppLocalizations l) {
    switch (room.lastStatus) {
      case '':
        return '';
      case 'missing_key' || 'partial':
        return l.chatLastEncrypted;
      case 'redacted':
        return l.chatLastDeleted;
      case 'plaintext' || 'decrypted':
        final mine = room.lastSender == state.account.user;
        final prefix = mine
            ? '${l.chatYou}: '
            : (room.isDirect
                  ? ''
                  : '${state.account.nameOf(room.lastSender)}: ');
        return '$prefix${room.lastBody}';
      default:
        return l.chatLastUnavailable;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = roomTitle(state, room);
    final presence = room.isDirect
        ? state.account.presenceOf(room.peer).state
        : null;
    return ListTile(
      leading: ChatAvatar(
        matrixId: room.peer,
        name: title,
        group: !room.isDirect,
        presence: presence,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (room.encrypted == true)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.lock_outline, size: 14),
            ),
          Expanded(
            child: Text(
              _preview(l),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Text(
        shortTime(context, room.lastTs),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => openConversation(context, room.id),
    );
  }
}

void openConversation(BuildContext context, String roomId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ConversationScreen(roomId: roomId)),
  );
}
