import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'shell.dart';

/// Animated intro built on the splash artwork: the house fades in, the bulb
/// flickers on with a spark, a shine runs over the title, the bar loads.
class SplashPage extends StatefulWidget {
  const SplashPage();
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _a.forward();
    _a.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
    Future.delayed(const Duration(milliseconds: 150), Sound.intro);
  }

  void _go() {
    if (_gone || !mounted) return;
    _gone = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => const Shell(),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ));
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.navy0,
      body: GestureDetector(
        onTap: _go,
        child: AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final t = _a.value * 3.8; // seconds
            final enter = Curves.easeOutCubic.transform(_seg(t, 0, 1.0));
            return LayoutBuilder(builder: (context, box) {
              const ar = 780 / 1380;
              var h = box.maxHeight;
              var w = h * ar;
              if (w > box.maxWidth) {
                w = box.maxWidth;
                h = w / ar;
              }
              return Stack(fit: StackFit.expand, children: [
                // blurred copy fills the sides on wide screens
                Opacity(
                  opacity: .55 * enter,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Image.asset('assets/images/splash_full.webp', fit: BoxFit.cover),
                  ),
                ),
                Container(color: C.navy0.withValues(alpha: .35)),
                Center(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Opacity(
                      opacity: enter,
                      child: Transform.scale(
                        scale: 1.06 - .06 * enter,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.asset('assets/images/splash_full.webp', fit: BoxFit.fill),
                          CustomPaint(painter: _FxPainter(t)),
                        ]),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 26,
                  child: Opacity(
                    opacity: _seg(t, 1.4, 2.0),
                    child: Column(children: [
                      SizedBox(
                        width: math.min(280, box.maxWidth * .7),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(children: [
                            Container(height: 7, color: Colors.white.withValues(alpha: .12)),
                            FractionallySizedBox(
                              widthFactor: Curves.easeInOut.transform(_seg(t, 1.4, 3.6)),
                              child: Container(height: 7, decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.gold, C.goldHi]), boxShadow: [BoxShadow(color: C.gold, blurRadius: 10)])),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(t < 2.6 ? 'جاري تجهيز اللوحة والمكونات...' : 'جاهز!', style: const TextStyle(color: C.dim, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('تطوير ${AppInfo.developer}  •  الإصدار ${AppInfo.version}', style: TextStyle(color: C.dim, fontSize: 11)),
                    ]),
                  ),
                ),
              ]);
            });
          },
        ),
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  final double t;
  _FxPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    // bulb: flicker on around 1.2 s (in time with the spark in the intro sound)
    final bulb = Offset(s.width * .395, s.height * .44);
    double glow;
    if (t < 1.15) {
      glow = 0;
    } else if (t < 1.5) {
      final k = ((t - 1.15) * 40).floor();
      glow = (k % 3 == 0) ? .25 : .9;
    } else {
      glow = .85 + .15 * math.sin(t * 6);
    }
    if (glow > 0) {
      final r = s.width * .23;
      canvas.drawCircle(bulb, r, Paint()..shader = RadialGradient(colors: [const Color(0xFFFFF1B0).withValues(alpha: .75 * glow), const Color(0xFFFFC53A).withValues(alpha: .28 * glow), Colors.transparent], stops: const [0, .35, 1]).createShader(Rect.fromCircle(center: bulb, radius: r)));
    }
    // spark burst at the bolt under the title
    final bolt = Offset(s.width * .5, s.height * .79);
    if (t > 1.15 && t < 2.2) {
      final k = (t - 1.15) / 1.05;
      final rnd = math.Random(4);
      final p = Paint()..strokeCap = StrokeCap.round;
      for (var i = 0; i < 26; i++) {
        final ang = rnd.nextDouble() * math.pi * 2;
        final sp = 30 + rnd.nextDouble() * 70;
        final d = sp * k * s.width / 390;
        final a = Offset(math.cos(ang), math.sin(ang) + k * .6);
        final o = bolt + a * d;
        p
          ..color = Color.lerp(const Color(0xFFFFF6C8), C.gold, k)!.withValues(alpha: 1 - k)
          ..strokeWidth = 2.2 * (1 - k) + .4;
        canvas.drawLine(o, o - a * 6, p);
      }
      canvas.drawCircle(bolt, 30 * (1 - k), Paint()..color = Colors.white.withValues(alpha: .5 * (1 - k))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    }
    // shine sweeping across the title plate
    if (t > 1.7 && t < 2.6) {
      final k = (t - 1.7) / .9;
      final rect = Rect.fromLTWH(s.width * .05, s.height * .57, s.width * .9, s.height * .2);
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(30)));
      final x = rect.left - 120 + (rect.width + 240) * k;
      final path = Path()
        ..moveTo(x, rect.top)
        ..lineTo(x + 50, rect.top)
        ..lineTo(x + 10, rect.bottom)
        ..lineTo(x - 40, rect.bottom)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: .28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.restore();
    }
    // electric pulses along the blueprint corner
    final pulse = (t * .7) % 1;
    final c = Offset(s.width * (.55 + .4 * pulse), s.height * (.05 + .25 * pulse));
    canvas.drawCircle(c, 4, Paint()..color = C.glow.withValues(alpha: .8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(_FxPainter o) => o.t != t;
}
