import 'package:flutter/material.dart';

class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.dim,
    required this.primary,
    required this.primaryInk,
    required this.accent,
    required this.onAccent,
    required this.green,
    required this.red,
    required this.amber,
    required this.mapSpot,
    required this.mapFood,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;
  final Color dim;
  final Color primary;
  final Color primaryInk;
  final Color accent;
  final Color onAccent;
  final Color green;
  final Color red;
  final Color amber;
  final Color mapSpot;
  final Color mapFood;

  static const light = SemanticColors(
    bg: Color(0xFFFFFAEE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFF3D6),
    line: Color(0xFFEAD9B2),
    text: Color(0xFF2B1D0E),
    muted: Color(0xFF6B5536),
    dim: Color(0xFF7A6040),
    primary: Color(0xFFF59E0B),
    primaryInk: Color(0xFF985000),
    accent: Color(0xFFF97316),
    onAccent: Color(0xFF2B1D0E),
    green: Color(0xFF047857),
    red: Color(0xFFB91C1C),
    amber: Color(0xFFB45309),
    mapSpot: Color(0xFF0284C7),
    mapFood: Color(0xFFE8590C),
  );

  static const dark = SemanticColors(
    bg: Color(0xFF0A1220),
    surface: Color(0xFF111B2E),
    surface2: Color(0xFF18243B),
    line: Color(0xFF2A3A58),
    text: Color(0xFFF0F9FF),
    muted: Color(0xFFA3B5CC),
    dim: Color(0xFF8497B0),
    primary: Color(0xFF38BDF8),
    primaryInk: Color(0xFF38BDF8),
    accent: Color(0xFFF97316),
    onAccent: Color(0xFF0A1220),
    green: Color(0xFF34D399),
    red: Color(0xFFF87171),
    amber: Color(0xFFFBBF24),
    mapSpot: Color(0xFF0284C7),
    mapFood: Color(0xFFE8590C),
  );

  @override
  SemanticColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? muted,
    Color? dim,
    Color? primary,
    Color? primaryInk,
    Color? accent,
    Color? onAccent,
    Color? green,
    Color? red,
    Color? amber,
    Color? mapSpot,
    Color? mapFood,
  }) {
    return SemanticColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      dim: dim ?? this.dim,
      primary: primary ?? this.primary,
      primaryInk: primaryInk ?? this.primaryInk,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      green: green ?? this.green,
      red: red ?? this.red,
      amber: amber ?? this.amber,
      mapSpot: mapSpot ?? this.mapSpot,
      mapFood: mapFood ?? this.mapFood,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryInk: Color.lerp(primaryInk, other.primaryInk, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      green: Color.lerp(green, other.green, t)!,
      red: Color.lerp(red, other.red, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      mapSpot: Color.lerp(mapSpot, other.mapSpot, t)!,
      mapFood: Color.lerp(mapFood, other.mapFood, t)!,
    );
  }
}

extension SemanticColorsExtension on BuildContext {
  SemanticColors get colors =>
      Theme.of(this).extension<SemanticColors>() ?? SemanticColors.light;
}
