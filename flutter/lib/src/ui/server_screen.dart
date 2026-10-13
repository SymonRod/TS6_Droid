import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/api.dart';
import '../state/server_controller.dart';

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
            icon: Icon(s.muted ? Icons.mic_off : Icons.mic, color: s.muted ? null : Colors.green),
            tooltip: s.muted ? 'Unmute' : 'Mute',
            onPressed: ctrl.toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: ctrl.disconnect,
          ),
        ],
      ),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: [
              _ChannelTree(snap: snap, talking: s.talking),
              _Chat(snap: snap, messages: s.messages),
            ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'Channels'),
          NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
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
          selected: here,
          onTap: here ? null : () => ref.read(serverProvider.notifier).moveToChannel(ch.id),
        ));
        for (final u in snap.users.where((u) => u.channelId == ch.id)) {
          rows.add(ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: 36.0 + depth * 16, right: 8),
            leading: Icon(
              talking.contains(u.id) ? Icons.mic : (u.isInputMuted ? Icons.mic_off : Icons.person),
              size: 20,
              color: talking.contains(u.id) ? Colors.green : null,
            ),
            title: Text(u.nickname + (u.id == snap.clientId ? ' (you)' : '')),
            trailing: u.isStreaming ? const Icon(Icons.screen_share, size: 18, color: Colors.green) : null,
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
    final others = widget.snap.users.where((u) => u.id != widget.snap.clientId).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<TsMessageTarget>(
          segments: const [
            ButtonSegment(value: TsMessageTarget.channel, label: Text('Channel')),
            ButtonSegment(value: TsMessageTarget.server, label: Text('Server')),
            ButtonSegment(value: TsMessageTarget.private, label: Text('Private')),
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
            hint: const Text('Send to...'),
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
                    SelectableText(m.text), // BBCode shown raw for now
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
              decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ]),
      ),
    ]);
  }
}
