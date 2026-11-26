import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'perf.dart';

/// «Glass Navy» — deep navy, electric blue, frosted glass (v2.3). See v2/design/README.md.
///
/// `amber*` keeps its old name for the primary accent (now electric blue) so every screen
/// switches at once; warnings use `gold*`.
class CC {
  static const bg = Color(0xFF050914);
  static const bgTop = Color(0xFF0B1636);
  static const surface = Color(0xFF0D1630);
  static const surface2 = Color(0xFF14204A);
  static const stage = Color(0xFF081024);
  static const nav = Color(0xD90A1226);
  static const line = Color(0xFF1D2B52);
  static const line2 = Color(0xFF2B3F73);
  static const text = Color(0xFFEAF1FF);
  static const text2 = Color(0xFFC3D0EA);
  static const muted = Color(0xFF8798BF);

  // primary accent: electric blue
  static const amber = Color(0xFF3D8BFF);
  static const amberBg = Color(0xFF0F2150);
  static const amberLine = Color(0xFF2A57B0);
  static const accentSoft = Color(0xFF8FB8FF);

  static const cyan = Color(0xFF4FD8FF);
  static const cyanBg = Color(0xFF0A2340);
  static const cyanLine = Color(0xFF1B4E78);
  static const green = Color(0xFF35E08A);
  static const red = Color(0xFFFF5A64);

  // warnings / safety
  static const gold = Color(0xFFF5B83D);
  static const goldBg = Color(0xFF221A0A);
  static const goldLine = Color(0xFF55421A);

  static const glassTop = Color(0x1AFFFFFF);
  static const glassBottom = Color(0x08FFFFFF);
  static const glassBorder = Color(0x26A9C8FF);

  static const mono = 'JetBrainsMono';

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: amber, brightness: Brightness.dark).copyWith(
      primary: amber,
      onPrimary: Colors.white,
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
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: bg,
      dividerColor: line,
      splashFactory: InkRipple.splashFactory,
    );
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(99));
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text, fontFamily: 'Cairo'),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: const TextStyle(fontFamily: 'Cairo', color: text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: line2)),
      ),
      sliderTheme: const SliderThemeData(activeTrackColor: amber, thumbColor: Colors.white, inactiveTrackColor: line2, overlayColor: Color(0x333D8BFF)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: Colors.white,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: text, side: const BorderSide(color: line2), shape: pill),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accentSoft, shape: pill)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? amber : surface2),
        trackOutlineColor: WidgetStateProperty.all(line2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: amber, width: 1.4)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: line2)),
      ),
      pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const _BackdropTransitions()}),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      ),
    );
  }
}

/// Frosted-glass panel. Pass [color] for a tinted (opaque) panel instead of glass.
BoxDecoration panelBox({Color color = CC.surface, double radius = 18, Color border = CC.line}) {
  final glass = color == CC.surface;
  return BoxDecoration(
    color: glass ? null : color,
    gradient: glass
        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [CC.glassTop, CC.glassBottom])
        : null,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: glass && border == CC.line ? CC.glassBorder : border),
  );
}

/// Soft blue glow under highlighted elements.
List<BoxShadow> glow([Color c = CC.amber, double strength = 1]) => [
      BoxShadow(color: c.withValues(alpha: 0.38 * strength), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
    ];

/// Real blurred glass for floating bars and overlays (use sparingly: BackdropFilter is costly).
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color tint;
  const Glass({super.key, required this.child, this.radius = 24, this.padding = EdgeInsets.zero, this.blur = 18, this.tint = const Color(0x990C1530)});

  @override
  Widget build(BuildContext context) {
    // a panel that is nearly opaque shows no blur anyway; on big desktop touch screens
    // (Perf.lite) the blur over a live, repainting sheet is the costliest thing on screen
    final opaque = tint.a >= 0.85;
    if (Perf.lite || opaque) {
      // a Material, not a coloured box, so list tiles inside keep their ink splashes
      return Material(
        color: opaque ? tint : Color.alphaBlend(tint, const Color(0xF20A1124)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: const BorderSide(color: CC.glassBorder)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: CC.glassBorder),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)]),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// App-wide background: deep navy gradient with two soft light blooms.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [CC.bgTop, CC.bg], stops: [0, 0.62]),
          ),
        ),
      ),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: Alignment(0.9, -1.0), radius: 0.9, colors: [Color(0x403D8BFF), Color(0x003D8BFF)]),
          ),
        ),
      ),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: Alignment(-1.0, 0.85), radius: 0.8, colors: [Color(0x2E6A4BFF), Color(0x006A4BFF)]),
          ),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}

/// Every route paints the navy backdrop under its page (pages use transparent scaffolds).
class _BackdropTransitions extends PageTransitionsBuilder {
  const _BackdropTransitions();
  static const _inner = ZoomPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      _inner.buildTransitions(route, context, animation, secondaryAnimation, AppBackdrop(child: child));
}
