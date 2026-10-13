import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../data/server_bookmark.dart';
import '../state/server_controller.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _address = TextEditingController();
  final _nickname = TextEditingController();
  final _password = TextEditingController();
  final _channel = TextEditingController();
  int _editing = -1;
  bool _autoReconnect = false;

  @override
  void initState() {
    super.initState();
    _tryAutoReconnect();
  }

  Future<void> _tryAutoReconnect() async {
    final store = ref.read(bookmarkStoreProvider);
    _autoReconnect = await store.autoReconnect();
    if (mounted) setState(() {});
    if (!_autoReconnect) return;
    final last = await store.lastAddress();
    final list = await ref.read(bookmarksProvider.future);
    final b = list.where((b) => b.address == last).firstOrNull;
    if (b != null && mounted) _connect(b);
  }

  ServerBookmark _fromFields() => ServerBookmark(
        name: _address.text.trim().split(':').first,
        address: _address.text.trim(),
        nickname: _nickname.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        channel: _channel.text.trim().isEmpty ? null : _channel.text.trim(),
      );

  void _clear() {
    _address.clear();
    _nickname.clear();
    _password.clear();
    _channel.clear();
    setState(() => _editing = -1);
  }

  Future<void> _connect(ServerBookmark b) async {
    if (b.address.isEmpty || b.nickname.isEmpty) {
      ref.read(serverProvider.notifier).clearError();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).errAddrNick)));
      return;
    }
    await ref.read(bookmarkStoreProvider).setLastAddress(b.address);
    await ref.read(serverProvider.notifier).connect(b);
  }

  Future<void> _save() async {
    final b = _fromFields();
    if (b.address.isEmpty) return;
    final n = ref.read(bookmarksProvider.notifier);
    if (_editing >= 0) {
      await n.replace(_editing, b);
    } else {
      await n.add(b);
    }
    _clear();
  }

  void _edit(ServerBookmark b, int i) {
    _address.text = b.address;
    _nickname.text = b.nickname;
    _password.text = b.password ?? '';
    _channel.text = b.channel ?? '';
    setState(() => _editing = i);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(serverProvider);
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];
    final connecting = s.status == ConnStatus.connecting;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('TS6 Droid')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: l.serverAddress),
            keyboardType: TextInputType.url,
          ),
          TextField(controller: _nickname, decoration: InputDecoration(labelText: l.nickname)),
          TextField(
            controller: _password,
            decoration: InputDecoration(labelText: l.serverPassword),
            obscureText: true,
          ),
          TextField(
            controller: _channel,
            decoration: InputDecoration(labelText: l.channelOptional),
          ),
          const SizedBox(height: 12),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(s.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: connecting ? null : () => _connect(_fromFields()),
                child: connecting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.connect),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _save,
              child: Text(_editing >= 0 ? l.updateBookmark : l.saveBookmark),
            ),
            if (_editing >= 0) TextButton(onPressed: _clear, child: Text(l.cancel)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.reconnectLast),
            value: _autoReconnect,
            onChanged: (v) async {
              await ref.read(bookmarkStoreProvider).setAutoReconnect(v);
              setState(() => _autoReconnect = v);
            },
          ),
          const Divider(),
          if (bookmarks.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(l.noBookmarks)),
          for (var i = 0; i < bookmarks.length; i++)
            ListTile(
              leading: const Icon(Icons.dns),
              title: Text(bookmarks[i].serverName ?? bookmarks[i].name),
              subtitle: Text('${bookmarks[i].nickname} @ ${bookmarks[i].address}'),
              onTap: connecting ? null : () => _connect(bookmarks[i]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(bookmarks[i], i)),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => ref.read(bookmarksProvider.notifier).remove(i),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
