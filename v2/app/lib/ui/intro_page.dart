import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/audio_service.dart';
import 'shell.dart';
import 'theme.dart';

/// The intro, drawn live (no video, no web view, so it looks the same on every
/// platform). A start/stop circuit draws itself on a blueprint, S1 is pressed, the
/// contactor pulls in, current runs through the control path and the motor runs up.
/// Then the drawing folds away into the logo, the name, and the credits.
/// The soundtrack (assets/audio/sfx/intro_theme.mp3, made by audio/sfx_real.py)
/// follows the same timeline.
class IntroPage extends StatefulWidget {
  /// open this page instead of the app when the intro ends (tests)
  final Widget? next;
  const IntroPage({super.key, this.next});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

/// the intro's timeline, in seconds
class IntroTimes {
  static const draw = 1.9, press = 1.9, pull = 2.1, motorUp = 2.15, hit = 3.7, title = 4.4, credits = 5.1, end = 8.0;
}

class _IntroPageState extends State<IntroPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: (IntroTimes.end * 1000).round()));
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    // start with the first frame so picture and sound begin together
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AudioService.instance.playIntro();
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _finish() {
    if (_left || !mounted) return;
    _left = true;
    AudioService.instance.stopIntro();
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, __, ___) => widget.next ?? const Shell(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
      ),
    ));
  }

  /// 0…1 progress of a part of the timeline that starts at [a] and lasts [d] seconds
  static double seg(double t, double a, double d, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / d).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040812),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _finish,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * IntroTimes.end;
            final size = MediaQuery.sizeOf(context);
            final logoW = math.min(size.shortestSide * 0.44, 340.0);
            final hit = seg(t, IntroTimes.hit, 1.1, Curves.easeOutBack);
            final title = seg(t, IntroTimes.title, 0.9);
            final credits = seg(t, IntroTimes.credits, 0.8);
            return Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: IntroPainter(t)),
              // logo
              Align(
                alignment: const Alignment(0, -0.22),
                child: Opacity(
                  opacity: seg(t, IntroTimes.hit, 0.45),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX((1 - hit) * 0.7)
                      ..scaleByDouble(0.55 + 0.45 * hit, 0.55 + 0.45 * hit, 1, 1),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: const Color(0xFFF5A400).withValues(alpha: 0.28 * hit), blurRadius: 60, spreadRadius: 6),
                      ]),
                      child: Image.asset('assets/images/logo.webp', width: logoW, errorBuilder: (_, __, ___) => SizedBox(width: logoW, height: logoW)),
                    ),
                  ),
                ),
              ),
              // name
              Align(
                alignment: const Alignment(0, 0.42),
                child: Opacity(
                  opacity: title,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - title)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(AppInfo.brandAr,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: math.min(size.width * 0.066, 34), color: const Color(0xFFEAF1FF), height: 1.3)),
                      Text(AppInfo.product.toUpperCase(),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontFamily: 'Cairo', fontSize: math.min(size.width * 0.036, 17), color: const Color(0xFFF5B400), letterSpacing: 2 + 4 * (1 - title))),
                      const SizedBox(height: 10),
                      Container(
                        height: 2,
                        width: math.min(size.width * 0.7, 420) * seg(t, IntroTimes.title + 0.5, 0.9),
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.transparent, Color(0xFF3FD5E8), Color(0xFFF5A400), Color(0xFF3FD5E8), Colors.transparent])),
                      ),
                    ]),
                  ),
                ),
              ),
              // credits
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 18,
                child: Opacity(
                  opacity: credits,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - credits)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        ClipOval(child: Image.asset(AppInfo.orgLogo, width: 40, height: 40, errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40))),
                        const SizedBox(width: 10),
                        const Flexible(
                            child: Text(AppInfo.organization,
                                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFC9D4DB)), overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 6),
                      const Text('تطوير: ${AppInfo.developer}', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFFE8EEF2))),
                      const Text('الإصدار ${AppInfo.version} · ${AppInfo.build}', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF93A3AF))),
                    ]),
                  ),
                ),
              ),
              PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + 10,
                end: 14,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: CC.text2,
                    backgroundColor: const Color(0x66000000),
                    minimumSize: const Size(64, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('تخطي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// The blueprint and the start/stop circuit at time [t] (seconds).
class IntroPainter extends CustomPainter {
  final double t;
  IntroPainter(this.t);

  static const _cyan = Color(0xFF3FD5E8), _amber = Color(0xFFF5A400), _ink = Color(0xFF7FA6D6);

  double _seg(double a, double d, [Curve c = Curves.easeOutCubic]) => _IntroPageState.seg(t, a, d, c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
        r,
        Paint()
          ..shader = const RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [Color(0xFF0E1C38), Color(0xFF040812)]).createShader(r));
    // blueprint dots
    final grid = Paint()..color = const Color(0xFF1A2E52).withValues(alpha: 0.7 * _seg(0, 0.8));
    for (var x = 11.0; x < size.width; x += 22) {
      for (var y = 11.0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 0.9, grid);
      }
    }
    final fold = _seg(IntroTimes.hit - 0.3, 0.7, Curves.easeInCubic);
    if (fold < 1) _circuit(canvas, size, fold);
    // the hit: flash and an expanding ring of energy
    if (t >= IntroTimes.hit - 0.05) {
      final k = _seg(IntroTimes.hit - 0.05, 1.2);
      final c = Offset(size.width / 2, size.height * 0.39);
      final f = 1 - _seg(IntroTimes.hit, 0.8);
      canvas.drawCircle(c, size.longestSide * 0.6, Paint()..shader = RadialGradient(colors: [const Color(0xFFFFECBE).withValues(alpha: 0.85 * f), Colors.transparent], stops: const [0, 0.55]).createShader(Rect.fromCircle(center: c, radius: size.longestSide * 0.6)));
      canvas.drawCircle(
          c,
          size.shortestSide * (0.12 + 0.6 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - k) + 0.5
            ..color = _cyan.withValues(alpha: 0.6 * (1 - k)));
      final glow = _seg(IntroTimes.hit, 1.4);
      canvas.drawCircle(c, size.shortestSide * 0.42, Paint()..shader = RadialGradient(colors: [_amber.withValues(alpha: 0.32 * glow), _cyan.withValues(alpha: 0.10 * glow), Colors.transparent], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: size.shortestSide * 0.42)));
    }
  }

  void _circuit(Canvas canvas, Size size, double fold) {
    // a 20 × 14 drawing, centred, folding into the logo's place at the hit
    final u = math.min(size.width / 22, size.height / 22);
    final o = Offset(size.width / 2 - 10 * u, size.height * 0.4 - 7 * u);
    canvas.save();
    final c = Offset(size.width / 2, size.height * 0.39);
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 - 0.75 * fold);
    canvas.translate(-c.dx, -c.dy);
    Offset p(double x, double y) => o + Offset(x * u, y * u);
    final alpha = 1 - fold;

    // the drawing, in stroke order: control rails, control path, power path, motor
    final control = <List<Offset>>[
      [p(10, 0), p(19, 0)], // L
      [p(10, 14), p(19, 14)], // N
      [p(17, 0), p(17, 2.2)], // to S0
      [p(17, 3.8), p(17, 5.2)], // S0 → S1
      [p(17, 6.8), p(17, 9.6)], // S1 → coil
      [p(17, 11.4), p(17, 14)], // coil → N
    ];
    final power = <List<Offset>>[
      for (final x in [2.0, 4.0, 6.0]) [p(x, 0), p(x, 4.2)],
      for (final x in [2.0, 4.0, 6.0]) [p(x, 5.8), p(x, 8.6)],
    ];
    final strokes = [...control, ...power];
    var total = 0.0;
    for (final s in strokes) {
      total += (s[1] - s[0]).distance;
    }
    final drawn = _seg(0.15, IntroTimes.draw - 0.35, Curves.easeInOut) * total;
    final inkP = Paint()
      ..color = _ink.withValues(alpha: alpha)
      ..strokeWidth = math.max(1.4, u * 0.11)
      ..strokeCap = StrokeCap.round;
    var left = drawn;
    Offset? pen;
    for (final s in strokes) {
      final len = (s[1] - s[0]).distance;
      if (left <= 0) break;
      final k = math.min(1.0, left / len);
      final end = Offset.lerp(s[0], s[1], k)!;
      canvas.drawLine(s[0], end, inkP);
      if (k < 1) pen = end;
      left -= len;
    }
    final symbols = _seg(0.5, 1.2);
    final symP = Paint()
      ..color = _ink.withValues(alpha: alpha * symbols)
      ..strokeWidth = math.max(1.4, u * 0.11)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pressed = t >= IntroTimes.press;
    final pulled = t >= IntroTimes.pull;
    // S0 (NC stop)
    canvas.drawLine(p(17, 2.2), p(17.9, 3.8), symP);
    canvas.drawLine(p(17.9, 3.2), p(17, 3.2), symP);
    // S1 (NO start): closes when pressed
    canvas.drawLine(p(17, 5.2), pressed ? p(17, 6.8) : p(16.1, 6.6), symP);
    canvas.drawLine(p(16.4, 6.0), p(15.6, 6.0), symP);
    _label(canvas, 'S1', p(18.2, 6.0), u, alpha * symbols);
    _label(canvas, 'S0', p(18.4, 3.0), u, alpha * symbols);
    // K1 coil
    final coilR = Rect.fromLTRB(p(16.2, 9.6).dx, p(16.2, 9.6).dy, p(17.8, 11.4).dx, p(17.8, 11.4).dy);
    if (pulled) {
      canvas.drawRect(coilR, Paint()..color = _amber.withValues(alpha: 0.85 * alpha * _seg(IntroTimes.pull, 0.25)));
    }
    canvas.drawRect(coilR, symP);
    _label(canvas, 'K1', p(19.0, 10.5), u, alpha * symbols);
    // K1 main contacts (three poles, linked)
    for (final x in [2.0, 4.0, 6.0]) {
      canvas.drawLine(p(x, 4.2), pulled ? p(x, 5.8) : p(x - 0.9, 5.6), symP);
    }
    final dash = Paint()
      ..color = _ink.withValues(alpha: 0.6 * alpha * symbols)
      ..strokeWidth = 1;
    canvas.drawLine(p(pulled ? 2 : 1.5, 5.0), p(pulled ? 6.6 : 6.1, 5.0), dash);
    _label(canvas, 'K1', p(7.6, 5.0), u, alpha * symbols);
    _label(canvas, 'L1  L2  L3', p(4.0, -0.9), u, alpha * symbols);
    _label(canvas, 'L', p(10.6, -0.9), u, alpha * symbols);
    _label(canvas, 'N', p(10.6, 14.9), u, alpha * symbols);
    // motor
    final mc = p(4, 10.6), mr = 2.0 * u;
    canvas.drawCircle(mc, mr, symP);
    canvas.drawLine(p(2, 8.6), mc + Offset(-mr * 0.75, -mr * 0.65), symP);
    canvas.drawLine(p(4, 8.6), mc + Offset(0, -mr), symP);
    canvas.drawLine(p(6, 8.6), mc + Offset(mr * 0.75, -mr * 0.65), symP);
    _label(canvas, 'M\n3~', mc, u * 1.1, alpha * symbols);

    // current: control path from S1 on, then the power path
    if (pressed) {
      final k = _seg(IntroTimes.press, 0.35);
      final path = Path()
        ..moveTo(p(17, 0).dx, p(17, 0).dy)
        ..lineTo(p(17, 0).dx, p(17, 0).dy + (p(17, 14).dy - p(17, 0).dy) * k);
      _current(canvas, path, u, _amber, alpha);
    }
    if (pulled) {
      final k = _seg(IntroTimes.pull + 0.05, 0.4);
      for (final x in [2.0, 4.0, 6.0]) {
        final path = Path()
          ..moveTo(p(x, 0).dx, p(x, 0).dy)
          ..lineTo(p(x, 0).dx, p(x, 0).dy + (p(x, 8.6).dy - p(x, 0).dy) * k);
        _current(canvas, path, u, _cyan, alpha);
      }
      // rotor: three blades turning faster as the motor runs up
      final ms = t - IntroTimes.motorUp;
      if (ms > 0) {
        final ang = 2 * math.pi * (ms * 3.2 - (1 - math.exp(-ms * 2.4)) * 3.2 / 2.4) * 1.0;
        final rp = Paint()
          ..color = _cyan.withValues(alpha: 0.75 * alpha)
          ..strokeWidth = math.max(1.5, u * 0.14)
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final a = ang + i * 2 * math.pi / 3;
          canvas.drawLine(mc, mc + Offset(math.cos(a), math.sin(a)) * mr * 0.72, rp);
        }
        canvas.drawCircle(mc, mr * 1.25, Paint()..shader = RadialGradient(colors: [_cyan.withValues(alpha: 0.25 * alpha * _seg(IntroTimes.motorUp, 1.0)), Colors.transparent]).createShader(Rect.fromCircle(center: mc, radius: mr * 1.25)));
      }
    }
    // the pen's glowing tip while drawing
    if (pen != null) {
      canvas.drawCircle(pen, u * 0.55, Paint()..color = _cyan.withValues(alpha: 0.25));
      canvas.drawCircle(pen, u * 0.18, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  /// moving dashes of current along [path], with a soft glow
  void _current(Canvas canvas, Path path, double u, Color col, double alpha) {
    canvas.drawPath(
        path,
        Paint()
          ..color = col.withValues(alpha: 0.35 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.45
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    final dash = Paint()
      ..color = col.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, u * 0.13)
      ..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      final step = u * 0.9, off = (t * u * 6) % step;
      for (var d = off; d < m.length; d += step) {
        canvas.drawPath(m.extractPath(d, math.min(m.length, d + step * 0.45)), dash);
      }
    }
  }

  void _label(Canvas canvas, String s, Offset at, double u, double alpha) {
    if (alpha <= 0.01) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: math.max(9, u * 0.62), color: _ink.withValues(alpha: alpha), height: 1.05, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant IntroPainter old) => old.t != t;
}
