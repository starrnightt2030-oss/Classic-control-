// Painting the schematic sheet: frame, title block, wires, symbols, live state.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sim/engine.dart';
import 'model.dart';
import 'symbols.dart';

/// live look of one symbol from the running simulation
SymLook? lookOf(SPlaced s, SchemSim? sim) {
  if (sim == null) return null;
  final l = sim.lab;
  final c = l.byId(sim.compOf[s.id] ?? '');
  switch (s.d.role) {
    case SymRole.source:
      return SymLook(energised: l.power);
    case SymRole.contact:
      return SymLook(closed: c?.s.on ?? false);
    case SymRole.hostPart:
      return SymLook(closed: c?.s.on ?? false);
    case SymRole.host:
      if (c == null) return const SymLook();
      if (c.type == 'ol') {
        return SymLook(fault: c.s.trip, note: c.s.trip ? 'TRIP' : '${c.s.current.toStringAsFixed(1)} / ${c.num_('set').toStringAsFixed(1)} A');
      }
      String? note;
      if (c.type == 'timer' && c.s.on) note = '${math.min(c.s.el, c.num_('T')).toStringAsFixed(1)}s';
      if (c.s.hum) note = 'HUM';
      if (c.s.dead) note = 'BURNT';
      return SymLook(energised: c.s.on, fault: c.s.hum || c.s.dead, note: note);
    case SymRole.device:
      if (c == null) return const SymLook();
      switch (c.type) {
        case 'pb_no':
          return SymLook(closed: c.s.pr);
        case 'pb_nc':
          return SymLook(closed: !c.s.pr);
        case 'estop':
          return SymLook(closed: !c.s.lat);
        case 'sel':
          return SymLook(closed: c.s.pos != 0);
        case 'lamp':
          return SymLook(energised: !c.s.dead && c.s.v > c.num_('V') * 0.6, fault: c.s.dead);
        case 'motor':
          final run = c.s.mode == 'star' || c.s.mode == 'delta';
          final bad = c.s.mode == 'single' || c.s.mode == 'over' || c.s.mode == 'dead';
          final mode = {'star': 'STAR', 'delta': 'DELTA', 'single': 'PHASE LOSS', 'over': 'OVERVOLT', 'dead': 'BURNT'}[c.s.mode];
          return SymLook(
              energised: run && c.s.spd > 0.02,
              fault: bad,
              angle: c.s.ang,
              note: mode == null ? null : '$mode · ${(c.s.spd * 1450).round()} rpm · ${c.s.current.toStringAsFixed(1)} A');
        default: // breakers, fuse
          return SymLook(closed: c.s.on, fault: c.s.trip);
      }
  }
}

class SheetPainter extends CustomPainter {
  final SchemDoc doc;
  final SchemSim? sim;
  final Map<int, int> flows; // document wire index → ±1
  final Set<int> flash;
  final double phase;
  final String? selected;
  final int? selWire;
  final String? pending;
  final (Offset, Offset, bool)? drag; // from pin (grid), to (grid), from-pin up
  final bool print; // no grid dots, no pin markers
  final String date;
  SheetPainter(this.doc,
      {this.sim, this.flows = const {}, this.flash = const {}, this.phase = 0, this.selected, this.selWire, this.pending, this.drag, this.print = false, this.date = ''});

  @override
  void paint(Canvas c, Size size) {
    const g = kG;
    final w = doc.sheetW * g, h = doc.sheetH * g;
    final sheet = Rect.fromLTWH(0, 0, w, h);
    if (!print) c.drawShadow(Path()..addRect(sheet), Colors.black, 16, false);
    c.drawRect(sheet, Paint()..color = Colors.white);
    if (!print) {
      final dot = Paint()..color = const Color(0xFFD5DBE5);
      for (var x = 1; x < doc.sheetW; x++) {
        for (var y = 1; y < doc.sheetH; y++) {
          c.drawCircle(Offset(x * g, y * g), 0.9, dot);
        }
      }
    }
    _frame(c, w, h);
    _wires(c);
    final nums = doc.contactNumbers();
    for (final s in doc.syms) {
      c.save();
      c.translate(s.x * g, s.y * g);
      paintSymbol(c, s.d, look: lookOf(s, sim), tag: s.tag, p: s.p, contactNo: nums[s.id] ?? '');
      if (s.p['burnt'] == true) _burnt(c, s);
      c.restore();
      if (s.id == selected) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.x * g, s.y * g, s.d.w * g, s.d.h * g).inflate(8), const Radius.circular(6)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF3D8BFF));
      }
    }
    if (!print && sim == null) _pins(c);
    final dg = drag;
    if (dg != null) {
      final a = dg.$1 * g, b = dg.$2 * g;
      final p = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(a.dx, b.dy)
        ..lineTo(b.dx, b.dy);
      c.drawPath(p, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3D8BFF));
      c.drawCircle(b, 6, Paint()..color = const Color(0x553D8BFF));
    }
  }

  void _burnt(Canvas c, SPlaced s) {
    final r = Rect.fromLTWH(0, 0, s.d.w * kG, s.d.h * kG);
    c.drawRect(r.deflate(2), Paint()..color = const Color(0x332A0A0A));
    final tp = TextPainter(
        text: const TextSpan(text: 'محترق', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800)), textDirection: TextDirection.rtl)
      ..layout();
    final box = Rect.fromCenter(center: Offset(r.center.dx, -8), width: tp.width + 10, height: tp.height + 2);
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = kBad);
    tp.paint(c, box.topLeft + const Offset(5, 1));
  }

  void _frame(Canvas c, double w, double h) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..color = kInk
      ..strokeWidth = 1.6;
    c.drawRect(Rect.fromLTWH(10, 10, w - 20, h - 20), pen);
    // title block, bottom-right
    const bw = 360.0, bh = 66.0;
    final r = Rect.fromLTWH(w - 10 - bw, h - 10 - bh, bw, bh);
    c.drawRect(r, Paint()..color = Colors.white);
    c.drawRect(r, pen);
    c.drawLine(Offset(r.left, r.top + 30), Offset(r.right, r.top + 30), pen..strokeWidth = 1);
    c.drawLine(Offset(r.left + 220, r.top + 30), Offset(r.left + 220, r.bottom), pen);
    void t(String s, Offset at, double size, {bool bold = false, TextDirection dir = TextDirection.rtl, double maxW = 340}) {
      final tp = TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontSize: size, color: kInk, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontFamily: 'Cairo')),
          textDirection: dir,
          maxLines: 1,
          ellipsis: '…')
        ..layout(maxWidth: maxW);
      tp.paint(c, at - Offset(dir == TextDirection.rtl ? tp.width : 0, tp.height / 2));
    }

    t(doc.title, Offset(r.right - 10, r.top + 15), 15, bold: true);
    t('أكاديمية التحكم الكهربائي', Offset(r.right - 10, r.top + 48), 11.5, maxW: 130);
    t(date.isEmpty ? 'لوحة 1/1' : date, Offset(r.left + 10, r.top + 48), 11, dir: TextDirection.ltr, maxW: 200);
  }

  void _pins(Canvas c) {
    final used = <String, int>{};
    for (final w in doc.wires) {
      used[w.a] = (used[w.a] ?? 0) + 1;
      used[w.b] = (used[w.b] ?? 0) + 1;
    }
    for (final s in doc.syms) {
      for (final pn in s.d.pins) {
        final k = '${s.id}.${pn.id}';
        final o = s.pinPos(pn) * kG;
        final isP = k == pending;
        c.drawCircle(o, isP ? 6 : 3.6, Paint()..color = isP ? const Color(0x663D8BFF) : (used.containsKey(k) ? const Color(0xFF1B2330) : const Color(0xFFFFFFFF)));
        c.drawCircle(o, isP ? 6 : 3.6, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF3D8BFF));
      }
    }
  }

  void _wires(Canvas c) {
    const g = kG;
    final n = sim?.lab.nets;
    final pinTerm = sim?.pinToTerm ?? const <String, String>{};
    final nums = doc.wireNumbers();
    final ends = <Offset, int>{};
    for (var i = 0; i < doc.wires.length; i++) {
      final w = doc.wires[i];
      final a = doc.pinPos(w.a), b = doc.pinPos(w.b);
      if (a == null || b == null) continue;
      final pts = schemRoute(a, doc.pinUp(w.a), b, doc.pinUp(w.b));
      final path = Path()..moveTo(pts.first.dx * g, pts.first.dy * g);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx * g, p.dy * g);
      }
      for (final p in pts) {
        ends[p] = (ends[p] ?? 0) + 1;
      }
      final term = pinTerm[w.a];
      final live = n != null && term != null && n.live(term);
      final hot = flash.contains(i);
      if (i == selWire) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x553D8BFF));
      }
      if (hot) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..color = kBad.withValues(alpha: 0.5 + 0.5 * math.sin(phase * math.pi * 12)));
      }
      Color col = kInk;
      if (live) {
        final ph = n!.phaseOf(term!);
        col = switch (ph) { 'N' => const Color(0xFF2F7FE0), 'PE' => const Color(0xFF2EAA4A), _ => const Color(0xFFC62828) };
      }
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = live ? 2.4 : 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = col);
      final f = flows[i];
      if (f != null) {
        final dash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFA000);
        for (final m in path.computeMetrics()) {
          const seg = 7.0, gap = 13.0;
          final shift = (phase * 3 % 1) * (seg + gap);
          for (var t = -seg - gap + shift; t < m.length; t += seg + gap) {
            final s0 = f > 0 ? t : m.length - t - seg;
            final x0 = s0.clamp(0.0, m.length).toDouble(), x1 = (s0 + seg).clamp(0.0, m.length).toDouble();
            if (x1 - x0 > 0.5) c.drawPath(m.extractPath(x0, x1), dash);
          }
        }
      }
      // wire number at the middle of the longest segment
      if (pts.length >= 2) {
        var best = 0, bl = 0.0;
        for (var k = 0; k < pts.length - 1; k++) {
          final d = (pts[k + 1] - pts[k]).distance;
          if (d > bl) {
            bl = d;
            best = k;
          }
        }
        if (bl > 1.6) {
          final mid = (pts[best] + pts[best + 1]) / 2 * g;
          final vertical = (pts[best].dx - pts[best + 1].dx).abs() < 0.01;
          final tp = TextPainter(
              text: TextSpan(text: '${nums[i]}', style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7588), fontFamily: 'JetBrainsMono')), textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(c, mid + (vertical ? Offset(3, -tp.height / 2) : Offset(-tp.width / 2, -tp.height - 1)));
        }
      }
    }
    // junction dots where three or more wire ends meet
    for (final e in ends.entries) {
      if (e.value >= 3) c.drawCircle(e.key * g, 3.4, Paint()..color = kInk);
    }
  }

  @override
  bool shouldRepaint(covariant SheetPainter old) => true;
}

/// distance (grid units) from a point to a wire's route
double wireDistance(SchemDoc d, SWire w, Offset p) {
  final a = d.pinPos(w.a), b = d.pinPos(w.b);
  if (a == null || b == null) return double.infinity;
  final pts = schemRoute(a, d.pinUp(w.a), b, d.pinUp(w.b));
  var best = double.infinity;
  for (var i = 0; i < pts.length - 1; i++) {
    final s = pts[i], e = pts[i + 1];
    final v = e - s;
    final l2 = v.dx * v.dx + v.dy * v.dy;
    final t = l2 == 0 ? 0.0 : (((p - s).dx * v.dx + (p - s).dy * v.dy) / l2).clamp(0.0, 1.0).toDouble();
    best = math.min(best, (p - (s + v * t)).distance);
  }
  return best;
}

/// the bill of materials page (A4 portrait, 1 px = 1 pt × [k])
void paintBom(Canvas c, SchemDoc d, {double k = 2, String date = ''}) {
  const w = 595.0, h = 842.0;
  c.scale(k);
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  void t(String s, double xRight, double y, double size, {bool bold = false, Color col = kInk, double maxW = 500, TextDirection dir = TextDirection.rtl}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: col, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontFamily: 'Cairo', height: 1.3)),
        textDirection: dir,
        maxLines: 2,
        ellipsis: '…')
      ..layout(maxWidth: maxW);
    tp.paint(c, Offset(dir == TextDirection.rtl ? xRight - tp.width : xRight, y));
  }

  t('قائمة مكونات الدائرة', w - 40, 40, 22, bold: true);
  t(d.title, w - 40, 72, 14, col: const Color(0xFF3D4A5E));
  t(date, 40, 76, 11, dir: TextDirection.ltr, col: const Color(0xFF6B7588));
  final line = Paint()
    ..color = const Color(0xFFCBD3DF)
    ..strokeWidth = 1;
  var y = 110.0;
  c.drawRect(Rect.fromLTWH(40, y, w - 80, 26), Paint()..color = const Color(0xFF0F2150));
  t('الرمز', w - 50, y + 3, 12, bold: true, col: Colors.white);
  t('المكوّن', w - 130, y + 3, 12, bold: true, col: Colors.white);
  t('المواصفات', w - 330, y + 3, 12, bold: true, col: Colors.white);
  y += 26;
  var i = 0;
  for (final (tag, name, spec) in d.bom()) {
    if (i.isOdd) c.drawRect(Rect.fromLTWH(40, y, w - 80, 26), Paint()..color = const Color(0xFFF2F5FA));
    t(tag, w - 50, y + 4, 12, bold: true, dir: TextDirection.ltr, maxW: 70);
    t(name, w - 130, y + 4, 12, maxW: 190);
    t(spec, w - 330, y + 4, 11, col: const Color(0xFF3D4A5E), maxW: 210);
    y += 26;
    c.drawLine(Offset(40, y), Offset(w - 40, y), line);
    i++;
    if (y > h - 80) break;
  }
  t('عدد الأسلاك في الرسم: ${d.wires.length}', w - 40, y + 18, 11, col: const Color(0xFF6B7588));
  t('أكاديمية التحكم الكهربائي · Control Academy', w - 40, h - 40, 10, col: const Color(0xFF8A94A6));
}
