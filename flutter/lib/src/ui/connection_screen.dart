import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../data/account_vault.dart';
import '../data/server_bookmark.dart';
import '../state/identity_resolver.dart';
import '../state/imported_bookmarks.dart';
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
    // Background reconnect never asks which identity to use: without a
    // settled identity it simply does not connect.
    if (b != null && mounted) _connect(b, interactive: false);
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

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _connect(ServerBookmark b, {bool interactive = true}) async {
    final l = AppLocalizations.of(context);
    if (b.address.isEmpty || (b.nickname.isEmpty && !b.imported)) {
      ref.read(serverProvider.notifier).clearError();
      _snack(l.errAddrNick);
      return;
    }
    final ResolvedIdentity? resolved;
    try {
      resolved = await ref.read(identityResolverProvider).resolve(
            b,
            ask: (options, {required canCreate}) => _askIdentity(options, canCreate),
            interactive: interactive,
          );
    } catch (_) {
      if (mounted && interactive) _snack(l.identityUnavailable);
      return;
    }
    if (resolved == null || !mounted) return;
    ref.invalidate(importedBookmarksProvider);
    final nickname = b.nickname.isNotEmpty ? b.nickname : (resolved.nicknameHint ?? '').trim();
    if (nickname.isEmpty) {
      ref.read(serverProvider.notifier).clearError();
      _snack(l.errAddrNick);
      return;
    }
    await ref.read(bookmarkStoreProvider).setLastAddress(b.address);
    await ref
        .read(serverProvider.notifier)
        .connect(b.withNickname(nickname), identity: resolved.identity);
  }

  /// The user's own identity choice. Nothing is preselected and nothing is
  /// chosen for them; the cloud reference is not consulted.
  Future<String?> _askIdentity(List<IdentityOption> options, bool canCreate) {
    final l = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.identityChooseTitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(l.identityChooseBody),
          ),
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(o.id == AccountVault.legacyIdentityId ? l.identityLocal : o.label),
                subtitle: Text(o.uid, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          if (canCreate)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, IdentityResolver.createLocal),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add),
                title: Text(l.identityCreate),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Change the stored choice for an imported bookmark.
  Future<void> _changeIdentity(ServerBookmark b) async {
    final l = AppLocalizations.of(context);
    try {
      final options = await ref.read(identityResolverProvider).options();
      if (!mounted) return;
      final choice = await _askIdentity(options, false);
      if (choice == null || !options.any((o) => o.id == choice)) return;
      await ref.read(identityResolverProvider).choose(b.vaultId!, choice);
      ref.read(identityLinkRevision.notifier).bump();
    } catch (_) {
      if (mounted) _snack(l.identityUnavailable);
    }
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
    if (mounted) Navigator.of(context).pop();
  }

  void _edit(ServerBookmark b, int i) {
    _address.text = b.address;
    _nickname.text = b.nickname;
    _password.text = b.password ?? '';
    _channel.text = b.channel ?? '';
    _editing = i;
    _openSheet();
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _serverSheet(context),
    );
    _clear();
  }

  Widget _serverSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    final connecting = ref.read(serverProvider).status == ConnStatus.connecting;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing >= 0 ? l.editServer : l.newServer,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: l.serverAddress,
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nickname,
              decoration: InputDecoration(
                labelText: l.nickname,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: l.serverPassword,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              obscureText: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _channel,
              decoration: InputDecoration(
                labelText: l.channelOptional,
                prefixIcon: const Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.login),
                  onPressed: connecting
                      ? null
                      : () {
                          final b = _fromFields();
                          Navigator.of(context).pop();
                          _connect(b);
                        },
                  label: Text(l.connect),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: _save,
                  label: Text(_editing >= 0 ? l.updateBookmark : l.saveBookmark),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(serverProvider);
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];
    final imported = ref.watch(importedBookmarksProvider).value ?? const [];
    final connecting = s.status == ConnStatus.connecting;
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TS6 Droid'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: l.mytsTitle,
            onPressed: () => context.push('/myts'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSheet,
        icon: const Icon(Icons.add),
        label: Text(l.newServer),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (s.error != null)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.error_outline, color: cs.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.error!, style: TextStyle(color: cs.onErrorContainer)),
                  ),
                ]),
              ),
            ),
          if (connecting) const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.history),
              title: Text(l.reconnectLast),
              value: _autoReconnect,
              onChanged: (v) async {
                await ref.read(bookmarkStoreProvider).setAutoReconnect(v);
                setState(() => _autoReconnect = v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            child: Text(
              l.savedServers,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary),
            ),
          ),
          if (bookmarks.isEmpty && imported.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                Icon(Icons.dns_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(l.noBookmarks, style: TextStyle(color: cs.outline)),
              ]),
            ),
          for (final entry in imported)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(entry.bookmark.name),
                subtitle: Text(
                  '${entry.bookmark.nickname.isEmpty ? '' : '${entry.bookmark.nickname} @ '}'
                  '${entry.bookmark.address}\n'
                  '${l.importedFromAccount} · '
                  '${entry.usesLocalIdentityFile ? l.identityChosen(l.identityLocal) : entry.identityLabel != null ? l.identityChosen(entry.identityLabel!) : l.identityNotChosen}',
                ),
                isThreeLine: true,
                onTap: connecting ? null : () => _connect(entry.bookmark),
                trailing: IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: l.identityChange,
                  onPressed: connecting ? null : () => _changeIdentity(entry.bookmark),
                ),
              ),
            ),
          for (var i = 0; i < bookmarks.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.dns),
                title: Text(bookmarks[i].serverName ?? bookmarks[i].name),
                subtitle: Text('${bookmarks[i].nickname} @ ${bookmarks[i].address}'),
                onTap: connecting ? null : () => _connect(bookmarks[i]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(bookmarks[i], i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref.read(bookmarksProvider.notifier).remove(i),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
