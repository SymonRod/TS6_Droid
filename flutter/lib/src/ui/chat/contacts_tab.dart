import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/chat_controller.dart';
import '../../myts/contact_store.dart';
import 'chat_widgets.dart';
import 'chats_tab.dart';

String contactName(ChatState s, StoredContact c) {
  if (c.note.isNotEmpty) return c.note;
  final name = s.account.names[c.matrixId];
  if (name != null) return name;
  return c.identifier.isNotEmpty ? c.identifier : c.matrixId;
}

/// Opens the existing direct chat with [matrixId], or (after an explicit
/// warning) creates an unencrypted one.
Future<void> openChatWith(
  BuildContext context,
  WidgetRef ref,
  String matrixId,
) async {
  final controller = ref.read(chatProvider.notifier);
  final existing = controller.directRoomWith(matrixId);
  if (existing != null) {
    openConversation(context, existing);
    return;
  }
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.lock_open_outlined),
      title: Text(l.chatStartPlainTitle),
      content: Text(l.chatStartPlainBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(l.chatStart),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final room = await controller.startDirect(matrixId);
  if (room != null && context.mounted) openConversation(context, room);
}

/// "New chat": pick from the contact roster.
Future<void> pickContactAndOpen(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final s = ref.read(chatProvider);
  final contacts = s.contacts.where((c) => c.matrixId.isNotEmpty).toList();
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: contacts.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.chatContactsEmpty),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final contact in contacts)
                  ListTile(
                    leading: ChatAvatar(
                      matrixId: contact.matrixId,
                      name: contactName(s, contact),
                      presence: s.account.presenceOf(contact.matrixId).state,
                    ),
                    title: Text(contactName(s, contact)),
                    onTap: () => Navigator.pop(c, contact.matrixId),
                  ),
              ],
            ),
    ),
  );
  if (picked != null && context.mounted)
    await openChatWith(context, ref, picked);
}

/// Add/edit dialog. It owns its controllers: disposing them from the caller
/// right after `showDialog` returns would hit the TextFields while the route's
/// exit animation is still running (`_dependents.isEmpty` assertion).
class _ContactDialog extends StatefulWidget {
  final String matrixId;
  final String note;
  final bool editing;
  const _ContactDialog({
    required this.matrixId,
    required this.note,
    required this.editing,
  });

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final _id = TextEditingController(text: widget.matrixId);
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _id.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.editing ? l.chatEditContact : l.chatAddContact),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            enabled: !widget.editing && widget.matrixId.isEmpty,
            autocorrect: false,
            decoration: InputDecoration(labelText: l.chatContactId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: l.chatContactNote),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_id.text.trim(), _note.text.trim())),
          child: Text(l.chatSave),
        ),
      ],
    );
  }
}

/// Asks for the contact's id (when not given) and note, then saves it.
/// Returns whether the contact was saved.
Future<bool> showContactDialog(
  BuildContext context,
  WidgetRef ref, {
  String matrixId = '',
  String note = '',
  bool editing = false,
}) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (c) =>
        _ContactDialog(matrixId: matrixId, note: note, editing: editing),
  );
  if (result == null || result.$1.isEmpty) return false;
  return ref.read(chatProvider.notifier).saveContact(result.$1, result.$2);
}

class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  String _filter = '';

  Future<void> _edit({StoredContact? contact}) => showContactDialog(
    context,
    ref,
    matrixId: contact?.matrixId ?? '',
    note: contact?.note ?? '',
    editing: contact != null,
  );

  Future<void> _remove(StoredContact contact) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(chatProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.chatRemoveConfirm(contactName(s, contact))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.chatRemove),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(chatProvider.notifier).removeContact(contact.matrixId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(chatProvider);
    final needle = _filter.trim().toLowerCase();
    final contacts =
        [
          for (final c in s.contacts)
            if (needle.isEmpty ||
                contactName(s, c).toLowerCase().contains(needle) ||
                c.matrixId.toLowerCase().contains(needle))
              c,
        ]..sort(
          (a, b) => contactName(
            s,
            a,
          ).toLowerCase().compareTo(contactName(s, b).toLowerCase()),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        tooltip: l.chatAddContact,
        onPressed: _edit,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.chatSearch,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: ref.read(chatProvider.notifier).refreshContacts,
              child: contacts.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l.chatContactsEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        for (final c in contacts)
                          _ContactTile(
                            contact: c,
                            state: s,
                            onEdit: () => _edit(contact: c),
                            onRemove: () => _remove(c),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  final StoredContact contact;
  final ChatState state;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  const _ContactTile({
    required this.contact,
    required this.state,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final name = contactName(state, contact);
    final presence = state.account.presenceOf(contact.matrixId);
    final known = state.account.presence.containsKey(contact.matrixId);
    return ListTile(
      leading: ChatAvatar(
        matrixId: contact.matrixId,
        name: name,
        presence: known ? presence.state : null,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        known
            ? (presence.status.isEmpty
                  ? presenceLabel(l, presence.state)
                  : '${presenceLabel(l, presence.state)} · ${presence.status}')
            : contact.matrixId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: contact.matrixId.isEmpty
          ? null
          : () => openChatWith(context, ref, contact.matrixId),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l.chatEditContact)),
          PopupMenuItem(value: 'remove', child: Text(l.chatRemove)),
        ],
      ),
    );
  }
}
