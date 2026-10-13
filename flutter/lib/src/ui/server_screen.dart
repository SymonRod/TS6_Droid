import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../rust/api.dart';
import '../state/server_controller.dart';
import '../state/stream_broadcaster.dart' show ShareState;
import '../util/errors.dart';
import 'bbcode.dart';
import 'theme.dart';
import 'ts_image.dart';

class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  static const _channel = MethodChannel('ts6/audio');
  int _tab = 0;

  void _moveToBack() => _channel.invokeMethod('moveTaskToBack').catchError((_) {});

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

    final kb = MediaQuery.of(context).viewInsets.bottom > 0;
    // Back must not leave the server screen (the router root): send the app to the
    // background like Home, keeping the connection and UI state intact.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _moveToBack();
      },
      child: Scaffold(
      appBar: AppBar(title: Text(snap?.serverInfo.name ?? 'Server')),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _tab, children: [
              _ChannelTree(snap: snap, talking: s.talking),
              _Chat(snap: snap, messages: s.messages),
            ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (snap != null && !kb) const _ControlBar(),
        NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.account_tree), label: l.channels),
            NavigationDestination(icon: const Icon(Icons.chat), label: l.chat),
          ],
        ),
      ]),
    ));
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

Color _avatarColor(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.36).toColor();
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'[\s_\-.]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final r = words[0].runes.toList();
    return String.fromCharCodes(r.take(2)).toUpperCase();
  }
  return (String.fromCharCode(words[0].runes.first) + String.fromCharCode(words[1].runes.first)).toUpperCase();
}

/// Server avatar when we have one, otherwise a coloured circle with initials.
/// A green ring pulses in while the user is talking.
class _UserAvatar extends StatelessWidget {
  final TsUser u;
  final bool talking;
  const _UserAvatar(this.u, {required this.talking});

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    final ring = TsColors.of(context).talking;
    final key = u.uid.isNotEmpty ? u.uid : u.nickname;
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _avatarColor(key), shape: BoxShape.circle),
      child: Text(_initials(u.nickname),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    );
    final hasAvatar = (u.avatarId ?? '').isNotEmpty && u.uid.isNotEmpty;
    final inner = hasAvatar ? TsImage('avatar:${u.uid}', size: size, round: true, fallback: initials) : initials;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: talking ? ring : Colors.transparent, width: 2.5),
        boxShadow: talking ? [BoxShadow(color: ring.withValues(alpha: 0.45), blurRadius: 8)] : null,
      ),
      child: inner,
    );
  }
}

Future<void> _confirmDisconnect(BuildContext context, ServerController ctrl, AppLocalizations l) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.disconnectConfirm),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.disconnect)),
      ],
    ),
  );
  if (ok == true) ctrl.disconnect();
}

class _ControlBar extends ConsumerWidget {
  const _ControlBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(serverProvider);
    final ctrl = ref.read(serverProvider.notifier);
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tc = TsColors.of(context);
    final live = !s.muted;

    Widget btn(IconData icon, String label, VoidCallback onTap,
        {Color? bg, Color? fg, int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: bg ?? cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: _btnFace(icon, label, fg ?? cs.onSurface),
            ),
          ),
        ),
      );
    }

    final Widget mic;
    if (s.ptt) {
      mic = Expanded(
        flex: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Listener(
            onPointerDown: (_) => ctrl.pttHold(true),
            onPointerUp: (_) => ctrl.pttHold(false),
            onPointerCancel: (_) => ctrl.pttHold(false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: live ? tc.talking : cs.secondaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: _btnFace(live ? Icons.mic : Icons.mic_off, l.holdToTalk,
                  live ? Colors.black : cs.onSecondaryContainer),
            ),
          ),
        ),
      );
    } else {
      mic = btn(
        s.muted ? Icons.mic_off : Icons.mic,
        s.muted ? l.unmute : l.mute,
        ctrl.toggleMute,
        bg: s.muted ? tc.muted.withValues(alpha: 0.22) : tc.talking,
        fg: s.muted ? tc.muted : Colors.black,
        flex: 2,
      );
    }

    return Material(
      color: cs.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: SizedBox(
          height: 68,
          child: Row(children: [
            mic,
            btn(s.deafened ? Icons.headset_off : Icons.headset, s.deafened ? l.undeafen : l.deafen,
                ctrl.toggleDeafen,
                bg: s.deafened ? tc.muted.withValues(alpha: 0.22) : null, fg: s.deafened ? tc.muted : null),
            btn(_routeIcon(s.route.current), l.audioOutput, () => _pickAudio(context, ref, l),
                bg: s.route.current?.isBluetooth == true ? cs.primaryContainer : null,
                fg: s.route.current?.isBluetooth == true ? cs.onPrimaryContainer : null),
            btn(Icons.more_horiz, l.more, () => _more(context, ref, l),
                bg: s.share != ShareState.idle || s.ptt ? cs.primaryContainer : null,
                fg: s.share != ShareState.idle || s.ptt ? cs.onPrimaryContainer : null),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: l.disconnect,
                child: Material(
                  color: tc.muted,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _confirmDisconnect(context, ctrl, l),
                    child: const SizedBox(
                        width: 56, height: double.infinity, child: Icon(Icons.call_end, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static IconData _routeIcon(AudioDevice? d) {
    if (d == null) return Icons.volume_up;
    if (d.isBluetooth) return Icons.bluetooth_audio;
    if (d.isWired) return Icons.headphones;
    return d.type == 1 ? Icons.phone_in_talk : Icons.volume_up;
  }

  String _deviceName(AudioDevice d, AppLocalizations l) => switch (d.name) {
        'speaker' => l.audioSpeaker,
        'earpiece' => l.audioEarpiece,
        'device' => l.audioDeviceFallback,
        final n => n,
      };

  void _more(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final ctrl = ref.read(serverProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final s = ref.watch(serverProvider);
        final sharing = s.share != ShareState.idle;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(sharing ? Icons.stop_screen_share : Icons.screen_share),
              title: Text(sharing ? l.stopShare : l.shareScreen),
              onTap: () {
                ctrl.toggleScreenShare();
                Navigator.pop(ctx);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.touch_app),
              title: Text(l.pttSetting),
              value: s.ptt,
              onChanged: ctrl.setPushToTalk,
            ),
          ]),
        );
      }),
    );
  }

  void _pickAudio(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final ctrl = ref.read(serverProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final r = ref.watch(serverProvider.select((s) => s.route));
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(l.audioAuto),
              trailing: r.auto ? const Icon(Icons.check) : null,
              onTap: () {
                ctrl.setAudioDevice(null);
                Navigator.pop(ctx);
              },
            ),
            for (final d in r.devices)
              ListTile(
                leading: Icon(_routeIcon(d)),
                title: Text(_deviceName(d, l)),
                trailing: !r.auto && d.id == r.active ? const Icon(Icons.check) : null,
                onTap: () {
                  ctrl.setAudioDevice(d.id);
                  Navigator.pop(ctx);
                },
              ),
          ]),
        );
      }),
    );
  }

  Widget _btnFace(IconData icon, String label, Color fg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 28, color: fg),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.1, color: fg, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _ChannelTree extends ConsumerStatefulWidget {
  final TsSnapshot snap;
  final Set<int> talking;
  const _ChannelTree({required this.snap, required this.talking});

  @override
  ConsumerState<_ChannelTree> createState() => _ChannelTreeState();
}

class _ChannelTreeState extends ConsumerState<_ChannelTree> {
  final _collapsed = <int>{};
  static const _indent = 20.0;

  Widget _guides(int depth, Color color, Widget child) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(width: 8),
          for (var i = 0; i < depth; i++)
            SizedBox(
              width: _indent,
              child: Align(alignment: Alignment.centerLeft, child: Container(width: 1.5, color: color)),
            ),
          Expanded(child: child),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final snap = widget.snap;
    final cs = Theme.of(context).colorScheme;
    final tc = TsColors.of(context);
    final l = AppLocalizations.of(context);
    final line = cs.outlineVariant;
    final myChannel =
        snap.users.where((u) => u.id == snap.clientId).map((u) => u.channelId).firstOrNull ?? snap.channelId;
    final rows = <Widget>[];

    void walk(int parent, int depth) {
      for (final ch in _orderedChildren(snap.channels, parent)) {
        final here = myChannel == ch.id;
        final kids = _orderedChildren(snap.channels, ch.id);
        final users = snap.users.where((u) => u.channelId == ch.id).toList();
        final expandable = kids.isNotEmpty || users.isNotEmpty;
        final closed = _collapsed.contains(ch.id);
        final total = users.length;
        rows.add(_guides(
          depth,
          line,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Material(
              color: here ? cs.primary.withValues(alpha: 0.22) : Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: here ? cs.primary : Colors.transparent, width: 1.5)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: here ? null : () => _join(context, ref, ch),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 36,
                      height: 44,
                      child: expandable
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: AnimatedRotation(
                                turns: closed ? -0.25 : 0,
                                duration: const Duration(milliseconds: 150),
                                child: const Icon(Icons.expand_more, size: 22),
                              ),
                              onPressed: () => setState(() {
                                if (!_collapsed.remove(ch.id)) _collapsed.add(ch.id);
                              }),
                            )
                          : null,
                    ),
                    Icon(ch.hasPassword ? Icons.lock : Icons.tag,
                        size: 18, color: here ? cs.primary : cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_channelLabel(ch.name),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: here ? FontWeight.w700 : FontWeight.w600,
                              color: here ? cs.primary : cs.onSurface)),
                    ),
                    if (ch.iconId != 0) ...[const SizedBox(width: 6), TsImage('icon:${ch.iconId}', size: 18)],
                    if (closed && total > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                        child: Text('$total', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ));
        if (!closed) {
          for (final u in users) {
            final isTalking = widget.talking.contains(u.id);
            final me = u.id == snap.clientId;
            rows.add(_guides(
              depth + 1,
              line,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 46),
                  child: Row(children: [
                    _UserAvatar(u, talking: isTalking),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(u.nickname + (me ? ' (${l.you})' : ''),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isTalking || me ? FontWeight.w600 : FontWeight.normal,
                              color: isTalking ? tc.talking : cs.onSurface)),
                    ),
                    if (u.iconId != 0) ...[TsImage('icon:${u.iconId}', size: 16), const SizedBox(width: 6)],
                    if (u.isAway) Icon(Icons.bedtime, size: 18, color: tc.away),
                    if (u.isOutputMuted || !u.hasOutputHardware)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.headset_off, size: 18, color: tc.muted),
                      ),
                    if (u.isInputMuted || !u.hasInputHardware)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.mic_off, size: 18, color: tc.muted),
                      ),
                    if (u.isStreaming)
                      me
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.screen_share, size: 18, color: tc.talking))
                          : IconButton(
                              icon: Icon(Icons.screen_share, size: 22, color: tc.talking),
                              tooltip: l.watchShare,
                              onPressed: () => _watch(context, ref, u),
                            ),
                  ]),
                ),
              ),
            ));
          }
          walk(ch.id, depth + 1);
        }
      }
    }

    walk(0, 0);
    return ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: rows);
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
            final cs = Theme.of(context).colorScheme;
            final t = TimeOfDay.fromDateTime(m.time).format(context);
            return Align(
              alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: m.isMe ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(m.isMe ? 18 : 4),
                    bottomRight: Radius.circular(m.isMe ? 4 : 18),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!m.isMe)
                      Flexible(
                        child: Text(m.sender,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: HSLColor.fromColor(_avatarColor(m.sender))
                                    .withLightness(Theme.of(context).brightness == Brightness.dark ? 0.72 : 0.32)
                                    .toColor())),
                      ),
                    if (!m.isMe) const SizedBox(width: 8),
                    Text(t, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 2),
                  BbText(m.text),
                ]),
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
