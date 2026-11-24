import 'package:flutter/material.dart';

/// «Graphite & Signal» — see v2/design/README.md
class CC {
  static const bg = Color(0xFF0B0F12);
  static const surface = Color(0xFF131A1F);
  static const surface2 = Color(0xFF1A232A);
  static const stage = Color(0xFF0F1519);
  static const nav = Color(0xFF0F1418);
  static const line = Color(0xFF26323C);
  static const line2 = Color(0xFF33414C);
  static const text = Color(0xFFE8EEF2);
  static const text2 = Color(0xFFC9D4DB);
  static const muted = Color(0xFF93A3AF);
  static const amber = Color(0xFFF5A400);
  static const amberBg = Color(0xFF2A2210);
  static const amberLine = Color(0xFF4A3A10);
  static const cyan = Color(0xFF3FD5E8);
  static const cyanBg = Color(0xFF0F2A2E);
  static const cyanLine = Color(0xFF1E4A52);
  static const green = Color(0xFF3DDC84);
  static const red = Color(0xFFFF5A4F);

  static const mono = 'JetBrainsMono';

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: amber,
      brightness: Brightness.dark,
    ).copyWith(
      primary: amber,
      onPrimary: bg,
      secondary: cyan,
      onSecondary: bg,
      surface: bg,
      onSurface: text,
      surfaceContainerHighest: surface2,
      outline: line,
      error: red,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: bg,
      dividerColor: line,
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text, fontFamily: 'Cairo'),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: TextStyle(fontFamily: 'Cairo', color: text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: const SliderThemeData(activeTrackColor: amber, thumbColor: amber, inactiveTrackColor: line),
    );
  }
}

BoxDecoration panelBox({Color color = CC.surface, double radius = 16, Color border = CC.line}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );
