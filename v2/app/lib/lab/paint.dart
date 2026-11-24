// Panel Lab drawing: plate, DIN rails, wire ducts, wires with ferrules, motor terminal plate.
// World unit = millimetre; the canvas is painted at [kPx] logical pixels per mm.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../sim/engine.dart';
import 'catalog.dart';
import 'model.dart';

const double kPx = 4.0;

// ------------------------------------------------------------------ routing
class WireRoute {
  final List<Offset> pts; // mm
  final Offset dirA, dirB; // unit vectors leaving each terminal
  const WireRoute(this.pts, this.dirA, this.dirB);
}

class WireRouter {
  final LabDoc doc;
  late final List<Rect> hDucts, vDucts;
  WireRouter(this.doc) {
    hDucts = [for (final p in doc.parts) if (p.def == 'duct_h') p.rect];
    vDucts = [for (final p in doc.parts) if (p.def == 'duct_v') p.rect];
  }

  Rect? _hDuct(Offset t, bool up) {
    Rect? best;
    var bd = double.infinity;
    for (final r in hDucts) {
      final inDir = up ? r.center.dy < t.dy : r.center.dy > t.dy;
      if (!inDir) continue;
      final dx = t.dx < r.left ? r.left - t.dx : (t.dx > r.right ? t.dx - r.right : 0.0);
      final d = (r.center.dy - t.dy).abs() + dx * 3;
      if (d < bd && (r.center.dy - t.dy).abs() < 260) {
        bd = d;
        best = r;
      }
    }
    return best;
  }

  Rect? _vDuct(double y1, double y2, double nearX) {
    Rect? best;
    var bd = double.infinity;
    final lo = math.min(y1, y2), hi = math.max(y1, y2);
    for (final r in vDucts) {
      if (r.top > lo + 30 || r.bottom < hi - 30) continue;
      final d = (r.center.dx - nearX).abs();
      if (d < bd) {
        bd = d;
        best = r;
      }
    }
    return best;
  }

  WireRoute route(LabWire w, int index) {
    final a = doc.termPos(w.a)!, b = doc.termPos(w.b)!;
    final upA = doc.termUp(w.a), upB = doc.termUp(w.b);
    final dA = Offset(0, upA ? -1 : 1), dB = Offset(0, upB ? -1 : 1);
    final lane = (((index * 7) % 11) - 5) * 2.4;
    final ha = _hDuct(a, upA), hb = _hDuct(b, upB);
    double inRange(Rect r, double x) => x.clamp(r.left + 6, r.right - 6).toDouble();
    if (ha != null && hb != null) {
      final ya = ha.center.dy + lane, yb = hb.center.dy + lane;
      if (ha == hb) {
        return WireRoute([a, Offset(a.dx, ya), Offset(b.dx, ya), b], dA, dB);
      }
      final v = _vDuct(ya, yb, (a.dx + b.dx) / 2);
      if (v != null) {
        final x = v.center.dx + lane;
        return WireRoute([a, Offset(a.dx, ya), Offset(x, ya), Offset(x, yb), Offset(b.dx, yb), b], dA, dB);
      }
      final xa = inRange(ha, b.dx);
      return WireRoute([a, Offset(a.dx, ya), Offset(xa, ya), Offset(xa, yb), Offset(b.dx, yb), b], dA, dB);
    }
    if (ha != null) {
      final ya = ha.center.dy + lane;
      final out = b + dB * 18;
      return WireRoute([a, Offset(a.dx, ya), Offset(inRange(ha, b.dx), ya), Offset(out.dx, out.dy), b], dA, dB);
    }
    if (hb != null) {
      final yb = hb.center.dy + lane;
      final out = a + dA * 18;
      return WireRoute([a, Offset(out.dx, out.dy), Offset(inRange(hb, a.dx), yb), Offset(b.dx, yb), b], dA, dB);
    }
    return WireRoute([a, b], dA, dB); // free wire: drawn as a soft curve
  }
}

Path wirePath(WireRoute r) {
  final p = Path();
  final pts = [for (final o in r.pts) o * kPx];
  p.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 2) {
    final a = pts.first, b = pts.last;
    final d = (b - a).distance;
    final k = math.max(40.0, math.min(220.0, d * 0.45));
    final c1 = a + r.dirA * k + Offset(0, d * 0.12);
    final c2 = b + r.dirB * k + Offset(0, d * 0.12);
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
    return p;
  }
  const rad = 16.0;
  for (var i = 1; i < pts.length - 1; i++) {
    final p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1];
    final v1 = p1 - p0, v2 = p2 - p1;
    final l1 = v1.distance, l2 = v2.distance;
    if (l1 < 0.5 || l2 < 0.5) {
      p.lineTo(p1.dx, p1.dy);
      continue;
    }
    final rr = math.min(rad, math.min(l1, l2) / 2);
    final s = p1 - v1 / l1 * rr, e = p1 + v2 / l2 * rr;
    p.lineTo(s.dx, s.dy);
    p.quadraticBezierTo(p1.dx, p1.dy, e.dx, e.dy);
  }
  p.lineTo(pts.last.dx, pts.last.dy);
  return p;
}

/// distance (mm) from point to a route (sampled)
double routeDistance(Path path, Offset mm) {
  final q = mm * kPx;
  var best = double.infinity;
  for (final m in path.computeMetrics()) {
    for (var t = 0.0; t <= m.length; t += 6) {
      final tg = m.getTangentForOffset(t);
      if (tg == null) continue;
      best = math.min(best, (tg.position - q).distance);
    }
  }
  return best / kPx;
}

// ------------------------------------------------------------------ plate + structure
class PlatePainter extends CustomPainter {
  final LabDoc doc;
  final String? selected;
  PlatePainter(this.doc, this.selected);

  @override
  void paint(Canvas c, Size size) {
    final plate = Rect.fromLTWH(0, 0, doc.plateW * kPx, doc.plateH * kPx);
    final rr = RRect.fromRectAndRadius(plate, const Radius.circular(18));
    c.drawShadow(Path()..addRRect(rr), Colors.black, 18, false);
    c.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD5D9DD), Color(0xFFB9BEC3), Color(0xFFCDD1D5)])
              .createShader(plate));
    // zinc spangle hint
    final sp = Paint()..color = const Color(0x10FFFFFF);
    final rnd = math.Random(7);
    for (var i = 0; i < 260; i++) {
      final x = rnd.nextDouble() * plate.width, y = rnd.nextDouble() * plate.height;
      c.drawCircle(Offset(x, y), 10 + rnd.nextDouble() * 40, sp);
    }
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF8E959B));
    for (final o in [const Offset(14, 14), Offset(doc.plateW - 14, 14), Offset(14, doc.plateH - 14), Offset(doc.plateW - 14, doc.plateH - 14)]) {
      c.drawCircle(o * kPx, 5 * kPx, Paint()..color = const Color(0xFF7D848A));
      c.drawCircle(o * kPx, 3.2 * kPx, Paint()..color = const Color(0xFF3A4046));
    }
    for (final p in doc.parts) {
      if (p.def == 'din_rail') _rail(c, p.rect, p.id == selected);
      if (p.def == 'duct_h' || p.def == 'duct_v') _ductBase(c, p.rect, p.def == 'duct_v');
    }
  }

  void _rail(Canvas c, Rect r0, bool sel) {
    final r = Rect.fromLTWH(r0.left * kPx, r0.top * kPx, r0.width * kPx, r0.height * kPx);
    c.drawRect(r.shift(const Offset(0, 6)), Paint()..color = const Color(0x33000000));
    final lip = r.height * 0.14;
    final body = Rect.fromLTRB(r.left, r.top + lip, r.right, r.bottom - lip);
    final metal = Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF1F3F5), Color(0xFFAEB4BA), Color(0xFFE2E5E8), Color(0xFF9AA1A8)], stops: [0, .35, .6, 1])
          .createShader(body);
    c.drawRect(body, metal);
    c.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.top + lip), Paint()..color = const Color(0xFFDCE0E4));
    c.drawRect(Rect.fromLTRB(r.left, r.bottom - lip, r.right, r.bottom), Paint()..color = const Color(0xFFC3C8CD));
    final slot = Paint()..color = const Color(0xFF6A7178);
    for (var x = r.left + 12 * kPx; x < r.right - 12 * kPx; x += 25 * kPx) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, r.center.dy), width: 15 * kPx, height: 5.2 * kPx), Radius.circular(2.6 * kPx)), slot);
    }
    if (sel) _selBox(c, r);
  }

  static void _ductBase(Canvas c, Rect r0, bool vertical) {
    final r = Rect.fromLTWH(r0.left * kPx, r0.top * kPx, r0.width * kPx, r0.height * kPx);
    c.drawRect(r.shift(const Offset(0, 6)), Paint()..color = const Color(0x33000000));
    c.drawRect(r, Paint()..color = const Color(0xFF6F767D));
    c.drawRect(r.deflate(2.4 * kPx), Paint()..color = const Color(0xFF555C63));
  }

  static void _selBox(Canvas c, Rect r) {
    c.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(8)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF3D8BFF));
  }

  @override
  bool shouldRepaint(covariant PlatePainter old) => true;
}

/// Duct covers with comb fingers — painted over the wires so the bundle disappears inside.
void paintDuctCovers(Canvas c, LabDoc doc, String? selected) {
  for (final p in doc.parts) {
    if (p.def != 'duct_h' && p.def != 'duct_v') continue;
    final v = p.def == 'duct_v';
    final r = Rect.fromLTWH(p.x * kPx, p.y * kPx, p.size.width * kPx, p.size.height * kPx);
    final cover = Paint()
      ..shader = LinearGradient(
              begin: v ? Alignment.centerLeft : Alignment.topCenter,
              end: v ? Alignment.centerRight : Alignment.bottomCenter,
              colors: const [Color(0xF2A4ABB2), Color(0xF28F969D), Color(0xF2A0A7AE)])
          .createShader(r);
    final inner = v ? r.deflate(0).inflate(0) : r;
    // comb fingers on both long edges
    final finger = Paint()..color = const Color(0xFF8A9198);
    final gap = 7.0 * kPx, fw = 4.2 * kPx, depth = 6 * kPx;
    if (!v) {
      for (var x = r.left + 2; x < r.right - fw; x += gap) {
        c.drawRect(Rect.fromLTWH(x, r.top, fw, depth), finger);
        c.drawRect(Rect.fromLTWH(x, r.bottom - depth, fw, depth), finger);
      }
      final cv = Rect.fromLTRB(inner.left, inner.top + depth * 0.65, inner.right, inner.bottom - depth * 0.65);
      c.drawRRect(RRect.fromRectAndRadius(cv, const Radius.circular(6)), cover);
      c.drawLine(Offset(cv.left + 8, cv.center.dy), Offset(cv.right - 8, cv.center.dy), Paint()
        ..color = const Color(0x22FFFFFF)
        ..strokeWidth = 3);
    } else {
      for (var y = r.top + 2; y < r.bottom - fw; y += gap) {
        c.drawRect(Rect.fromLTWH(r.left, y, depth, fw), finger);
        c.drawRect(Rect.fromLTWH(r.right - depth, y, depth, fw), finger);
      }
      final cv = Rect.fromLTRB(inner.left + depth * 0.65, inner.top, inner.right - depth * 0.65, inner.bottom);
      c.drawRRect(RRect.fromRectAndRadius(cv, const Radius.circular(6)), cover);
    }
    if (p.id == selected) PlatePainter._selBox(c, r);
  }
}

// ------------------------------------------------------------------ wires
class WirePainter extends CustomPainter {
  final LabDoc doc;
  final int? selectedWire;
  final Nets? nets;
  final double phase; // animation 0..1 for live glow
  final String? pending;
  final Set<LabWire> faulty;
  late final WireRouter router = WireRouter(doc);
  WirePainter({required this.doc, this.selectedWire, this.nets, this.phase = 0, this.pending, this.faulty = const {}});

  @override
  void paint(Canvas c, Size size) {
    final numbers = doc.netNumbers();
    final paths = <Path>[];
    for (var i = 0; i < doc.wires.length; i++) {
      final w = doc.wires[i];
      if (doc.termPos(w.a) == null || doc.termPos(w.b) == null) {
        paths.add(Path());
        continue;
      }
      final r = router.route(w, i);
      final path = wirePath(r);
      paths.add(path);
      final col = wireColor(w.color);
      final thick = w.color == 'br' || w.color == 'bk' || w.color == 'gy' || w.color == 'ge' ? 2.6 * kPx : 2.0 * kPx;
      final live = nets != null && nets!.live(w.a);
      if (i == selectedWire) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick + 10
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xAA3D8BFF));
      }
      if (live) {
        final a = 0.25 + 0.25 * math.sin(phase * math.pi * 2);
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick + 7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..color = const Color(0xFFFFD54A).withValues(alpha: a));
      }
      // shadow, outline, body, specular
      c.drawPath(path.shift(const Offset(2.5, 4)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x40000000));
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick + 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(col.color, Colors.black, 0.55)!);
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = col.color);
      if (col.stripe != null) {
        for (final m in path.computeMetrics()) {
          for (var t = 0.0; t < m.length; t += 22) {
            c.drawPath(m.extractPath(t, math.min(t + 10, m.length)), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = thick
              ..color = col.stripe!);
          }
        }
      }
      c.drawPath(path.shift(const Offset(-0.8, -1.2)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick * 0.22
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.28));
    }
    paintDuctCovers(c, doc, null);
    // ferrules on top of everything at each end
    for (var i = 0; i < doc.wires.length; i++) {
      final w = doc.wires[i];
      for (final (t, up) in [(w.a, doc.termUp(w.a)), (w.b, doc.termUp(w.b))]) {
        final p = doc.termPos(t);
        if (p == null) continue;
        _ferrule(c, p * kPx, up, numbers[t] ?? 0, w.color);
      }
    }
  }

  void _ferrule(Canvas c, Offset at, bool up, int n, String col) {
    final dir = up ? -1.0 : 1.0;
    // insulated end sleeve (coloured by size), then the white number marker
    final sleeve = Rect.fromCenter(center: at + Offset(0, dir * 5.2 * kPx), width: 3.6 * kPx, height: 5.4 * kPx);
    final sleeveCol = (col == 'br' || col == 'bk' || col == 'gy' || col == 'ge') ? const Color(0xFF2F6FE0) : const Color(0xFFE53935);
    c.drawRRect(RRect.fromRectAndRadius(sleeve, Radius.circular(1.2 * kPx)), Paint()..color = sleeveCol);
    c.drawRect(Rect.fromLTWH(sleeve.left, sleeve.top + sleeve.height * 0.15, sleeve.width, sleeve.height * 0.12), Paint()..color = const Color(0x55FFFFFF));
    final mark = Rect.fromCenter(center: at + Offset(0, dir * 11.6 * kPx), width: 3.8 * kPx, height: 7.2 * kPx);
    c.drawRRect(RRect.fromRectAndRadius(mark, Radius.circular(1.0 * kPx)), Paint()..color = const Color(0xFFF4F5F0));
    c.drawRRect(RRect.fromRectAndRadius(mark, Radius.circular(1.0 * kPx)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9AA0A6));
    final tp = TextPainter(
      text: TextSpan(text: '$n', style: TextStyle(fontSize: 3.2 * kPx, fontWeight: FontWeight.w800, color: const Color(0xFF15181B), fontFamily: 'JetBrainsMono')),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(mark.center.dx, mark.center.dy);
    c.rotate(-math.pi / 2);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(covariant WirePainter old) => true;
}

/// Terminal markers: rings for every free terminal while wiring, live dots while running.
class TermPainter extends CustomPainter {
  final LabDoc doc;
  final String? pending;
  final bool wiring;
  final Set<String> hidden;
  TermPainter(this.doc, this.pending, this.wiring, this.hidden);

  @override
  void paint(Canvas c, Size size) {
    final used = <String, int>{};
    for (final w in doc.wires) {
      used[w.a] = (used[w.a] ?? 0) + 1;
      used[w.b] = (used[w.b] ?? 0) + 1;
    }
    for (final p in doc.parts) {
      for (final e in p.termsAbs().entries) {
        final key = '${p.id}.${e.key}';
        if (hidden.contains(key)) continue;
        final o = e.value * kPx;
        if (key == pending) {
          c.drawCircle(o, 4.2 * kPx, Paint()..color = const Color(0x553D8BFF));
          c.drawCircle(o, 4.2 * kPx, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF3D8BFF));
        } else if (wiring) {
          final n = used[key] ?? 0;
          c.drawCircle(o, 3.0 * kPx, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = n >= 2 ? const Color(0x88FF5A64) : const Color(0xCC4FD8FF));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant TermPainter old) => true;
}

/// The motor part: terminal box plate (studs + bridges) above the motor body.
class MotorPlatePainter extends CustomPainter {
  final String links;
  MotorPlatePainter(this.links);
  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    final plate = Rect.fromLTWH(MotorPlate.plateX * s, MotorPlate.plateY * s, MotorPlate.plateW * s, MotorPlate.plateH * s);
    c.drawRRect(RRect.fromRectAndRadius(plate.inflate(4 * s), Radius.circular(4 * s)), Paint()..color = const Color(0xFF5E666E));
    c.drawRRect(RRect.fromRectAndRadius(plate, Radius.circular(2.5 * s)), Paint()..color = const Color(0xFF1E2328));
    final t = MotorPlate.terms();
    void stud(Offset o, String label) {
      c.drawCircle(o, 4.6 * s, Paint()..color = const Color(0xFFB8BEC4));
      c.drawCircle(o, 3.0 * s, Paint()..color = const Color(0xFF7E868E));
      final tp = TextPainter(
          text: TextSpan(text: label, style: TextStyle(fontSize: 3.0 * s, color: const Color(0xFFE6EBEF), fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, o + Offset(-tp.width / 2, label.endsWith('1') ? -9.6 * s : 5.6 * s));
    }

    for (final k in ['U1', 'V1', 'W1', 'W2', 'U2', 'V2']) {
      final p = t[k]!;
      stud(Offset(p.$1 * s, p.$2 * s), k);
    }
    final bridge = Paint()
      ..color = const Color(0xFFD9A441)
      ..strokeWidth = 3.4 * s
      ..strokeCap = StrokeCap.round;
    Offset at(String k) => Offset(t[k]!.$1 * s, t[k]!.$2 * s);
    if (links == 'delta') {
      c.drawLine(at('U1'), at('W2'), bridge);
      c.drawLine(at('V1'), at('U2'), bridge);
      c.drawLine(at('W1'), at('V2'), bridge);
    } else if (links == 'star') {
      c.drawLine(at('W2'), at('V2'), bridge);
    }
    final pe = at('PE');
    c.drawCircle(pe, 4.6 * s, Paint()..color = const Color(0xFF2EAA4A));
    c.drawCircle(pe, 2.6 * s, Paint()..color = const Color(0xFFF3D23B));
  }

  @override
  bool shouldRepaint(covariant MotorPlatePainter old) => old.links != links;
}

ui.Color stateColor(bool on) => on ? const Color(0xFF35E08A) : const Color(0xFF8798BF);
