import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Small BBCode renderer: [b] [i] [u] [s] [color=] [size=] [url] [url=] [img] [code] [center].
/// Unknown tags are shown as text; unclosed tags are closed at the end.
class BbCode {
  static final _tag = RegExp(r'\[(/?)([a-zA-Z]+)(?:=([^\]]*))?\]');
  static final _bare = RegExp(r'(https?://[^\s\[\]<>]+)');
  static const _known = {'b', 'i', 'u', 's', 'color', 'size', 'url', 'img', 'code', 'center', 'left', 'right'};

  /// Disposable recognizers are collected here; the caller disposes them.
  static TextSpan build(String src, TextStyle base, Color linkColor, List<GestureRecognizer> sink) {
    final stack = <(String, String?)>[];
    final spans = <InlineSpan>[];

    TextStyle style() {
      var st = base;
      for (final (t, a) in stack) {
        switch (t) {
          case 'b':
            st = st.copyWith(fontWeight: FontWeight.bold);
          case 'i':
            st = st.copyWith(fontStyle: FontStyle.italic);
          case 'u':
            st = st.copyWith(decoration: _deco(st, TextDecoration.underline));
          case 's':
            st = st.copyWith(decoration: _deco(st, TextDecoration.lineThrough));
          case 'color':
            final c = _color(a);
            if (c != null) st = st.copyWith(color: c);
          case 'size':
            final n = double.tryParse(a ?? '');
            if (n != null) st = st.copyWith(fontSize: (base.fontSize ?? 14) * (n / 10).clamp(0.6, 2.5));
          case 'code':
            st = st.copyWith(fontFamily: 'monospace');
        }
      }
      return st;
    }

    void link(String text, String url) {
      final r = TapGestureRecognizer()..onTap = () => _open(url);
      sink.add(r);
      spans.add(TextSpan(
        text: text,
        style: style().copyWith(color: linkColor, decoration: TextDecoration.underline),
        recognizer: r,
      ));
    }

    void text(String t) {
      if (t.isEmpty) return;
      final inUrl = stack.any((e) => e.$1 == 'url' || e.$1 == 'img');
      if (inUrl) {
        spans.add(TextSpan(text: t, style: style()));
        return;
      }
      var pos = 0;
      for (final m in _bare.allMatches(t)) {
        if (m.start > pos) spans.add(TextSpan(text: t.substring(pos, m.start), style: style()));
        link(m.group(0)!, m.group(0)!);
        pos = m.end;
      }
      if (pos < t.length) spans.add(TextSpan(text: t.substring(pos), style: style()));
    }

    var pos = 0;
    for (final m in _tag.allMatches(src)) {
      final closing = m.group(1) == '/';
      final name = m.group(2)!.toLowerCase();
      if (!_known.contains(name)) continue;
      // [url]..[/url] and [img]..[/img] need their content as the target.
      text(src.substring(pos, m.start));
      pos = m.end;
      if (!closing) {
        if (name == 'url' || name == 'img') {
          final end = src.toLowerCase().indexOf('[/$name]', pos);
          if (end >= 0) {
            final inner = src.substring(pos, end);
            final target = m.group(3) ?? inner;
            link(name == 'img' ? '[img] $inner' : inner, target.trim());
            pos = end + name.length + 3;
            continue;
          }
        }
        stack.add((name, m.group(3)));
      } else {
        final i = stack.lastIndexWhere((e) => e.$1 == name);
        if (i >= 0) stack.removeRange(i, stack.length);
      }
    }
    text(src.substring(pos));
    return TextSpan(children: spans, style: base);
  }

  static TextDecoration _deco(TextStyle st, TextDecoration add) =>
      TextDecoration.combine([if (st.decoration != null) st.decoration!, add]);

  static Color? _color(String? v) {
    if (v == null) return null;
    final h = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
    if (h != null) return Color(0xFF000000 | int.parse(h.group(1)!, radix: 16));
    const named = {
      'red': Colors.red, 'green': Colors.green, 'blue': Colors.blue, 'yellow': Colors.yellow,
      'orange': Colors.orange, 'purple': Colors.purple, 'white': Colors.white, 'black': Colors.black,
      'gray': Colors.grey, 'grey': Colors.grey, 'pink': Colors.pink, 'cyan': Colors.cyan,
    };
    return named[v.trim().toLowerCase()];
  }

  static Future<void> _open(String url) async {
    var u = url;
    if (!u.contains('://')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Selectable-free rich text that owns its tap recognizers.
class BbText extends StatefulWidget {
  final String text;
  const BbText(this.text, {super.key});

  @override
  State<BbText> createState() => _BbTextState();
}

class _BbTextState extends State<BbText> {
  final _rec = <GestureRecognizer>[];

  void _free() {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _free();
    final base = DefaultTextStyle.of(context).style.merge(Theme.of(context).textTheme.bodyMedium);
    return Text.rich(BbCode.build(widget.text, base, Theme.of(context).colorScheme.primary, _rec));
  }
}
