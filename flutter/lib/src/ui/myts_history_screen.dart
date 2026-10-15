import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../myts/controller.dart';
import '../myts/history.dart';

/// Text history only. Opening this page never logs in or publishes keys.
class MyTsHistoryScreen extends ConsumerStatefulWidget {
  const MyTsHistoryScreen({super.key});

  @override
  ConsumerState<MyTsHistoryScreen> createState() => _MyTsHistoryScreenState();
}

class _MyTsHistoryScreenState extends ConsumerState<MyTsHistoryScreen> {
  final _password = TextEditingController();
  HistoryReader? _reader;
  Map<String, dynamic>? _view;
  String _room = '';
  bool _busy = false;
  bool _failed = false;
  bool _allowOwnEmpty = false;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await operation();
    } catch (_) {
      // Native/network errors may include secret-bearing URLs. Never render them.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() => _run(() async {
    final password = _password.text;
    _password.clear();
    if (password.isEmpty) throw const FormatException('password required');
    final reader = await HistoryReader.open(
      api: ref.read(myTsApiProvider),
      sessions: ref.read(myTsSessionStoreProvider),
      password: password,
      allowOwnEmpty: _allowOwnEmpty,
    );
    if (!mounted) {
      reader.close();
      return;
    }
    _reader = reader;
    final view = await reader.view();
    if (mounted) setState(() => _view = view);
  });

  Future<void> _refresh() => _run(() async {
    final reader = _reader!;
    if (_room.isEmpty) {
      await reader.connect();
    } else {
      await reader.messages(_room);
    }
    final view = await reader.view(_room);
    if (mounted) setState(() => _view = view);
  });

  Future<void> _select(String room) => _run(() async {
    final cached = await _reader!.view(room);
    if (mounted) {
      setState(() {
        _room = room;
        _view = cached;
      });
    }
    if (cached['authenticated'] == true) {
      await _reader!.messages(room);
      final loaded = await _reader!.view(room);
      if (mounted) setState(() => _view = loaded);
    }
  });

  Future<void> _older() => _run(() async {
    await _reader!.messages(_room, older: true);
    final view = await _reader!.view(_room);
    if (mounted) setState(() => _view = view);
  });

  @override
  void dispose() {
    _password.dispose();
    _reader?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(myTsProvider, (previous, next) {
      if (next.status != MyTsStatus.signedIn ||
          _reader != null && next.email != _reader!.owner.email) {
        _reader?.close();
        setState(() {
          _reader = null;
          _view = null;
          _room = '';
        });
      }
    });
    final rooms = (_view?['rooms'] as List? ?? []).cast<Map<String, dynamic>>();
    final messages = (_view?['messages'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final selected = rooms.where((r) => r['id'] == _room).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _room.isEmpty
              ? l.mytsHistoryTitle
              : selected?['title'] as String? ?? l.mytsHistoryTitle,
        ),
        leading: _room.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l.mytsHistoryRooms,
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final view = await _reader!.view();
                        if (mounted) {
                          setState(() {
                            _room = '';
                            _view = view;
                            _failed = false;
                          });
                        }
                      }),
              ),
        actions: [
          if (_reader != null)
            IconButton(
              tooltip: l.mytsHistoryRefresh,
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _refresh,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l.mytsHistoryReadOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l.mytsHistoryError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_reader == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l.mytsAccountPassword,
                    ),
                    onSubmitted: (_) => _unlock(),
                  ),
                  CheckboxListTile(
                    value: _allowOwnEmpty,
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _allowOwnEmpty = value ?? false),
                    title: Text(l.mytsHistoryAllowOwnEmpty),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: Text(l.mytsHistoryUnlock),
                  ),
                ],
              ),
            )
          else if (_room.isEmpty) ...[
            if (_view?['authenticated'] != true)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l.mytsHistoryFirstLogin),
              ),
            OutlinedButton(
              onPressed: _busy ? null : _refresh,
              child: Text(l.mytsHistoryConnect),
            ),
            Expanded(
              child: rooms.isEmpty
                  ? Center(child: Text(l.mytsHistoryEmpty))
                  : ListView.builder(
                      itemCount: rooms.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(rooms[i]['title'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy
                            ? null
                            : () => _select(rooms[i]['id'] as String),
                      ),
                    ),
            ),
          ] else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (selected?['has_older'] == true)
                    OutlinedButton(
                      onPressed: _busy ? null : _older,
                      child: Text(l.mytsHistoryOlder),
                    ),
                  if (messages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.mytsHistoryNoMessages),
                    ),
                  for (final m in messages)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m['sender'] as String,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 6),
                            SelectableText(switch (m['status']) {
                              'plaintext' || 'decrypted' => m['body'] as String,
                              'partial' => l.mytsHistoryPartial,
                              'missing_key' => l.mytsHistoryMissingKey,
                              _ => l.mytsHistoryInvalid,
                            }),
                            const SizedBox(height: 6),
                            Text(
                              m['status'] == 'plaintext'
                                  ? l.mytsHistoryPlaintext
                                  : m['status'] == 'decrypted'
                                  ? (m['metadata_matched'] == true
                                        ? l.mytsHistoryUnverified
                                        : l.mytsHistoryOwnUnverified)
                                  : '',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
