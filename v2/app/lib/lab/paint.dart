// Panel Lab drawing: plate, DIN rails, hand-drawn wires with ferrules and live current,
// spark / smoke effects, motor terminal plate.
// World unit = millimetre; the canvas is painted at [kPx] logical pixels per mm.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../schem/plant_paint.dart';
import '../sim/engine.dart';
import '../sim/plant.dart';
import '../ui/perf.dart';
import 'catalog.dart';
import 'machine_sprites.dart';
import 'model.dart';

const double kPx = 4.0;

// ------------------------------------------------------------------ routing
class WireRoute {
  final List<Offset> pts; // mm
  final Offset dirA, dirB; // unit vectors leaving each terminal
  final int index; // spreads parallel wires a little
  const WireRoute(this.pts, this.dirA, this.dirB, [this.index = 0]);
}

/// Free hand wiring: every wire leaves its terminal straight out (up for top
/// terminals, down for bottom ones) and hangs between its ends in a soft curve.
class WireRouter {
  final LabDoc doc;
  WireRouter(this.doc);

  WireRoute route(LabWire w, int index) {
    final a = doc.termPos(w.a)!, b = doc.termPos(w.b)!;
    return WireRoute([a, ...w.pts, b], doc.termDir(w.a), doc.termDir(w.b), index);
  }
}

Path wirePath(WireRoute r) {
  final p = Path();
  final pts = [for (final o in r.pts) o * kPx];
  p.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 2) {
    final a = pts.first, b = pts.last;
    final d = (b - a).distance;
    final spread = 1 + ((r.index * 5) % 7 - 3) * 0.06;
    final k = math.max(14.0 * kPx, math.min(70.0 * kPx, d * 0.42)) * spread;
    final sag = Offset(0, d * 0.10);
    final c1 = a + r.dirA * k + sag;
    final c2 = b + r.dirB * k + sag;
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
  PlatePainter(this.doc, this.selected) : _sig = _signature(doc, selected);

  /// what the plate shows: its size, the bench, the door and the rails. The plate is
  /// only repainted when one of these changes, not on every frame of a simulation.
  final int _sig;
  static int _signature(LabDoc d, String? sel) => Object.hash(d.plateW, d.plateH, d.benchW, d.doorH, sel,
      Object.hashAll([for (final p in d.parts) if (p.def == 'din_rail') Object.hash(p.id, p.x, p.y, p.len)]));

  @override
  void paint(Canvas c, Size size) {
    final bench = doc.benchRect;
    if (bench != null) {
      final b = Rect.fromLTWH(bench.left * kPx, bench.top * kPx, bench.width * kPx, bench.height * kPx);
      final br = RRect.fromRectAndRadius(b, const Radius.circular(18));
      c.drawShadow(Path()..addRRect(br), Colors.black, 14, false);
      c.drawRRect(br, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A3344), Color(0xFF1C2433)]).createShader(b));
      final grid = Paint()..color = const Color(0x14FFFFFF);
      for (var x = b.left + 20 * kPx; x < b.right; x += 20 * kPx) {
        c.drawLine(Offset(x, b.top + 8), Offset(x, b.bottom - 8), grid);
      }
      for (var y = b.top + 20 * kPx; y < b.bottom; y += 20 * kPx) {
        c.drawLine(Offset(b.left + 8, y), Offset(b.right - 8, y), grid);
      }
      final tp = TextPainter(
          text: TextSpan(text: 'منضدة العمل: المحركات والآلات ومكونات الباب', style: TextStyle(fontSize: 6 * kPx, color: const Color(0x99DDE6F5), fontWeight: FontWeight.w600)),
          textDirection: TextDirection.rtl)
        ..layout();
      tp.paint(c, Offset(b.right - tp.width - 8 * kPx, b.top + 5 * kPx));
    }
    final door = doc.doorRect;
    if (door != null) {
      final r = Rect.fromLTWH(door.left * kPx, door.top * kPx, door.width * kPx, door.height * kPx);
      final rr0 = RRect.fromRectAndRadius(r, Radius.circular(4 * kPx));
      c.drawShadow(Path()..addRRect(rr0), Colors.black, 10, false);
      c.drawRRect(rr0, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD9DCDD), Color(0xFFC4C8CA)]).createShader(r));
      c.drawRRect(rr0, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * kPx
        ..color = const Color(0xFF8E959C));
      final tp = TextPainter(
          text: TextSpan(text: 'باب اللوحة: ركّب هنا الضواغط ولمبات البيان والسرينة', style: TextStyle(fontSize: 5.6 * kPx, color: const Color(0xFF39414B), fontWeight: FontWeight.w700)),
          textDirection: TextDirection.rtl)
        ..layout();
      tp.paint(c, Offset(r.right - tp.width - 6 * kPx, r.top + 5 * kPx));
      for (final h in doc.doorHoles()) {
        final o = h * kPx;
        c.drawCircle(o, 11.5 * kPx, Paint()..color = const Color(0xFF9AA1A7));
        c.drawCircle(o, 11 * kPx, Paint()..color = const Color(0xFF20252B));
        c.drawCircle(o, 11 * kPx, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * kPx
          ..color = const Color(0xFF5E666E));
      }
    }
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

  static void _selBox(Canvas c, Rect r) {
    c.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(8)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF3D8BFF));
  }

  @override
  bool shouldRepaint(covariant PlatePainter old) => old._sig != _sig || old.doc != doc;
}

// ------------------------------------------------------------------ wires
class WirePainter extends CustomPainter {
  final LabDoc doc;
  final int? selectedWire;
  final Nets? nets;
  final double phase; // animation 0..1 for live glow
  final String? pending;
  final Set<LabWire> faulty;
  /// wires carrying current: index → +1 a→b / -1 b→a
  final Map<int, int> flows;
  /// wires of a shorted net (flash red)
  final Set<int> flash;
  /// rubber-band wire being dragged: from (mm) → to (mm)
  final (Offset, Offset, bool)? drag;
  final String dragColor;
  late final WireRouter router = WireRouter(doc);
  WirePainter(
      {required this.doc,
      this.selectedWire,
      this.nets,
      this.phase = 0,
      this.pending,
      this.faulty = const {},
      this.flows = const {},
      this.flash = const {},
      this.drag,
      this.dragColor = 'rd'});

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
      final hot = flash.contains(i);
      if (i == selectedWire) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick + 10
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xAA3D8BFF));
      }
      if (hot) {
        final a = 0.55 + 0.45 * math.sin(phase * math.pi * 12);
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick + 12
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..color = const Color(0xFFFF3B30).withValues(alpha: a));
      } else if (live) {
        // energised but no current: faint halo
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick + 5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..color = const Color(0x40FFD54A));
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
      final f = flows[i];
      if (f != null) _flow(c, path, f, thick);
    }
    final dg = drag;
    if (dg != null) {
      final a = dg.$1 * kPx, b = dg.$2 * kPx;
      final rb = Path()..moveTo(a.dx, a.dy);
      final up = dg.$3 ? -1.0 : 1.0;
      final d = (b - a).distance;
      final k = math.min(50.0 * kPx, d * 0.4);
      rb.cubicTo(a.dx, a.dy + up * k, b.dx, b.dy + d * 0.1, b.dx, b.dy);
      final col = wireColor(dragColor).color;
      c.drawPath(rb, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * kPx + 1.6
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(col, Colors.black, 0.55)!);
      c.drawPath(rb, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * kPx
        ..strokeCap = StrokeCap.round
        ..color = col);
      c.drawCircle(b, 4.5 * kPx, Paint()..color = const Color(0x553D8BFF));
      c.drawCircle(b, 1.6 * kPx, Paint()..color = const Color(0xFFDDE7FF));
    }
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

  /// moving bright dashes along a wire in the direction of the current
  void _flow(Canvas c, Path path, int dir, double thick) {
    const seg = 7.0 * kPx, gap = 11.0 * kPx;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick * 0.55
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFF3B0);
    final glowP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick * 1.6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..color = const Color(0xAAFFC93D);
    for (final m in path.computeMetrics()) {
      final shift = (phase * 3 % 1) * (seg + gap);
      for (var t = -seg - gap + shift; t < m.length; t += seg + gap) {
        final s0 = dir > 0 ? t : m.length - t - seg;
        final a = s0.clamp(0.0, m.length).toDouble(), b = (s0 + seg).clamp(0.0, m.length).toDouble();
        if (b - a < 1) continue;
        final part = m.extractPath(a, b);
        c.drawPath(part, glowP);
        c.drawPath(part, paint);
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
    final tp = TextCache.get('$n', TextStyle(fontSize: 3.2 * kPx, fontWeight: FontWeight.w800, color: const Color(0xFF15181B), fontFamily: 'JetBrainsMono'));
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
/// wires one terminal screw takes
const kMaxWiresPerTerm = 4;

class TermPainter extends CustomPainter {
  final LabDoc doc;
  final String? pending;
  final bool wiring;
  final Set<String> hidden;
  final String? probeRed, probeBlack;

  /// the terminal a dragged wire has snapped to
  final String? target;
  TermPainter(this.doc, this.pending, this.wiring, this.hidden, {this.probeRed, this.probeBlack, this.target});

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
        if (key == target) {
          c.drawCircle(o, 6.5 * kPx, Paint()..color = const Color(0x4432E37A));
          c.drawCircle(o, 4.6 * kPx, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = const Color(0xFF32E37A));
        } else if (key == pending) {
          c.drawCircle(o, 4.2 * kPx, Paint()..color = const Color(0x553D8BFF));
          c.drawCircle(o, 4.2 * kPx, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF3D8BFF));
        } else if (key == probeRed || key == probeBlack) {
          final col = key == probeRed ? const Color(0xFFE53935) : const Color(0xFF15181B);
          c.drawCircle(o, 4.4 * kPx, Paint()..color = col.withValues(alpha: 0.35));
          c.drawLine(o, o + Offset(9 * kPx, -14 * kPx), Paint()
            ..color = col
            ..strokeWidth = 2.6 * kPx
            ..strokeCap = StrokeCap.round);
          c.drawCircle(o, 1.6 * kPx, Paint()..color = const Color(0xFFDADFE3));
        } else if (wiring) {
          final n = used[key] ?? 0;
          c.drawCircle(o, 3.0 * kPx, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = n >= kMaxWiresPerTerm ? const Color(0x88FF5A64) : const Color(0xCC4FD8FF));
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
  final bool single; // single-phase motor: U1 U2 / Z1 Z2 and a run capacitor
  MotorPlatePainter(this.links, {this.single = false});
  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    final plate = Rect.fromLTWH(MotorPlate.plateX * s, MotorPlate.plateY * s, MotorPlate.plateW * s, MotorPlate.plateH * s);
    c.drawRRect(RRect.fromRectAndRadius(plate.inflate(4 * s), Radius.circular(4 * s)), Paint()..color = const Color(0xFF5E666E));
    c.drawRRect(RRect.fromRectAndRadius(plate, Radius.circular(2.5 * s)), Paint()..color = const Color(0xFF1E2328));
    final t = single ? MotorPlate.terms1() : MotorPlate.terms();
    void stud(Offset o, String label) {
      c.drawCircle(o, 4.6 * s, Paint()..color = const Color(0xFFB8BEC4));
      c.drawCircle(o, 3.0 * s, Paint()..color = const Color(0xFF7E868E));
      final tp = TextCache.get(label, TextStyle(fontSize: 3.0 * s, color: const Color(0xFFE6EBEF), fontWeight: FontWeight.w700));
      tp.paint(c, o + Offset(-tp.width / 2, label.endsWith('1') ? -9.6 * s : 5.6 * s));
    }

    for (final k in single ? const ['U1', 'U2', 'Z1', 'Z2'] : const ['U1', 'V1', 'W1', 'W2', 'U2', 'V2']) {
      final p = t[k]!;
      stud(Offset(p.$1 * s, p.$2 * s), k);
    }
    if (single) {
      // run capacitor in the auxiliary winding (drawn between the two columns)
      final cx = (MotorPlate.plateX + 35) * s, cy = (MotorPlate.plateY + 22) * s;
      final r = Rect.fromCenter(center: Offset(cx, cy), width: 13 * s, height: 26 * s);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 * s)), Paint()..color = const Color(0xFF2E5FA8));
      final tp = TextPainter(text: TextSpan(text: 'C', style: TextStyle(fontSize: 6 * s, color: Colors.white, fontWeight: FontWeight.w800)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2));
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
  bool shouldRepaint(covariant MotorPlatePainter old) => old.links != links || old.single != single;
}

/// screw-terminal lugs left and right of a face-on door device
class SideLugPainter extends CustomPainter {
  final List<String> labels;
  SideLugPainter(this.labels);
  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    final h = 18 * s, w = kLug * s * 0.92;
    for (var i = 0; i < 2; i++) {
      final x = i == 0 ? 0.0 : size.width - w;
      final r = Rect.fromLTWH(x, size.height / 2 - h / 2, w, h);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(2.2 * s)), Paint()..color = const Color(0xFF15191F));
      c.drawRRect(RRect.fromRectAndRadius(r.deflate(1.2 * s), Radius.circular(1.6 * s)), Paint()..color = const Color(0xFF2B3139));
      final o = r.center;
      c.drawCircle(o, 3.6 * s, Paint()..color = const Color(0xFFC9A24A));
      c.drawLine(o - Offset(2.2 * s, 0), o + Offset(2.2 * s, 0), Paint()
        ..color = const Color(0xFF7A5E22)
        ..strokeWidth = 0.9 * s);
      final tp = TextCache.get(labels[i], TextStyle(fontSize: 3.6 * s, color: const Color(0xFFE8EDF2), fontWeight: FontWeight.w800));
      tp.paint(c, Offset(o.dx - tp.width / 2, r.top - tp.height - 0.6 * s));
    }
  }

  @override
  bool shouldRepaint(covariant SideLugPainter old) => false;
}

/// Machines driven by a motor: cart on a track, hoist, three-floor lift, tank with pump.
/// [x] is position / level 0…1, [sw] the switch states, [run] the motor turns.
class MachinePainter extends CustomPainter {
  final String kind;
  final double x;
  final List<bool> sw;
  final bool run, valve;
  final String motor;
  final double phase;

  /// sorting belt, press, filling line: the machine of lib/sim/plant.dart drawn in the
  /// scene area, the circuit it reads, and whether its valve coil (A1-A2) is energised
  final Plant? plant;
  final PlantIo? io;
  final bool coil;

  /// the machine rendered from its Blender model (lib/lab/machine_sprites.dart), when loaded
  final MachineSprite? sprite;
  MachinePainter(this.kind,
      {this.x = 0,
      this.sw = const [false, false, false, false],
      this.run = false,
      this.valve = true,
      this.motor = '',
      this.phase = 0,
      this.plant,
      this.io,
      this.coil = false,
      this.sprite});

  /// what the panel lab's own machines (cart, hoist, lift) show now
  MachineLook _look() {
    final pl = plant;
    if (pl != null) return MachineLook.ofPlant(pl, io ?? _Idle(coil));
    bool s(int i) => i < sw.length && sw[i];
    return switch (kind) {
      'cart' => MachineLook(x: x, lamps: {'LS1': s(0), 'LS2': s(1), 'RUN': run}),
      'hoist' => MachineLook(z: x, lamps: {'B1': s(0), 'B2': s(1)}),
      'lift' => MachineLook(z: x, door: !run && (s(0) || s(1) || s(2)) ? 1 : 0, lamps: {'B1': s(0), 'B2': s(1), 'B3': s(2), 'CAR': true}),
      _ => const MachineLook(),
    };
  }

  static const _steel = Color(0xFF8C96A3), _dark = Color(0xFF151A22), _frame = Color(0xFF2B3442);

  void _text(Canvas c, String t, Offset at, double size, {Color col = const Color(0xFFDDE6F5), bool bold = true, TextDirection dir = TextDirection.ltr, bool center = true}) {
    final tp = TextCache.get(t, TextStyle(fontSize: size, color: col, fontWeight: bold ? FontWeight.w800 : FontWeight.w500), dir: dir);
    tp.paint(c, at - Offset(center ? tp.width / 2 : 0, tp.height / 2));
  }

  /// a small roller limit switch; [on] when actuated
  void _limit(Canvas c, Offset o, bool on, String label, {bool flip = false}) {
    const s = kPx;
    final body = Rect.fromCenter(center: o, width: 14 * s, height: 18 * s);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(2 * s)), Paint()..color = const Color(0xFFE0B23A));
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(2 * s)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * s
      ..color = const Color(0xFF6B5216));
    final arm = o + Offset(0, (flip ? 1 : -1) * 12 * s) + Offset(on ? 4 * s : 0, 0);
    c.drawLine(o + Offset(0, (flip ? 1 : -1) * 8 * s), arm, Paint()
      ..strokeWidth = 1.4 * s
      ..color = _dark);
    c.drawCircle(arm, 3 * s, Paint()..color = on ? const Color(0xFF2FE07A) : const Color(0xFF3A4250));
    if (on) {
      c.drawCircle(o, 10 * s, Paint()
        ..color = const Color(0x552FE07A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    _text(c, label, o + Offset(0, (flip ? -1 : 1) * 14 * s), 4.6 * s, col: on ? const Color(0xFF2FE07A) : const Color(0xFFDDE6F5));
  }

  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    final all = Offset.zero & size;
    c.drawRRect(RRect.fromRectAndRadius(all, Radius.circular(5 * s)), Paint()..color = const Color(0xFF0E141D));
    c.drawRRect(RRect.fromRectAndRadius(all.deflate(1.5 * s), Radius.circular(4 * s)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s
      ..color = const Color(0xFF3A4658));
    // terminal strip along the bottom
    final strip = Rect.fromLTWH(6 * s, size.height - 20 * s, size.width - 12 * s, 16 * s);
    c.drawRRect(RRect.fromRectAndRadius(strip, Radius.circular(2 * s)), Paint()..color = _frame);
    final n = machSwitches(kind);
    final names = switch (kind) {
      'tank' => ['عوامة سفلى', 'عوامة عليا'],
      'lift' => ['الأرضي', 'الأول', 'الثاني'],
      'hoist' => ['أسفل', 'أعلى'],
      'sort' => ['آخر السير', 'معدن', 'بستم راجع', 'بستم طالع'],
      'press' => ['ذراع فوق', 'ذراع تحت', 'قطعة'],
      'fill' => ['زجاجة', 'اتملت'],
      _ => ['يسار', 'يمين'],
    };
    // the plant machines name their sensors B1…Bn, as in the schematic exercises
    final pre = kLabPlants.contains(kind) ? 'B' : 'S';
    final terms = MachineGeo.terms(kind);
    for (var i = 1; i <= n; i++) {
      final a = terms['S${i}1']!, b = terms['S${i}4']!;
      final cx = (a.$1 + b.$1) / 2 * s;
      final on = i <= sw.length && sw[i - 1];
      _text(c, '$pre$i ${names[i - 1]}', Offset(cx, strip.top - 4.5 * s), 4.2 * s, dir: TextDirection.rtl, col: on ? const Color(0xFF2FE07A) : const Color(0xFFDDE6F5));
      _text(c, 'NC', Offset(((terms['S${i}1']!.$1 + terms['S${i}2']!.$1) / 2) * s, strip.bottom + 2.2 * s), 3.2 * s, col: const Color(0xFF8EA0B8));
      _text(c, 'NO', Offset(((terms['S${i}3']!.$1 + terms['S${i}4']!.$1) / 2) * s, strip.bottom + 2.2 * s), 3.2 * s, col: const Color(0xFF8EA0B8));
    }
    final a1 = terms['A1'], a2 = terms['A2'];
    if (a1 != null && a2 != null) {
      _text(c, 'Y1 صمام', Offset((a1.$1 + a2.$1) / 2 * s, strip.top - 4.5 * s), 4.2 * s, dir: TextDirection.rtl, col: coil ? const Color(0xFFFFC14D) : const Color(0xFFDDE6F5));
      _text(c, 'A1  A2', Offset((a1.$1 + a2.$1) / 2 * s, strip.bottom + 2.2 * s), 3.2 * s, col: const Color(0xFF8EA0B8));
    }
    final area = Rect.fromLTRB(10 * s, 12 * s, size.width - 10 * s, strip.top - 12 * s);
    final sp = sprite;
    if (sp != null) {
      if (kind != 'press') {
        final what = plant != null ? 'السير يقوده المحرك' : 'يقودها المحرك';
        _text(c, motor.isEmpty ? 'غير مربوطة بمحرك' : '$what $motor', Offset(area.left, 6.5 * s), 4.2 * s,
            col: motor.isEmpty ? const Color(0xFFFF8A8A) : const Color(0xFF8EA0B8), dir: TextDirection.rtl, center: false, bold: false);
      }
      final scene = Rect.fromLTRB(area.left, area.top + 2 * s, area.right, area.bottom + 8 * s);
      c.save();
      c.translate(scene.left, scene.top);
      MachineSpritePainter(sp, _look(), 0).paint(c, scene.size);
      c.restore();
      return;
    }
    final pl = plant;
    if (pl != null) {
      if (kind != 'press') {
        _text(c, motor.isEmpty ? 'غير مربوطة بمحرك' : 'السير يقوده المحرك $motor', Offset(area.left, 6.5 * s), 4.2 * s,
            col: motor.isEmpty ? const Color(0xFFFF8A8A) : const Color(0xFF8EA0B8), dir: TextDirection.rtl, center: false, bold: false);
      }
      final scene = Rect.fromLTRB(area.left, area.top + 4 * s, area.right, area.bottom + 6 * s);
      c.save();
      c.translate(scene.left, scene.top);
      c.clipRect(Offset.zero & scene.size);
      PlantPainter(pl, io ?? _Idle(coil), 0).paint(c, scene.size);
      c.restore();
      return;
    }
    _text(c, motor.isEmpty ? 'غير مربوطة بمحرك' : 'يقودها المحرك $motor', Offset(area.left, 6.5 * s), 4.2 * s,
        col: motor.isEmpty ? const Color(0xFFFF8A8A) : const Color(0xFF8EA0B8), dir: TextDirection.rtl, center: false, bold: false);
    switch (kind) {
      case 'cart':
        _cart(c, area);
      case 'hoist':
        _hoist(c, area);
      case 'lift':
        _lift(c, area);
      case 'tank':
        _tank(c, area);
    }
  }

  void _cart(Canvas c, Rect a) {
    const s = kPx;
    final railY = a.center.dy + 14 * s;
    final l = a.left + 22 * s, r = a.right - 22 * s;
    c.drawRect(Rect.fromLTRB(l - 6 * s, railY, r + 6 * s, railY + 5 * s), Paint()..color = _steel);
    for (var xx = l; xx < r; xx += 16 * s) {
      c.drawRect(Rect.fromLTWH(xx, railY + 5 * s, 6 * s, 4 * s), Paint()..color = const Color(0xFF59616C));
    }
    const cw = 70.0 * s, ch = 38.0 * s;
    final cx = l + 9 * s + x * (r - l - 18 * s - cw);
    final body = Rect.fromLTWH(cx, railY - ch - 8 * s, cw, ch);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(4 * s)), Paint()..shader = const LinearGradient(colors: [Color(0xFF3D8BFF), Color(0xFF1F4FA8)]).createShader(body));
    c.drawRect(Rect.fromLTWH(body.left + 8 * s, body.top + 6 * s, cw - 16 * s, 10 * s), Paint()..color = const Color(0x553D8BFF));
    final rot = phase * 12;
    for (final wx in [body.left + 14 * s, body.right - 14 * s]) {
      final o = Offset(wx, railY - 4 * s);
      c.drawCircle(o, 7 * s, Paint()..color = _dark);
      c.drawCircle(o, 4 * s, Paint()..color = _steel);
      c.drawLine(o, o + Offset(math.cos(rot) * 4 * s, math.sin(rot) * 4 * s), Paint()
        ..strokeWidth = 1.2 * s
        ..color = _dark);
    }
    _text(c, run ? '◀ ▶' : '', body.center, 6 * s);
    _limit(c, Offset(l - 2 * s, railY - 18 * s), sw[0], 'S1');
    _limit(c, Offset(r + 2 * s, railY - 18 * s), sw[1], 'S2');
  }

  void _hoist(Canvas c, Rect a) {
    const s = kPx;
    final beam = Rect.fromLTWH(a.left + 10 * s, a.top + 6 * s, a.width - 20 * s, 10 * s);
    c.drawRect(beam, Paint()..color = const Color(0xFFE0B23A));
    for (var xx = beam.left; xx < beam.right; xx += 10 * s) {
      c.drawLine(Offset(xx, beam.top), Offset(xx + 8 * s, beam.bottom), Paint()
        ..color = const Color(0xFF6B5216)
        ..strokeWidth = 0.8 * s);
    }
    final drum = Rect.fromCenter(center: Offset(a.center.dx, beam.bottom + 14 * s), width: 46 * s, height: 20 * s);
    c.drawRRect(RRect.fromRectAndRadius(drum, Radius.circular(4 * s)), Paint()..color = _steel);
    for (var i = 0; i < 8; i++) {
      final xx = drum.left + 4 * s + i * 5.2 * s + (phase * 40 % 5.2) * s;
      if (xx < drum.right - 2 * s) {
        c.drawLine(Offset(xx, drum.top + 2 * s), Offset(xx + 2 * s, drum.bottom - 2 * s), Paint()
          ..color = const Color(0xFF59616C)
          ..strokeWidth = 0.8 * s);
      }
    }
    final top = drum.bottom + 8 * s, bottom = a.bottom - 36 * s;
    final hookY = bottom - x * (bottom - top);
    c.drawLine(Offset(a.center.dx, drum.bottom), Offset(a.center.dx, hookY), Paint()
      ..color = const Color(0xFFB8BEC4)
      ..strokeWidth = 1.2 * s);
    final block = Rect.fromCenter(center: Offset(a.center.dx, hookY + 6 * s), width: 16 * s, height: 12 * s);
    c.drawRRect(RRect.fromRectAndRadius(block, Radius.circular(2 * s)), Paint()..color = const Color(0xFFE0B23A));
    final load = Rect.fromCenter(center: Offset(a.center.dx, hookY + 26 * s), width: 50 * s, height: 26 * s);
    c.drawLine(block.bottomCenter, load.topLeft + Offset(6 * s, 0), Paint()
      ..color = _steel
      ..strokeWidth = 0.8 * s);
    c.drawLine(block.bottomCenter, load.topRight - Offset(6 * s, 0), Paint()
      ..color = _steel
      ..strokeWidth = 0.8 * s);
    c.drawRect(load, Paint()..color = const Color(0xFF7A5A3A));
    c.drawRect(load.deflate(3 * s), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * s
      ..color = const Color(0xFF4E3824));
    c.drawLine(Offset(a.left + 8 * s, a.bottom - 6 * s), Offset(a.right - 8 * s, a.bottom - 6 * s), Paint()
      ..color = _steel
      ..strokeWidth = 2 * s);
    _limit(c, Offset(a.right - 20 * s, top + 8 * s), sw[1], 'S2 أعلى');
    _limit(c, Offset(a.right - 20 * s, bottom + 20 * s), sw[0], 'S1 أسفل', flip: true);
  }

  void _lift(Canvas c, Rect a) {
    const s = kPx;
    final shaft = Rect.fromLTWH(a.left + 30 * s, a.top + 8 * s, a.width - 80 * s, a.height - 12 * s);
    c.drawRect(shaft, Paint()..color = const Color(0xFF1A2230));
    c.drawRect(shaft, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s
      ..color = _steel);
    const cabH = 52.0 * s;
    final travel = shaft.height - cabH - 4 * s;
    final names = ['الأرضي', 'الأول', 'الثاني'];
    for (var i = 0; i < 3; i++) {
      final fy = shaft.bottom - 2 * s - (i / 2) * travel;
      c.drawLine(Offset(shaft.left - 22 * s, fy), Offset(shaft.left, fy), Paint()
        ..color = _steel
        ..strokeWidth = 2 * s);
      _text(c, names[i], Offset(shaft.left - 12 * s, fy - 6 * s), 4.2 * s, dir: TextDirection.rtl);
      _limit(c, Offset(shaft.right + 14 * s, fy - cabH / 2), sw[i], 'S${i + 1}');
    }
    final cy = shaft.bottom - 2 * s - x * travel - cabH;
    final cab = Rect.fromLTWH(shaft.left + 6 * s, cy, shaft.width - 12 * s, cabH);
    c.drawLine(Offset(cab.center.dx, shaft.top), Offset(cab.center.dx, cab.top), Paint()
      ..color = const Color(0xFFB8BEC4)
      ..strokeWidth = 0.9 * s);
    c.drawRRect(RRect.fromRectAndRadius(cab, Radius.circular(3 * s)), Paint()..shader = const LinearGradient(colors: [Color(0xFFB8C2CF), Color(0xFF7D8998)]).createShader(cab));
    c.drawLine(Offset(cab.center.dx, cab.top + 4 * s), Offset(cab.center.dx, cab.bottom - 4 * s), Paint()
      ..color = const Color(0xFF4C5563)
      ..strokeWidth = 0.9 * s);
    if (run) _text(c, '⇅', cab.center, 10 * s, col: const Color(0xFF1F4FA8));
  }

  void _tank(Canvas c, Rect a) {
    const s = kPx;
    final tank = Rect.fromLTWH(a.left + 50 * s, a.top + 20 * s, a.width - 100 * s, a.height - 40 * s);
    final lv = x.clamp(0.0, 1.0);
    final water = Rect.fromLTRB(tank.left, tank.bottom - lv * tank.height, tank.right, tank.bottom);
    c.drawRect(tank, Paint()..color = const Color(0xFF16202C));
    c.drawRect(water, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4FB6FF), Color(0xFF1E5FB0)]).createShader(water));
    if (lv > 0.01) {
      final wave = Path()..moveTo(water.left, water.top);
      for (var xx = 0.0; xx <= water.width; xx += 4 * s) {
        wave.lineTo(water.left + xx, water.top + math.sin(xx / (10 * s) + phase * 20) * 1.2 * s);
      }
      c.drawPath(wave, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * s
        ..color = const Color(0xAAFFFFFF));
    }
    c.drawRect(tank, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s
      ..color = _steel);
    _text(c, '${(lv * 100).round()}%', tank.center, 8 * s);
    // floats on the right wall
    const pts = [0.2, 0.85];
    for (var i = 0; i < 2; i++) {
      final fy = tank.bottom - pts[i] * tank.height;
      final fl = Offset(tank.right - 10 * s, math.min(fy + 6 * s, tank.bottom - lv * tank.height + (lv * tank.height < pts[i] * tank.height ? 0 : 0)));
      c.drawLine(Offset(tank.right, fy), fl, Paint()
        ..strokeWidth = 0.8 * s
        ..color = _steel);
      c.drawCircle(fl, 3.4 * s, Paint()..color = const Color(0xFFFF8F1F));
      _limit(c, Offset(tank.right + 18 * s, fy), sw[i], 'S${i + 1}');
    }
    // pump and pipe into the top
    final pump = Offset(tank.left - 26 * s, tank.bottom - 14 * s);
    c.drawCircle(pump, 12 * s, Paint()..color = run ? const Color(0xFF2FA36B) : const Color(0xFF3A4250));
    for (var i = 0; i < 4; i++) {
      final ang = phase * 30 + i * math.pi / 2;
      c.drawLine(pump, pump + Offset(math.cos(ang), math.sin(ang)) * 8 * s, Paint()
        ..strokeWidth = 1.4 * s
        ..color = const Color(0xFFDDE6F5));
    }
    final pipe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..color = _steel;
    c.drawPath(Path()
      ..moveTo(pump.dx, pump.dy - 12 * s)
      ..lineTo(pump.dx, tank.top - 8 * s)
      ..lineTo(tank.left + 20 * s, tank.top - 8 * s)
      ..lineTo(tank.left + 20 * s, tank.top + 4 * s), pipe);
    if (run) {
      for (var i = 0; i < 4; i++) {
        final yy = tank.top + 6 * s + ((phase * 60 + i * 9) % (tank.height * (1 - lv) / s + 1)) * s;
        if (yy < water.top) c.drawCircle(Offset(tank.left + 20 * s, yy), 1.4 * s, Paint()..color = const Color(0xFF4FB6FF));
      }
    }
    _text(c, 'طلمبة', pump + Offset(0, 17 * s), 4 * s, dir: TextDirection.rtl);
    // outlet valve (tap it while running)
    final v = Offset(tank.right - 16 * s, tank.bottom + 10 * s);
    c.drawLine(Offset(v.dx, tank.bottom), Offset(v.dx, v.dy + 6 * s), pipe);
    c.drawCircle(v, 5 * s, Paint()..color = valve ? const Color(0xFF2FE07A) : const Color(0xFFFF5A64));
    _text(c, valve ? 'محبس مفتوح' : 'محبس مغلق', v + Offset(-22 * s, 0), 4 * s, dir: TextDirection.rtl);
  }

  @override
  bool shouldRepaint(covariant MachinePainter old) => true;
}

// ------------------------------------------------------------------ effects
class LabFx {
  final String kind; // spark · smoke
  final Offset at; // mm
  final double born; // seconds (page clock)
  final int seed;
  final bool loop; // previews: keep repeating
  const LabFx(this.kind, this.at, this.born, this.seed, {this.loop = false});
  double get life => loop ? 1e9 : (kind == 'spark' ? 1.4 : 6.0);
}

/// Sparks (bright particles + flash) at a short, smoke rising from a burnt part.
class FxPainter extends CustomPainter {
  final List<LabFx> fx;
  final double now;
  FxPainter(this.fx, this.now);

  @override
  void paint(Canvas c, Size size) {
    for (final f in fx) {
      var age = now - f.born;
      if (age < 0 || age > f.life) continue;
      if (f.loop) age = f.kind == 'spark' ? age % 1.4 : age % 5.0;
      final o = f.at * kPx;
      final rnd = math.Random(f.seed);
      if (f.kind == 'spark') {
        final k = 1 - age / 1.4;
        if (age < 0.25) {
          c.drawCircle(o, (14 + 90 * age) * kPx * 0.5, Paint()
            ..color = Colors.white.withValues(alpha: (1 - age / 0.25) * 0.9)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
        }
        c.drawCircle(o, 10 * kPx * k, Paint()
          ..color = const Color(0xFFFFB020).withValues(alpha: 0.5 * k)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
        for (var i = 0; i < 26; i++) {
          final ang = rnd.nextDouble() * math.pi * 2;
          final sp = (40 + rnd.nextDouble() * 110) * kPx;
          final t = age * (0.7 + rnd.nextDouble() * 0.6);
          final p = o + Offset(math.cos(ang), math.sin(ang)) * sp * t + Offset(0, 60 * kPx * t * t);
          final tail = o + Offset(math.cos(ang), math.sin(ang)) * sp * math.max(0, t - 0.05) + Offset(0, 60 * kPx * math.pow(math.max(0, t - 0.05), 2));
          c.drawLine(tail, p, Paint()
            ..strokeWidth = 1.2 * kPx
            ..strokeCap = StrokeCap.round
            ..color = Color.lerp(const Color(0xFFFFFFFF), const Color(0xFFFF8A00), rnd.nextDouble())!.withValues(alpha: k));
        }
      } else {
        // smoke puffs drifting up
        for (var i = 0; i < 14; i++) {
          final t = (age + i * 0.4) % 2.8;
          final x = o.dx + (rnd.nextDouble() - 0.5) * 18 * kPx + math.sin(t * 2 + i) * 6 * kPx;
          final y = o.dy - t * 26 * kPx;
          final r = (5 + t * 9) * kPx;
          final a = (1 - t / 2.8) * 0.35 * (f.loop ? 1.0 : (1 - age / 6.0).clamp(0.0, 1.0));
          c.drawCircle(Offset(x, y), r, Paint()
            ..color = const Color(0xFF3C3F44).withValues(alpha: a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FxPainter old) => true;
}

ui.Color stateColor(bool on) => on ? const Color(0xFF35E08A) : const Color(0xFF8798BF);

/// mechanical interlock between two contactors: a bracket across their sides
class InterlockPainter extends CustomPainter {
  final LabDoc doc;
  InterlockPainter(this.doc);
  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    for (final m in doc.mech) {
      final a = doc.byId(m[0]), b = doc.byId(m[1]);
      if (a == null || b == null) continue;
      final l = a.x < b.x ? a : b, r = a.x < b.x ? b : a;
      final gap = r.x - (l.x + l.size.width);
      if (gap > 30 || (a.y - b.y).abs() > 20) continue; // only when mounted side by side
      final cy = (l.y + l.size.height * 0.42) * s;
      final rect = Rect.fromLTRB((l.x + l.size.width - 6) * s, cy - 7 * s, (r.x + 6) * s, cy + 7 * s);
      c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(2 * s)), Paint()..color = const Color(0xFF2B3139));
      c.drawRRect(RRect.fromRectAndRadius(rect.deflate(1.2 * s), Radius.circular(1.5 * s)), Paint()..color = const Color(0xFF4A535E));
      final tp = TextPainter(text: TextSpan(text: '⇄', style: TextStyle(fontSize: 7 * s, color: const Color(0xFFF5B83D), fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant InterlockPainter old) => true;
}

/// a running motor: turning coupling on the shaft end with a direction arrow
class MotorRunPainter extends CustomPainter {
  final double angle; // degrees
  final int dir; // 1 clockwise seen from the shaft end, -1 anticlockwise
  final double speed; // 0..1
  final Offset shaft; // mm in the part frame, shaft tip
  MotorRunPainter(this.angle, this.dir, this.speed, this.shaft);
  @override
  void paint(Canvas c, Size size) {
    const s = kPx;
    final o = shaft * s;
    // coupling cylinder on the shaft (seen from the side): stripes slide with the rotation
    final body = Rect.fromCenter(center: o + Offset(7 * s, 0), width: 14 * s, height: 22 * s);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(body, Radius.circular(2.5 * s)));
    c.drawRect(body, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF59616C), Color(0xFFD5DADF), Color(0xFF59616C)]).createShader(body));
    final pitch = 6.0 * s;
    final shift = (angle / 360 * pitch * 4 * dir) % pitch;
    for (var y = body.top - pitch + shift; y < body.bottom + pitch; y += pitch) {
      c.drawLine(Offset(body.left, y), Offset(body.right, y + 3 * s), Paint()
        ..color = const Color(0xFFF5B83D)
        ..strokeWidth = 1.6 * s);
    }
    c.restore();
    // direction arrow around the shaft end
    final arc = Rect.fromCenter(center: o + Offset(7 * s, 0), width: 40 * s, height: 40 * s);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(const Color(0x003DFF8B), const Color(0xFF35E08A), speed.clamp(0.0, 1.0))!;
    final start = (angle * math.pi / 180) * dir;
    c.drawArc(arc, start, 4.2 * dir, false, paint);
    final end = start + 4.2 * dir;
    final tip = arc.center + Offset(math.cos(end), math.sin(end)) * arc.width / 2;
    final tang = Offset(-math.sin(end), math.cos(end)) * dir.toDouble();
    final nrm = Offset(math.cos(end), math.sin(end));
    final head = Path()
      ..moveTo(tip.dx + tang.dx * 5 * s, tip.dy + tang.dy * 5 * s)
      ..lineTo(tip.dx - tang.dx * 1 * s + nrm.dx * 4 * s, tip.dy - tang.dy * 1 * s + nrm.dy * 4 * s)
      ..lineTo(tip.dx - tang.dx * 1 * s - nrm.dx * 4 * s, tip.dy - tang.dy * 1 * s - nrm.dy * 4 * s)
      ..close();
    c.drawPath(head, Paint()..color = paint.color);
  }

  @override
  bool shouldRepaint(covariant MotorRunPainter old) => true;
}

/// sound waves from a sounding siren
class SirenPainter extends CustomPainter {
  final double phase;
  SirenPainter(this.phase);
  @override
  void paint(Canvas c, Size size) {
    final o = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final k = (phase * 3 + i / 3) % 1;
      final r = size.shortestSide * (0.45 + 0.55 * k);
      c.drawCircle(o, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * kPx
        ..color = const Color(0xFFFF3B30).withValues(alpha: (1 - k) * 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant SirenPainter old) => true;
}

/// a machine with the power off: nothing runs, the valve shows the coil state
class _Idle implements PlantIo {
  final bool coil;
  const _Idle(this.coil);
  @override
  double motor(String tag) => 0;
  @override
  bool on(String tag) => coil;
  @override
  void sense(String tag, bool active) {}
  @override
  bool has(String tag) => true;
}
