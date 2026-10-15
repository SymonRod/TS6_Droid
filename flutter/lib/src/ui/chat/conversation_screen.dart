import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import 'chat_widgets.dart';
import 'chats_tab.dart';
import 'contacts_tab.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String roomId;
  const ConversationScreen({super.key, required this.roomId});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  late final ChatController _controller;
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(chatProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.openRoom(widget.roomId);
    });
  }

  @override
  void dispose() {
    _controller.closeRoom(widget.roomId);
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // The first encrypted message publishes this phone's chat device keys:
    // ask before anything leaves, and keep the typed text if declined.
    if (await _controller.needsEncryptionConsent(widget.roomId)) {
      if (!mounted || !await _confirmEncryption()) return;
      if (!await _controller.grantEncryptionConsent()) return;
    }
    _input.clear();
    await _controller.send(widget.roomId, text);
  }

  Future<bool> _confirmEncryption() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.chatEncryptConsentTitle),
        content: SingleChildScrollView(child: Text(l.chatEncryptConsentBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.chatEncryptConsentContinue),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addContact(String peer, String name) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showContactDialog(
      context,
      ref,
      matrixId: peer,
      note: name,
    );
    if (saved) {
      messenger.showSnackBar(SnackBar(content: Text(l.chatContactAdded)));
    }
  }

  Future<void> _leave() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.chatLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.chatLeave),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _controller.leaveRoom(widget.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(chatProvider);
    ref.listen(chatProvider.select((s) => s.notice), (_, notice) {
      if (notice != ChatNotice.deviceChanged) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.chatNoticeDeviceChanged),
          duration: const Duration(seconds: 6),
        ),
      );
      Future.microtask(_controller.clearNotice);
    });
    final room = s.rooms.where((r) => r.id == widget.roomId).firstOrNull;
    final messages = s.messages[widget.roomId] ?? const <ChatMessage>[];
    final pending = s.pending[widget.roomId] ?? const <PendingMessage>[];
    final title = room == null ? '' : roomTitle(s, room);
    final presence = room != null && room.isDirect
        ? s.account.presenceOf(room.peer)
        : null;
    final group = room != null && !room.isDirect;
    final canAddContact =
        room != null &&
        room.isDirect &&
        room.peer.isNotEmpty &&
        !s.contacts.any((c) => c.matrixId == room.peer);

    // Clear rooms always; encrypted ones only when they are one-to-one (the
    // engine needs a single peer to know whose devices get the room key).
    final canSend =
        room != null &&
        (room.encrypted == false || (room.encrypted == true && room.isDirect));
    final blockedText = room == null || room.encrypted == null
        ? l.chatSendDisabledLoading
        : l.chatSendDisabledEncrypted;

    // Newest first, for a reversed list that sticks to the bottom.
    final items = <Object>[
      for (final p in pending.reversed) p,
      for (final m in messages.reversed) m,
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(
              matrixId: room?.peer ?? '',
              name: title,
              radius: 18,
              group: group,
              presence: presence?.state,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    presence == null
                        ? (room?.encrypted == true
                              ? l.chatEncryptedRoom
                              : room?.encrypted == false
                              ? l.chatPlainRoom
                              : '')
                        : (presence.status.isNotEmpty
                              ? '${presenceLabel(l, presence.state)} · ${presence.status}'
                              : presenceLabel(l, presence.state)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (canAddContact)
            IconButton(
              tooltip: l.chatAddContact,
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => _addContact(room.peer, title),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'leave') _leave();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'leave', child: Text(l.chatLeave)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const ChatErrorBanner(),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(l.chatEmptyConversation))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length + 1,
                    itemBuilder: (context, i) {
                      if (i == items.length) {
                        return room != null && room.hasOlder
                            ? Center(
                                child: TextButton(
                                  onPressed: _loadingOlder
                                      ? null
                                      : () async {
                                          setState(() => _loadingOlder = true);
                                          await _controller.loadOlder(
                                            widget.roomId,
                                          );
                                          if (mounted) {
                                            setState(
                                              () => _loadingOlder = false,
                                            );
                                          }
                                        },
                                  child: Text(l.chatOlder),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final item = items[i];
                      if (item is PendingMessage) {
                        return _PendingBubble(
                          message: item,
                          onRetry: () =>
                              _controller.retry(widget.roomId, item.txn),
                          onDiscard: () =>
                              _controller.discard(widget.roomId, item.txn),
                        );
                      }
                      final message = item as ChatMessage;
                      // The next older item decides whether a day heading goes
                      // above this one.
                      final older = i + 1 < items.length ? items[i + 1] : null;
                      final olderTs = older is ChatMessage
                          ? older.timestamp
                          : 0;
                      final showDay =
                          older is! ChatMessage ||
                          !_sameDay(olderTs, message.timestamp);
                      return Column(
                        children: [
                          if (showDay && message.timestamp > 0)
                            _DayChip(dayHeading(context, message.timestamp)),
                          _Bubble(
                            message: message,
                            mine: message.sender == s.account.user,
                            showSender: group,
                            senderName: s.account.nameOf(message.sender),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (canSend)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: l.chatMessageHint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: l.chatSend,
                      icon: const Icon(Icons.send),
                      onPressed: _send,
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blockedText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

bool _sameDay(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a);
  final y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool showSender;
  final String senderName;
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showSender,
    required this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontStyle: FontStyle.italic,
      color: scheme.onSurfaceVariant,
    );

    Widget content;
    switch (message.status) {
      case 'plaintext' || 'decrypted':
        final text = switch (message.kind) {
          'image' => l.chatImage(message.body),
          'file' || 'audio' || 'video' => l.chatFile(message.body),
          'emote' => '* $senderName ${message.body}',
          _ => message.body,
        };
        content = SelectableText(
          text,
          style: message.kind == 'emote'
              ? const TextStyle(fontStyle: FontStyle.italic)
              : null,
        );
      case 'missing_key':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(l.chatMissingKey, style: muted)),
          ],
        );
      case 'partial':
        content = Text(l.chatPartial, style: muted);
      case 'redacted':
        content = Text(l.chatDeleted, style: muted);
      default:
        content = Text(l.chatInvalidMessage, style: muted);
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: message.readable
            ? () async {
                await Clipboard.setData(ClipboardData(text: message.body));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l.chatCopied),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              }
            : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender && !mine)
                Text(
                  senderName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: scheme.primary),
                ),
              content,
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  shortTime(context, message.timestamp),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBubble extends StatelessWidget {
  final PendingMessage message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  const _PendingBubble({
    required this.message,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: message.failed
              ? scheme.errorContainer
              : scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(message.text)),
            if (message.failed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onRetry, child: Text(l.chatNotSent)),
                  IconButton(
                    tooltip: l.chatDiscard,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDiscard,
                  ),
                ],
              )
            else
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
          ],
        ),
      ),
    );
  }
}
