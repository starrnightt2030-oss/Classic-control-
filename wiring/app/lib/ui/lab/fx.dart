import 'dart:math' as math;
import 'dart:ui';

/// Sparks and smoke shown where a short, an overload or a burnt part happens.
class Particle {
  Offset p;
  Offset v;
  double life; // seconds left
  final double max;
  final bool smoke;
  final double size;
  Particle(this.p, this.v, this.life, this.smoke, this.size) : max = life;
}

class Fx {
  final List<Particle> items = [];
  final _r = math.Random();
  /// seconds of smoke still to emit, per board point
  final Map<Offset, double> _smokers = {};

  bool get busy => items.isNotEmpty || _smokers.isNotEmpty;

  void sparks(Offset at, {int n = 40}) {
    for (var i = 0; i < n; i++) {
      final a = _r.nextDouble() * math.pi * 2;
      final s = 80 + _r.nextDouble() * 260;
      items.add(Particle(at, Offset(math.cos(a) * s, math.sin(a) * s - 60), .25 + _r.nextDouble() * .5, false, 1 + _r.nextDouble() * 2));
    }
  }

  void smoke(Offset at, {double seconds = 2.5}) => _smokers[at] = seconds;

  void step(double dt) {
    for (final k in _smokers.keys.toList()) {
      final left = _smokers[k]! - dt;
      if (left <= 0) {
        _smokers.remove(k);
      } else {
        _smokers[k] = left;
        if (_r.nextDouble() < dt * 22) {
          items.add(Particle(k + Offset(_r.nextDouble() * 16 - 8, 0), Offset(_r.nextDouble() * 20 - 10, -30 - _r.nextDouble() * 25), 1.6 + _r.nextDouble(), true, 8 + _r.nextDouble() * 6));
        }
      }
    }
    for (final p in items) {
      p.life -= dt;
      p.p += p.v * dt;
      if (p.smoke) {
        p.v = Offset(p.v.dx + (_r.nextDouble() - .5) * 30 * dt, p.v.dy * (1 - dt * .3));
      } else {
        p.v = Offset(p.v.dx * (1 - dt * 2), p.v.dy + 500 * dt);
      }
    }
    items.removeWhere((p) => p.life <= 0);
  }

  void paint(Canvas c) {
    for (final p in items) {
      final k = (p.life / p.max).clamp(0.0, 1.0);
      if (p.smoke) {
        final r = p.size * (1 + (1 - k) * 2.2);
        c.drawCircle(p.p, r, Paint()
          ..color = Color.fromARGB((90 * k).round(), 70, 70, 74)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .5));
      } else {
        final tail = p.v * .025;
        c.drawLine(p.p, p.p - tail, Paint()
          ..color = Color.lerp(const Color(0xFFFFFFE0), const Color(0xFFFF9A1F), 1 - k)!.withValues(alpha: k)
          ..strokeWidth = p.size
          ..strokeCap = StrokeCap.round);
      }
    }
  }
}
