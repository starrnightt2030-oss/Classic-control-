import 'package:flutter/material.dart';

/// Visual identity: deep navy, electric blue glow and gold.
class C {
  static const navy0 = Color(0xFF06122E);
  static const navy1 = Color(0xFF0A2563);
  static const navy2 = Color(0xFF123C8C);
  static const card = Color(0xFF0C2A66);
  static const cardHi = Color(0xFF14408F);
  static const glow = Color(0xFF6EAAFF);
  static const gold = Color(0xFFF6B91A);
  static const goldHi = Color(0xFFFFD66B);
  static const text = Color(0xFFF2F6FF);
  static const dim = Color(0xFFA9BCE6);
  static const ok = Color(0xFF3DDC84);
  static const bad = Color(0xFFFF5A5F);
  static const warn = Color(0xFFFFA43A);
  static const board = Color(0xFFE9E4D8); // the plywood training board
  static const boardDark = Color(0xFFCFC7B4);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Cairo',
    colorScheme: ColorScheme.fromSeed(seedColor: C.navy2, brightness: Brightness.dark, primary: C.gold, secondary: C.glow, surface: C.navy1),
    scaffoldBackgroundColor: C.navy0,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text, fontFamily: 'Cairo'),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true, foregroundColor: C.text,
        titleTextStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 19, color: C.text)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: C.cardHi, contentTextStyle: TextStyle(fontFamily: 'Cairo', color: C.text)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: C.navy0, textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
    dialogTheme: const DialogThemeData(backgroundColor: C.navy1),
    sliderTheme: const SliderThemeData(activeTrackColor: C.gold, thumbColor: C.goldHi),
  );
}

/// Radial navy background used behind every page.
class NavyBackground extends StatelessWidget {
  final Widget child;
  const NavyBackground({required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.7), radius: 1.3, colors: [C.navy2, C.navy1, C.navy0], stops: [0, .45, 1]),
        ),
        child: child,
      );
}

/// Card with the blue glowing border of the identity.
BoxDecoration glowCard({double r = 18, bool hi = false, Color? border}) => BoxDecoration(
      borderRadius: BorderRadius.circular(r),
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: hi ? [C.cardHi, C.card] : [const Color(0xFF103578), const Color(0xFF0A2257)]),
      border: Border.all(color: border ?? C.glow.withValues(alpha: .55), width: 1.2),
      boxShadow: [BoxShadow(color: (border ?? C.glow).withValues(alpha: .25), blurRadius: 14, spreadRadius: -2)],
    );

class GlowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? border;
  final double radius;
  const GlowCard({required this.child, this.onTap, this.padding = const EdgeInsets.all(12), this.border, this.radius = 18});
  @override
  Widget build(BuildContext context) => Container(
        decoration: glowCard(border: border, r: radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

class GoldText extends StatelessWidget {
  final String text;
  final double size;
  const GoldText(this.text, {this.size = 20});
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [C.goldHi, C.gold, Color(0xFFE39A00)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
        child: Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(children: [
          Container(width: 4, height: 20, decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Page scaffold with the navy background and a title bar.
class PageFrame extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const PageFrame({required this.title, required this.body, this.actions});
  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: false,
        backgroundColor: C.navy0,
        appBar: AppBar(title: Text(title), actions: actions, flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.navy1, C.navy2])))),
        body: NavyBackground(child: body),
      );
}

/// Large layout for the 75" interactive board / desktop.
bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
