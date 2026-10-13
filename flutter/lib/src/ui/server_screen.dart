import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../rust/api.dart';
import '../state/server_controller.dart';
import '../util/errors.dart';
import 'bbcode.dart';
import 'ts_image.dart';

class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(serverProvider);
    final snap = s.snapshot;
    final ctrl = ref.read(serverProvider.notifier);
    final l = AppLocalizations.of(context);

    ref.listen(serverProvider.select((s) => s.error), (_, err) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        ctrl.clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(snap?.serverInfo.name ?? 'Server'),
        actions: [
          IconButton(
            icon: Icon(Icons.touch_app, color: s.ptt ? Theme.of(context).colorScheme.primary : null),
            tooltip: l.pttSetting,
            isSelected: s.ptt,
            onPressed: () => ctrl.setPushToTalk(!s.ptt),
          ),
          if (!s.ptt)
            IconButton(
              icon: Icon(s.muted ? Icons.mic_off : Icons.mic, color: s.muted ? null : Colors.green),
              tooltip: s.muted ? l.unmute : l.mute,
              onPressed: ctrl.toggleMute,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.disconnect,
            onPressed: ctrl.disconnect,
          ),
        ],
      ),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: [
              Column(children: [
                Expanded(child: _ChannelTree(snap: snap, talking: s.talking)),
                if (s.ptt) _PttButton(active: !s.muted, onChanged: ctrl.pttHold),
              ]),
              _Chat(snap: snap, messages: s.messages),
            ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.account_tree), label: l.channels),
          NavigationDestination(icon: const Icon(Icons.chat), label: l.chat),
        ],
      ),
    );
  }
}

/// Siblings are chained: `order` is the id of the previous sibling (0 = first).
List<TsChannel> _orderedChildren(List<TsChannel> all, int parent) {
  final kids = all.where((c) => c.parentId == parent).toList();
  final result = <TsChannel>[];
  var prev = 0;
  while (kids.isNotEmpty) {
    final i = kids.indexWhere((c) => c.order == prev);
    if (i < 0) {
      result.addAll(kids); // broken chain: keep whatever is left
      break;
    }
    final c = kids.removeAt(i);
    result.add(c);
    prev = c.id;
  }
  return result;
}

String _channelLabel(String name) {
  final m = RegExp(r'^\[[clr]?spacer\d*\](.*)$').firstMatch(name);
  return m != null ? m.group(1)! : name;
}

void _watch(BuildContext context, WidgetRef ref, TsUser u) {
  final viewer = ref.read(serverProvider.notifier).viewer;
  final snap = ref.read(serverProvider).snapshot;
  if (viewer == null || snap == null) return;
  final stream = snap.streams.where((s) => s.ownerId == u.id).firstOrNull;
  if (stream == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).streamNotReady)));
    ref.read(serverProvider.notifier).requestStreamInfo(u.id);
    return;
  }
  viewer.join(stream.ownerId, stream.id, stream.name ?? u.nickname);
  context.push('/server/stream');
}

Future<void> _join(BuildContext context, WidgetRef ref, TsChannel ch) async {
  final ctrl = ref.read(serverProvider.notifier);
  if (!ch.hasPassword) return ctrl.moveToChannel(ch.id);
  final l = AppLocalizations.of(context);
  final field = TextEditingController();
  final pw = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.channelPasswordTitle),
      content: TextField(
        controller: field,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: l.password),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, field.text), child: Text(l.join)),
      ],
    ),
  );
  field.dispose();
  if (pw != null) await ctrl.moveToChannel(ch.id, password: pw);
}

/// Avatar when the server has one, otherwise the talk/mute/person icon.
class _UserAvatar extends StatelessWidget {
  final TsUser u;
  final bool talking;
  const _UserAvatar(this.u, {required this.talking});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      talking ? Icons.mic : (u.isInputMuted ? Icons.mic_off : Icons.person),
      size: 20,
      color: talking ? Colors.green : null,
    );
    final hasAvatar = (u.avatarId ?? '').isNotEmpty && u.uid.isNotEmpty;
    if (!hasAvatar) return icon;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: talking ? Colors.green : Colors.transparent, width: 2),
      ),
      child: TsImage('avatar:${u.uid}', size: 26, round: true, fallback: icon),
    );
  }
}

class _PttButton extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  const _PttButton({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Listener(
          onPointerDown: (_) => onChanged(true),
          onPointerUp: (_) => onChanged(false),
          onPointerCancel: (_) => onChanged(false),
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Colors.green : cs.secondaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active ? Icons.mic : Icons.mic_off, color: active ? Colors.white : cs.onSecondaryContainer),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).holdToTalk,
                  style: TextStyle(color: active ? Colors.white : cs.onSecondaryContainer)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ChannelTree extends ConsumerWidget {
  final TsSnapshot snap;
  final Set<int> talking;
  const _ChannelTree({required this.snap, required this.talking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[];
    void walk(int parent, int depth) {
      for (final ch in _orderedChildren(snap.channels, parent)) {
        final here = snap.channelId == ch.id;
        rows.add(ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 16, right: 8),
          leading: Icon(ch.hasPassword ? Icons.lock : Icons.tag, size: 20),
          title: Text(_channelLabel(ch.name),
              style: TextStyle(fontWeight: here ? FontWeight.bold : FontWeight.normal)),
          trailing: ch.iconId != 0 ? TsImage('icon:${ch.iconId}', size: 20) : null,
          selected: here,
          onTap: here ? null : () => _join(context, ref, ch),
        ));
        for (final u in snap.users.where((u) => u.channelId == ch.id)) {
          rows.add(ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: 36.0 + depth * 16, right: 8),
            leading: _UserAvatar(u, talking: talking.contains(u.id)),
            title: Row(children: [
              Flexible(
                  child: Text(u.nickname + (u.id == snap.clientId ? ' (${AppLocalizations.of(context).you})' : ''),
                      overflow: TextOverflow.ellipsis)),
              if (u.iconId != 0) ...[
                const SizedBox(width: 6),
                TsImage('icon:${u.iconId}', size: 16),
              ],
            ]),
            trailing: u.isStreaming && u.id != snap.clientId
                ? IconButton(
                    icon: const Icon(Icons.screen_share, size: 20, color: Colors.green),
                    tooltip: AppLocalizations.of(context).watchShare,
                    onPressed: () => _watch(context, ref, u),
                  )
                : (u.isStreaming ? const Icon(Icons.screen_share, size: 18, color: Colors.green) : null),
          ));
        }
        walk(ch.id, depth + 1);
      }
    }

    walk(0, 0);
    return ListView(children: rows);
  }
}

class _Chat extends ConsumerStatefulWidget {
  final TsSnapshot snap;
  final List<ChatMessage> messages;
  const _Chat({required this.snap, required this.messages});

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  TsMessageTarget _target = TsMessageTarget.channel;
  int? _privateTo;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final c = ref.read(serverProvider.notifier);
    try {
      switch (_target) {
        case TsMessageTarget.channel:
          await c.sendChannelMessage(text);
        case TsMessageTarget.server:
          await c.sendServerMessage(text);
        case TsMessageTarget.private:
          if (_privateTo == null) return;
          await c.sendPrivateMessage(_privateTo!, text);
      }
      _input.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cleanError(e))));
    }
  }

  @override
  void didUpdateWidget(_Chat old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.messages.where((m) => m.target == _target).toList();
    final l = AppLocalizations.of(context);
    final others = widget.snap.users.where((u) => u.id != widget.snap.clientId).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<TsMessageTarget>(
          segments: [
            ButtonSegment(value: TsMessageTarget.channel, label: Text(l.tabChannel)),
            ButtonSegment(value: TsMessageTarget.server, label: Text(l.tabServer)),
            ButtonSegment(value: TsMessageTarget.private, label: Text(l.tabPrivate)),
          ],
          selected: {_target},
          onSelectionChanged: (v) => setState(() => _target = v.first),
        ),
      ),
      if (_target == TsMessageTarget.private)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<int>(
            isExpanded: true,
            hint: Text(l.sendTo),
            value: others.any((u) => u.id == _privateTo) ? _privateTo : null,
            items: [for (final u in others) DropdownMenuItem(value: u.id, child: Text(u.nickname))],
            onChanged: (v) => setState(() => _privateTo = v),
          ),
        ),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: shown.length,
          itemBuilder: (_, i) {
            final m = shown[i];
            return Align(
              alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Card(
                color: m.isMe ? Theme.of(context).colorScheme.primaryContainer : null,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.sender, style: Theme.of(context).textTheme.labelSmall),
                    BbText(m.text),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: InputDecoration(hintText: l.messageHint, border: const OutlineInputBorder()),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ]),
      ),
    ]);
  }
}
