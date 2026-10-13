import 'package:flutter/material.dart';

const Color tsSeed = Color(0xFF2E7DD1);

/// Semantic colours used across the UI: green = talking/ok, red = muted/error.
@immutable
class TsColors extends ThemeExtension<TsColors> {
  final Color talking;
  final Color muted;
  final Color away;
  const TsColors({required this.talking, required this.muted, required this.away});

  static TsColors of(BuildContext c) => Theme.of(c).extension<TsColors>()!;

  @override
  TsColors copyWith({Color? talking, Color? muted, Color? away}) =>
      TsColors(talking: talking ?? this.talking, muted: muted ?? this.muted, away: away ?? this.away);

  @override
  TsColors lerp(TsColors? other, double t) => other == null
      ? this
      : TsColors(
          talking: Color.lerp(talking, other.talking, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          away: Color.lerp(away, other.away, t)!);
}

/// [dynamic] is the Android wallpaper scheme when available; falls back to the seed.
ThemeData buildTheme(Brightness b, {ColorScheme? dynamic}) {
  final dark = b == Brightness.dark;
  var cs = dynamic ?? ColorScheme.fromSeed(seedColor: tsSeed, brightness: b);
  if (dark) {
    // OLED-style surfaces, keeping the accent colours of the scheme.
    cs = cs.copyWith(
      surface: const Color(0xFF000000),
      surfaceDim: const Color(0xFF000000),
      surfaceBright: const Color(0xFF2A2A2E),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF0B0B0D),
      surfaceContainer: const Color(0xFF111114),
      surfaceContainerHigh: const Color(0xFF18181C),
      surfaceContainerHighest: const Color(0xFF222226),
    );
  }
  final colors = TsColors(
    talking: dark ? const Color(0xFF3DDC84) : const Color(0xFF1B8A48),
    muted: dark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828),
    away: dark ? const Color(0xFFFFB74D) : const Color(0xFFB26A00),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.secondaryContainer,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant.withValues(alpha: 0.5)),
  );
}
