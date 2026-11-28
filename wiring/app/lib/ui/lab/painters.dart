import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/model.dart';
import '../../sim/solver.dart';
import 'fx.dart';

const boardSize = Size(1000, 620);

enum Skin { board, schematic }

Color wireColor(WireColor c) => switch (c) {
      WireColor.brown => const Color(0xFF8A4B22),
      WireColor.red => const Color(0xFFD7262B),
      WireColor.blue => const Color(0xFF1F6FD8),
      WireColor.earth => const Color(0xFF2FA84F),
      WireColor.black => const Color(0xFF1D1D1F),
      WireColor.grey => const Color(0xFF8C9096),
    };

/// Everything the board painter needs for one frame.
class BoardState {
  final Sim sim;
  final SimResult res;
  final Skin skin;
  final double t; // seconds, for animation
  final String? selTerm;
  final int? selWire;
  final String? selPart;
  final Set<String> glowTerms; // guide mode: terminals to connect now
  final Fx fx;
  final List<String> probes; // multimeter probes: red, black
  final bool showLabels;
  BoardState({
    required this.sim, required this.res, required this.skin, required this.t, this.selTerm, this.selWire, this.selPart,
    this.glowTerms = const {}, required this.fx, this.probes = const [], this.showLabels = true,
  });
}

/// Curve of a wire on the realistic board: hangs a little below its ends.
Path wirePath(Offset a, Offset b, int i, Skin skin) {
  if (skin == Skin.schematic) {
    final mid = math.max(a.dy, b.dy) + 14 + (i % 6) * 5;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(a.dx, mid)
      ..lineTo(b.dx, mid)
      ..lineTo(b.dx, b.dy);
  }
  final d = (b - a).distance;
  final sag = 26 + d * .12 + (i % 4) * 4;
  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(a.dx, a.dy + sag, b.dx, b.dy + sag, b.dx, b.dy);
}

/// Index of the wire under [p], or null.
int? hitWire(Sim s, Offset p, Skin skin) {
  for (var i = s.wires.length - 1; i >= 0; i--) {
    final w = s.wires[i];
    final a = _tp(s, w.a), b = _tp(s, w.b);
    if (a == null || b == null) continue;
    final path = wirePath(a, b, i, skin);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 4) {
        final q = m.getTangentForOffset(d)!.position;
        if ((q - p).distance < 9) return i;
      }
    }
  }
  return null;
}

Offset? _tp(Sim s, String key) {
  final i = key.indexOf('.');
  final p = s.part(key.substring(0, i));
  if (p == null) return null;
  final id = key.substring(i + 1);
  final t = p.type.terms.where((t) => t.id == id).firstOrNull;
  return t == null ? null : p.pos + t.pos;
}

Offset? termPos(Sim s, String key) => _tp(s, key);

/// Terminal under [p] (board units), or null.
String? hitTerm(Sim s, Offset p, {double r = 15}) {
  String? best;
  var bd = r;
  for (final part in s.parts) {
    for (final t in part.type.terms) {
      final d = (part.pos + t.pos - p).distance;
      if (d < bd) {
        bd = d;
        best = '${part.id}.${t.id}';
      }
    }
  }
  return best;
}

Part? hitPart(Sim s, Offset p) {
  for (final part in s.parts.reversed) {
    if ((part.pos & part.type.size).contains(p)) return part;
  }
  return null;
}

final Map<String, TextPainter> _tcache = {};
void text(Canvas c, String s, Offset at, {double size = 11, Color color = Colors.black87, FontWeight w = FontWeight.w600, bool center = true}) {
  final key = '$s|$size|${color.toARGB32()}|${w.value}';
  final tp = _tcache.putIfAbsent(key, () {
    if (_tcache.length > 600) _tcache.clear();
    return TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Cairo', fontSize: size, color: color, fontWeight: w, height: 1.1)),
      textDirection: TextDirection.rtl,
    )..layout();
  });
  tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

RRect _rr(Rect r, double k) => RRect.fromRectAndRadius(r, Radius.circular(k));

/// Glossy plastic body used for modules and switch plates.
void plastic(Canvas c, Rect r, {double radius = 8, Color top = const Color(0xFFFFFFFF), Color bottom = const Color(0xFFDCDDE2)}) {
  c.drawRRect(_rr(r.shift(const Offset(2, 4)), radius), Paint()
    ..color = Colors.black.withValues(alpha: .28)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  c.drawRRect(_rr(r, radius), Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom]).createShader(r));
  c.drawRRect(_rr(r.deflate(.5), radius), Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.black.withValues(alpha: .18));
}

class BoardPainter extends CustomPainter {
  final BoardState st;
  BoardPainter(this.st);

  Sim get s => st.sim;
  SimResult get r => st.res;

  @override
  void paint(Canvas c, Size size) {
    if (st.skin == Skin.board) {
      _board(c);
    } else {
      _paper(c);
    }
    // wires under the parts on the board (they go into the back of the devices); over them on paper
    if (st.skin == Skin.board) _wires(c);
    for (final p in s.parts) {
      c.save();
      c.translate(p.pos.dx, p.pos.dy);
      if (st.skin == Skin.board) {
        _part(c, p);
      } else {
        _symbol(c, p);
      }
      c.restore();
    }
    if (st.skin == Skin.schematic) _wires(c);
    _terms(c);
    _lightGlow(c);
    st.fx.paint(c);
    _probes(c);
  }

  // --------------------------------------------------------------- backgrounds
  void _board(Canvas c) {
    final r = Offset.zero & boardSize;
    c.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEDE3CC), Color(0xFFD9C8A6)]).createShader(r));
    // wood grain
    final g = Paint()
      ..color = const Color(0xFFB59A6A).withValues(alpha: .18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rnd = math.Random(3);
    for (var i = 0; i < 26; i++) {
      final y = rnd.nextDouble() * boardSize.height;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= boardSize.width; x += 50) {
        path.lineTo(x, y + math.sin(x / 90 + i) * 6);
      }
      c.drawPath(path, g);
    }
    // perforated holes
    final h = Paint()..color = const Color(0xFF8E7A55).withValues(alpha: .25);
    for (var x = 20.0; x < boardSize.width; x += 40) {
      for (var y = 20.0; y < boardSize.height; y += 40) {
        c.drawCircle(Offset(x, y), 2.2, h);
      }
    }
    // frame
    c.drawRect(r.deflate(3), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF7A6340));
    // DIN rail behind the board head
    final rail = Rect.fromLTWH(170, 60, 230, 14);
    c.drawRect(rail, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE8EAEE), Color(0xFF9CA2AA), Color(0xFFD5D8DD)]).createShader(rail));
  }

  void _paper(Canvas c) {
    final r = Offset.zero & boardSize;
    c.drawRect(r, Paint()..color = const Color(0xFFFDFDFB));
    final g1 = Paint()
      ..color = const Color(0xFF9EC3F0).withValues(alpha: .35)
      ..strokeWidth = .6;
    final g2 = Paint()
      ..color = const Color(0xFF6FA3E6).withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= boardSize.width; x += 10) {
      c.drawLine(Offset(x, 0), Offset(x, boardSize.height), x % 50 == 0 ? g2 : g1);
    }
    for (var y = 0.0; y <= boardSize.height; y += 10) {
      c.drawLine(Offset(0, y), Offset(boardSize.width, y), y % 50 == 0 ? g2 : g1);
    }
    c.drawRect(r.deflate(8), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF1B2A4A));
  }

  // --------------------------------------------------------------------- wires
  void _wires(Canvas c) {
    for (var i = 0; i < s.wires.length; i++) {
      final w = s.wires[i];
      final a = _tp(s, w.a), b = _tp(s, w.b);
      if (a == null || b == null) continue;
      final path = wirePath(a, b, i, st.skin);
      final col = wireColor(w.color);
      final sel = st.selWire == i;
      if (st.skin == Skin.board) {
        if (sel) {
          c.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..color = const Color(0xFFFFD66B).withValues(alpha: .7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        }
        c.drawPath(path.shift(const Offset(1.5, 3)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.black.withValues(alpha: .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(col, Colors.black, .35)!);
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.8
          ..strokeCap = StrokeCap.round
          ..color = col);
        if (w.color == WireColor.earth) {
          // yellow stripes of the green/yellow earth conductor
          final dash = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.8
            ..color = const Color(0xFFF3D21F);
          for (final m in path.computeMetrics()) {
            for (var d = 0.0; d < m.length; d += 16) {
              c.drawPath(m.extractPath(d, math.min(d + 7, m.length)), dash);
            }
          }
        }
        c.drawPath(path.shift(const Offset(-1, -1.2)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = Colors.white.withValues(alpha: .35));
        // stripped copper ends
        for (final e in [a, b]) {
          c.drawCircle(e, 3.2, Paint()..color = const Color(0xFFD08A3E));
        }
      } else {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 3.4 : 2
          ..color = sel ? const Color(0xFFE39A00) : Color.lerp(col, const Color(0xFF1B2A4A), .25)!;
        c.drawPath(path, paint);
        // current flow: moving dots on wires that sit at phase voltage while power is on
        if (s.power && r.live(w.a) && r.live(w.b)) {
          for (final m in path.computeMetrics()) {
            final off = (st.t * 60) % 18;
            for (var d = off; d < m.length; d += 18) {
              c.drawCircle(m.getTangentForOffset(d)!.position, 1.8, Paint()..color = const Color(0xFFFF7A00));
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ terminals
  void _terms(Canvas c) {
    final pulse = .5 + .5 * math.sin(st.t * 6);
    for (final p in s.parts) {
      for (final t in p.type.terms) {
        final key = '${p.id}.${t.id}';
        final o = p.pos + t.pos;
        if (st.glowTerms.contains(key)) {
          c.drawCircle(o, 11 + 4 * pulse, Paint()..color = const Color(0xFFFFC107).withValues(alpha: .35 + .3 * pulse));
          c.drawCircle(o, 11 + 4 * pulse, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFFFF8F00));
        }
        if (st.selTerm == key) {
          c.drawCircle(o, 12, Paint()..color = const Color(0xFF2E7DFF).withValues(alpha: .35));
          c.drawCircle(o, 12, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xFF2E7DFF));
        }
        if (st.skin == Skin.board) {
          // brass screw terminal
          c.drawCircle(o, 6.2, Paint()..shader = const RadialGradient(center: Alignment(-.4, -.4), colors: [Color(0xFFFFF0B5), Color(0xFFC9A13A), Color(0xFF7D5E17)]).createShader(Rect.fromCircle(center: o, radius: 6.2)));
          final slot = Paint()
            ..color = const Color(0xFF5A4210)
            ..strokeWidth = 1.4;
          c.drawLine(o + const Offset(-3.5, 1.5), o + const Offset(3.5, -1.5), slot);
        } else {
          c.drawCircle(o, 3.4, Paint()..color = const Color(0xFF1B2A4A));
        }
        if (st.showLabels && p.type.terms.length > 1) {
          final above = t.pos.dy > p.type.size.height / 2;
          text(c, t.label, o + Offset(0, above ? -13 : 13), size: 8.5, color: st.skin == Skin.board ? const Color(0xFF3A3A3A) : const Color(0xFF1B4FA0));
        }
      }
    }
  }

  void _probes(Canvas c) {
    for (var i = 0; i < st.probes.length; i++) {
      final o = _tp(s, st.probes[i]);
      if (o == null) continue;
      final col = i == 0 ? const Color(0xFFE53935) : const Color(0xFF222222);
      final tip = o + const Offset(0, -4);
      c.drawLine(tip, tip + const Offset(-18, -40), Paint()
        ..color = col
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round);
      c.drawLine(tip, tip + const Offset(-6, -14), Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 2);
    }
  }

  // light spilling from lamps on the board
  void _lightGlow(Canvas c) {
    if (st.skin != Skin.board) return;
    for (final p in s.parts) {
      double b = 0;
      Offset at = p.pos;
      double rad = 120;
      if (p.kind == Kind.lamp) {
        b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.3);
        at = p.pos + const Offset(40, 36);
        rad = 70 + 90 * b;
      } else if (p.kind == Kind.tube && r.tubes.contains(p.id)) {
        b = .8;
        at = p.pos + Offset(p.type.size.width / 2, 25);
        rad = 170;
      } else if (p.kind == Kind.ledpanel && r.panels.contains(p.id)) {
        b = 1;
        at = p.pos + const Offset(60, 52);
        rad = 150;
      }
      if (b < .02) continue;
      final warm = p.kind == Kind.lamp && !p.led;
      final col = warm ? const Color(0xFFFFD27A) : const Color(0xFFF4F8FF);
      c.drawCircle(at, rad, Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(colors: [col.withValues(alpha: .55 * math.min(1, b)), col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: rad)));
    }
  }

  // -------------------------------------------------------- realistic parts
  void _part(Canvas c, Part p) {
    final sz = p.type.size;
    final box = Offset.zero & sz;
    final sel = st.selPart == p.id;
    if (sel) {
      c.drawRRect(_rr(box.inflate(6), 12), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2E7DFF));
    }
    switch (p.kind) {
      case Kind.supply:
        final blown = s.fuseBlown;
        plastic(c, box, top: const Color(0xFF3A4150), bottom: const Color(0xFF1E232C));
        text(c, 'مصدر 220V', Offset(sz.width / 2, 16), color: Colors.white, size: 12, w: FontWeight.w700);
        final lamp = Offset(sz.width - 16, 16);
        c.drawCircle(lamp, 6, Paint()..color = s.power && !blown ? const Color(0xFFFF3B30) : const Color(0xFF5A2020));
        if (s.power && !blown) c.drawCircle(lamp, 12, Paint()..color = const Color(0x55FF3B30));
        // fuse window
        final f = Rect.fromLTWH(12, 30, 46, 18);
        c.drawRRect(_rr(f, 4), Paint()..color = const Color(0xFFE8E8E8));
        c.drawLine(f.centerLeft + const Offset(4, 0), f.centerRight - const Offset(4, 0), Paint()
          ..color = blown ? const Color(0xFF333333) : const Color(0xFFB0B0B0)
          ..strokeWidth = 2);
        if (blown) text(c, 'فيوز محروق', Offset(sz.width - 30, 40), size: 8, color: const Color(0xFFFF8A80));
        for (final t in [('L', const Color(0xFF8A4B22)), ('N', const Color(0xFF1F6FD8)), ('PE', const Color(0xFF2FA84F))]) {
          final o = p.type.term(t.$1).pos;
          c.drawRRect(_rr(Rect.fromCenter(center: o, width: 22, height: 22), 4), Paint()..color = t.$2.withValues(alpha: .55));
        }
      case Kind.mcb:
        final open = s.tripped.contains(p.id) || s.hasFault(FaultKind.mcbFaulty, p.id);
        plastic(c, box, radius: 4);
        c.drawRect(Rect.fromLTWH(0, 22, sz.width, 66), Paint()..color = const Color(0xFFF2F2F4));
        final lever = Rect.fromLTWH(sz.width / 2 - 9, open ? 58 : 32, 18, 22);
        c.drawRRect(_rr(Rect.fromLTWH(sz.width / 2 - 11, 30, 22, 52), 3), Paint()..color = const Color(0xFF2B2B2B));
        c.drawRRect(_rr(lever, 3), Paint()..shader = LinearGradient(colors: open ? [const Color(0xFF9E9E9E), const Color(0xFF616161)] : [const Color(0xFF4A90E2), const Color(0xFF1D5DB0)]).createShader(lever));
        text(c, 'C${p.rating}', Offset(sz.width / 2, 92), size: 9, color: Colors.black87, w: FontWeight.w700);
        c.drawRect(Rect.fromLTWH(sz.width / 2 - 8, 24, 16, 4), Paint()..color = open ? const Color(0xFF4CAF50) : const Color(0xFFE53935));
      case Kind.rcd:
        final open = s.tripped.contains(p.id);
        plastic(c, box, radius: 4);
        c.drawRect(Rect.fromLTWH(0, 22, sz.width, 66), Paint()..color = const Color(0xFFF2F2F4));
        c.drawRRect(_rr(Rect.fromLTWH(12, 30, 22, 52), 3), Paint()..color = const Color(0xFF2B2B2B));
        c.drawRRect(_rr(Rect.fromLTWH(14, open ? 58 : 32, 18, 22), 3), Paint()..color = open ? const Color(0xFF757575) : const Color(0xFF1D5DB0));
        c.drawCircle(const Offset(64, 44), 9, Paint()..color = const Color(0xFFF5C400));
        text(c, 'T', const Offset(64, 44), size: 10, w: FontWeight.w700);
        text(c, '30mA', const Offset(64, 70), size: 9);
        text(c, 'RCD', const Offset(64, 82), size: 8, color: Colors.black54);
      case Kind.meter:
        plastic(c, box, top: const Color(0xFFF4F4F2), bottom: const Color(0xFFC9CCD1));
        final lcd = Rect.fromLTWH(14, 18, sz.width - 28, 34);
        c.drawRRect(_rr(lcd, 4), Paint()..color = const Color(0xFF9DB89A));
        final w = r.meterW[p.id] ?? 0;
        text(c, '${w.toStringAsFixed(0)} W', lcd.center, size: 14, color: const Color(0xFF1C2A1C), w: FontWeight.w700);
        text(c, 'kWh  00${(1234 + st.t * w / 3600000).toStringAsFixed(3)}', const Offset(60, 64), size: 8.5, color: Colors.black54);
        final led = w > 1 && (st.t * w / 50) % 1 < .2;
        c.drawCircle(const Offset(98, 82), 4, Paint()..color = led ? const Color(0xFFFF1744) : const Color(0xFF6D2A2A));
        text(c, 'عداد', const Offset(40, 84), size: 10, color: Colors.black54);
        c.drawRect(Rect.fromLTWH(4, 124, sz.width - 8, 24), Paint()..color = const Color(0xFF3B3F46));
      case Kind.nbar:
      case Kind.ebar:
        final isN = p.kind == Kind.nbar;
        plastic(c, box, radius: 5, top: isN ? const Color(0xFF3B7DE0) : const Color(0xFF3BB560), bottom: isN ? const Color(0xFF1C4FA0) : const Color(0xFF1E7A3A));
        final bar = Rect.fromLTWH(6, 10, sz.width - 12, 14);
        c.drawRect(bar, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE08A), Color(0xFFC99A2E)]).createShader(bar));
      case Kind.jbox:
        plastic(c, box, radius: 10, top: const Color(0xFFBFC3C8), bottom: const Color(0xFF8E949B));
        c.drawRRect(_rr(box.deflate(10), 8), Paint()..color = const Color(0xFF6E747C));
        for (final t in p.type.terms) {
          c.drawRRect(_rr(Rect.fromCenter(center: t.pos, width: 26, height: 18), 3), Paint()..color = const Color(0xFFF5F5F5));
        }
      case Kind.sw1:
      case Kind.dimmer:
      case Kind.sw2:
      case Kind.swi:
      case Kind.swd:
        _switch(c, p, sz);
      case Kind.pb:
        plastic(c, box);
        c.drawCircle(const Offset(35, 28), 16, Paint()..color = const Color(0xFFE6E7EB));
        c.drawCircle(const Offset(35, 28), p.on ? 10 : 12, Paint()..shader = RadialGradient(colors: p.on ? [const Color(0xFFFFE082), const Color(0xFFFFA000)] : [const Color(0xFFFFFFFF), const Color(0xFFBDBDBD)]).createShader(Rect.fromCircle(center: const Offset(35, 28), radius: 12)));
        text(c, '🔔', const Offset(35, 28), size: 9);
      case Kind.lamp:
        _lamp(c, p, sz);
      case Kind.socket:
        plastic(c, box);
        c.drawRRect(_rr(Rect.fromLTWH(13, 8, 60, 52), 26), Paint()..color = const Color(0xFFEDEEF1));
        c.drawCircle(const Offset(31, 34), 4.5, Paint()..color = const Color(0xFF2A2A2A));
        c.drawCircle(const Offset(55, 34), 4.5, Paint()..color = const Color(0xFF2A2A2A));
        c.drawRect(const Rect.fromLTWH(40, 9, 6, 6), Paint()..color = const Color(0xFFB0B0B0));
        c.drawRect(const Rect.fromLTWH(40, 53, 6, 6), Paint()..color = const Color(0xFFB0B0B0));
        if (p.plug) {
          final on = r.sockets[p.id] ?? false;
          c.drawCircle(const Offset(43, 34), 20, Paint()..color = const Color(0xFF212121));
          c.drawCircle(const Offset(43, 34), 5, Paint()..color = on ? const Color(0xFF00E676) : const Color(0xFF424242));
          text(c, 'حمل 1kW', const Offset(43, 64), size: 8);
        }
      case Kind.bell:
        final ring = r.bells.contains(p.id);
        final dx = ring ? math.sin(st.t * 90) * 1.5 : 0.0;
        plastic(c, Rect.fromLTWH(10, 50, 60, 24), radius: 4, top: const Color(0xFF555B66), bottom: const Color(0xFF2C3038));
        final dome = Rect.fromCircle(center: Offset(40 + dx, 30), radius: 26);
        c.drawOval(dome, Paint()..shader = const RadialGradient(center: Alignment(-.4, -.5), colors: [Color(0xFFFFB3A7), Color(0xFFD32F2F), Color(0xFF7F1010)]).createShader(dome));
        c.drawCircle(Offset(40 + dx, 30), 4, Paint()..color = const Color(0xFF3A0A0A));
        if (ring) {
          final ar = Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFFF7043)
            ..strokeWidth = 2;
          for (var k = 0; k < 2; k++) {
            c.drawArc(Rect.fromCircle(center: const Offset(40, 30), radius: 34.0 + k * 7), -2.4, .8, false, ar);
            c.drawArc(Rect.fromCircle(center: const Offset(40, 30), radius: 34.0 + k * 7), -1.55, .8, false, ar);
          }
        }
      case Kind.lock:
        final open = r.locks.contains(p.id);
        plastic(c, box, top: const Color(0xFFD7DBE0), bottom: const Color(0xFF8C939C));
        c.drawRRect(_rr(Rect.fromLTWH(10, 10, 50, 70), 5), Paint()..color = const Color(0xFF9AA1AA));
        final bolt = Rect.fromLTWH(open ? 34 : 50, 34, 26, 16);
        c.drawRect(bolt, Paint()..shader = const LinearGradient(colors: [Color(0xFFE0E0E0), Color(0xFF9E9E9E)]).createShader(bolt));
        text(c, open ? 'مفتوح' : 'مقفول', const Offset(35, 66), size: 9, color: open ? const Color(0xFF1B5E20) : Colors.black87);
      case Kind.tube:
        _tube(c, p, sz);
      case Kind.ballast:
        plastic(c, box, radius: 3, top: const Color(0xFF4A4F57), bottom: const Color(0xFF25282D));
        text(c, 'BALLAST ${p.watts}W', Offset(sz.width / 2, 22), size: 9, color: Colors.white70);
      case Kind.starter:
        final rr = Rect.fromLTWH(10, 4, 30, 42);
        c.drawRRect(_rr(rr, 8), Paint()..shader = const LinearGradient(colors: [Color(0xFF64B5F6), Color(0xFF1565C0)]).createShader(rr));
        text(c, 'S', const Offset(25, 24), size: 12, color: Colors.white, w: FontWeight.w700);
        final glowing = r.volts('${p.id}.1') > 90 && !s.hasFault(FaultKind.starterDead, p.id);
        if (glowing && (st.t * 7).floor() % 2 == 0) c.drawCircle(const Offset(25, 14), 5, Paint()..color = const Color(0xFFFF9100));
      case Kind.stair:
        plastic(c, box, radius: 4);
        final left = s.stairLeft[p.id] ?? 0;
        c.drawCircle(const Offset(30, 40), 5, Paint()..color = left > 0 ? const Color(0xFF00E676) : const Color(0xFF2E4F3A));
        text(c, left > 0 ? left.toStringAsFixed(0) : '⏱', const Offset(30, 60), size: 12, w: FontWeight.w700);
        text(c, 'TIMER', const Offset(30, 80), size: 8, color: Colors.black54);
      case Kind.driver:
        plastic(c, box, radius: 4, top: const Color(0xFFF7F7F7), bottom: const Color(0xFFCFD3D8));
        text(c, 'LED DRIVER', Offset(sz.width / 2, 18), size: 9, w: FontWeight.w700);
        text(c, 'AC220V → DC', Offset(sz.width / 2, 32), size: 8, color: Colors.black54);
      case Kind.ledpanel:
        final on = r.panels.contains(p.id);
        plastic(c, box.deflate(4), radius: 6, top: const Color(0xFFEDEFF2), bottom: const Color(0xFFBFC4CA));
        final inner = Rect.fromLTWH(14, 14, 92, 76);
        c.drawRRect(_rr(inner, 4), Paint()..color = on ? const Color(0xFFFFFFFF) : const Color(0xFFDDE3EA));
        if (on) c.drawRRect(_rr(inner.inflate(6), 8), Paint()..color = const Color(0x88E3F2FF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    if (st.showLabels) {
      text(c, p.id, Offset(sz.width - 2, -8), size: 10, color: const Color(0xFF0D2B66), w: FontWeight.w700);
    }
  }

  void _switch(Canvas c, Part p, Size sz) {
    final box = Offset.zero & sz;
    plastic(c, box);
    final inner = Rect.fromLTWH(12, 8, sz.width - 24, 52);
    c.drawRRect(_rr(inner, 6), Paint()..color = const Color(0xFFE9EAEE));
    switch (p.kind) {
      case Kind.dimmer:
        c.drawCircle(inner.center, 20, Paint()..shader = const RadialGradient(center: Alignment(-.3, -.3), colors: [Colors.white, Color(0xFFB8BCC4)]).createShader(Rect.fromCircle(center: inner.center, radius: 20)));
        final ang = -math.pi * .75 + p.level * math.pi * 1.5;
        c.drawLine(inner.center, inner.center + Offset(math.cos(ang - math.pi / 2), math.sin(ang - math.pi / 2)) * 16, Paint()
          ..color = const Color(0xFF424242)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
        text(c, '${(p.level * 100).round()}%', Offset(inner.center.dx, inner.bottom - 2), size: 7.5, color: Colors.black54);
      case Kind.swd:
        _rocker(c, Rect.fromLTWH(inner.left + 4, inner.top + 4, inner.width / 2 - 6, inner.height - 8), p.on);
        _rocker(c, Rect.fromLTWH(inner.center.dx + 2, inner.top + 4, inner.width / 2 - 6, inner.height - 8), p.on2);
      default:
        _rocker(c, inner.deflate(5), p.on);
        if (p.kind == Kind.sw2) text(c, '⇅', Offset(inner.right - 6, inner.top + 8), size: 8, color: Colors.black45);
        if (p.kind == Kind.swi) text(c, '✕', Offset(inner.right - 6, inner.top + 8), size: 8, color: Colors.black45);
    }
  }

  void _rocker(Canvas c, Rect r, bool on) {
    c.drawRRect(_rr(r, 4), Paint()..color = const Color(0xFFCDD0D6));
    final top = Rect.fromLTWH(r.left, r.top, r.width, r.height / 2);
    final bot = Rect.fromLTWH(r.left, r.center.dy, r.width, r.height / 2);
    final pressed = on ? top : bot;
    final raised = on ? bot : top;
    c.drawRect(raised, Paint()..shader = LinearGradient(begin: on ? Alignment.bottomCenter : Alignment.topCenter, end: on ? Alignment.topCenter : Alignment.bottomCenter, colors: const [Colors.white, Color(0xFFE2E4E8)]).createShader(raised));
    c.drawRect(pressed, Paint()..color = const Color(0xFFC3C6CC));
    c.drawLine(r.centerLeft, r.centerRight, Paint()..color = Colors.black26);
    if (on) c.drawCircle(Offset(r.center.dx, top.center.dy), 2, Paint()..color = const Color(0xFFE53935));
  }

  void _lamp(Canvas c, Part p, Size sz) {
    final b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.3);
    final burnt = s.hasFault(FaultKind.lampBurnt, p.id) && st.selPart == '#reveal';
    // ceramic holder base
    final base = Rect.fromLTWH(8, 72, 64, 22);
    plastic(c, base, radius: 6, top: const Color(0xFFF7F3EA), bottom: const Color(0xFFCFC7B6));
    final holder = Rect.fromLTWH(26, 52, 28, 24);
    c.drawRect(holder, Paint()..shader = const LinearGradient(colors: [Color(0xFFDADADA), Color(0xFF9E9E9E), Color(0xFFDADADA)]).createShader(holder));
    // bulb glass
    const g = Offset(40, 30);
    final glass = Path()
      ..addOval(Rect.fromCircle(center: g, radius: 24))
      ..addRect(Rect.fromLTWH(30, 40, 20, 14));
    final warm = !p.led;
    final lit = b > .02;
    final on = Color.lerp(warm ? const Color(0xFFFFF3C4) : const Color(0xFFF7FBFF), warm ? const Color(0xFFFFC94A) : const Color(0xFFE3F0FF), .3)!;
    c.drawPath(glass, Paint()..shader = RadialGradient(center: const Alignment(-.3, -.4), colors: lit ? [Colors.white, on.withValues(alpha: .6 + .4 * math.min(1, b))] : [const Color(0xFFFFFFFF), const Color(0x99D7DEE8)]).createShader(Rect.fromCircle(center: g, radius: 26)));
    c.drawPath(glass, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black.withValues(alpha: .15));
    if (p.led) {
      c.drawRect(Rect.fromLTWH(30, 36, 20, 6), Paint()..color = lit ? Colors.white : const Color(0xFFFFE082));
    } else {
      // filament
      final fil = Path()..moveTo(32, 40);
      for (var i = 0; i < 6; i++) {
        fil.lineTo(33.0 + i * 3, i.isEven ? 26 : 30);
      }
      fil.lineTo(48, 40);
      c.drawPath(fil, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lit ? 1.8 : 1.1
        ..color = burnt ? const Color(0xFF555555) : lit ? Color.lerp(const Color(0xFFFF8F00), Colors.white, math.min(1, b))! : const Color(0xFF8D6E63));
    }
    if (lit) {
      c.drawCircle(g, 18 + 10 * b, Paint()
        ..color = on.withValues(alpha: .55 * math.min(1, b))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 8 * b));
    }
    text(c, '${p.watts}W${p.led ? ' LED' : ''}', const Offset(40, 82), size: 8, color: Colors.black54);
  }

  void _tube(Canvas c, Part p, Size sz) {
    final on = r.tubes.contains(p.id);
    final starting = !on && r.volts('${p.id}.A1') > 90 && (st.t * 5).floor().isEven;
    final body = Rect.fromLTWH(0, 4, sz.width, 42);
    plastic(c, body, radius: 6, top: const Color(0xFFF2F3F5), bottom: const Color(0xFFC5CAD1));
    final tube = Rect.fromLTWH(22, 14, sz.width - 44, 22);
    c.drawRRect(_rr(tube, 11), Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: on ? [Colors.white, const Color(0xFFEAF4FF)] : [const Color(0xFFF9FAFB), const Color(0xFFD5DAE0)]).createShader(tube));
    if (on || starting) {
      c.drawRRect(_rr(tube.inflate(4), 14), Paint()
        ..color = (on ? const Color(0xFFE3F2FF) : const Color(0xFFFFE0B2)).withValues(alpha: on ? .9 : .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    for (final x in [22.0, sz.width - 22]) {
      c.drawRect(Rect.fromCenter(center: Offset(x, 25), width: 8, height: 26), Paint()..color = const Color(0xFF9E9E9E));
    }
    text(c, '${p.watts}W', Offset(sz.width / 2, 25), size: 9, color: Colors.black45);
  }

  // -------------------------------------------------------------- IEC symbols
  void _symbol(Canvas c, Part p) {
    final sz = p.type.size;
    const ink = Color(0xFF1B2A4A);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ink;
    final hot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFFE39A00);
    Offset tp(String t) => p.type.term(t).pos;
    void lead(String t, Offset to) => c.drawLine(tp(t), to, pen);
    final mid = Offset(sz.width / 2, sz.height / 2);
    if (st.selPart == p.id) {
      c.drawRect((Offset.zero & sz).inflate(4), Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF2E7DFF));
    }
    switch (p.kind) {
      case Kind.supply:
        c.drawRect(Rect.fromLTWH(10, 10, sz.width - 20, 46), pen);
        text(c, '~ 220V 50Hz', Offset(sz.width / 2, 24), size: 11, color: ink);
        text(c, s.fuseBlown ? 'فيوز محروق' : 'L  N  PE', Offset(sz.width / 2, 44), size: 9, color: s.fuseBlown ? Colors.red : ink);
        for (final t in ['L', 'N', 'PE']) {
          lead(t, Offset(tp(t).dx, 56));
        }
      case Kind.mcb:
        final open = s.tripped.contains(p.id) || s.hasFault(FaultKind.mcbFaulty, p.id);
        lead('in', const Offset(23, 40));
        lead('out', const Offset(23, 70));
        c.drawLine(const Offset(23, 70), open ? const Offset(8, 42) : const Offset(23, 40), pen);
        c.drawLine(const Offset(18, 40), const Offset(28, 40), pen);
        c.drawRect(const Rect.fromLTWH(28, 50, 8, 8), pen);
        text(c, 'C${p.rating}', const Offset(8, 85), size: 9, color: ink);
      case Kind.rcd:
        final open = s.tripped.contains(p.id);
        for (final x in [25.0, 65.0]) {
          c.drawLine(Offset(x, 10), Offset(x, 40), pen);
          c.drawLine(Offset(x, 100), Offset(x, 70), pen);
          c.drawLine(Offset(x, 70), open ? Offset(x - 14, 44) : Offset(x, 40), pen);
        }
        c.drawOval(const Rect.fromLTWH(14, 76, 62, 14), pen);
        text(c, 'IΔn 30mA', const Offset(45, 60), size: 8.5, color: ink);
      case Kind.meter:
        c.drawRect(Rect.fromLTWH(8, 10, sz.width - 16, 100), pen);
        text(c, 'kWh', Offset(sz.width / 2, 48), size: 16, color: ink, w: FontWeight.w700);
        text(c, '${(r.meterW[p.id] ?? 0).toStringAsFixed(0)} W', Offset(sz.width / 2, 78), size: 11, color: const Color(0xFF1B4FA0));
        for (final t in p.type.terms) {
          lead(t.id, Offset(t.pos.dx, 110));
        }
      case Kind.nbar:
      case Kind.ebar:
        c.drawLine(const Offset(8, 17), Offset(sz.width - 8, 17), Paint()
          ..strokeWidth = 4
          ..color = p.kind == Kind.nbar ? const Color(0xFF1F6FD8) : const Color(0xFF2FA84F));
        text(c, p.kind == Kind.nbar ? 'N' : 'PE ⏚', Offset(sz.width / 2, 4), size: 9, color: ink);
      case Kind.jbox:
        c.drawCircle(mid, 46, pen);
      case Kind.sw1:
      case Kind.dimmer:
        lead('L', const Offset(25, 54));
        lead('1', const Offset(61, 54));
        c.drawLine(const Offset(25, 54), p.on || p.kind == Kind.dimmer ? const Offset(61, 54) : const Offset(55, 30), p.on ? hot : pen);
        if (p.kind == Kind.dimmer) {
          c.drawLine(const Offset(30, 66), const Offset(56, 40), pen);
          text(c, '${(p.level * 100).round()}%', const Offset(43, 20), size: 9, color: ink);
        }
      case Kind.sw2:
        lead('C', const Offset(18, 54));
        lead('1', const Offset(43, 34));
        lead('2', const Offset(68, 34));
        c.drawLine(const Offset(18, 54), p.on ? const Offset(68, 34) : const Offset(43, 34), hot);
      case Kind.swi:
        for (final t in ['A1', 'A2', 'B1', 'B2']) {
          lead(t, Offset(tp(t).dx, 50));
        }
        if (p.on) {
          c.drawLine(const Offset(16, 50), const Offset(70, 30), hot);
          c.drawLine(const Offset(34, 50), const Offset(52, 30), hot);
        } else {
          c.drawLine(const Offset(16, 50), const Offset(52, 30), hot);
          c.drawLine(const Offset(34, 50), const Offset(70, 30), hot);
        }
      case Kind.swd:
        lead('L', const Offset(18, 54));
        lead('1', const Offset(43, 40));
        lead('2', const Offset(68, 40));
        c.drawLine(const Offset(18, 54), p.on ? const Offset(43, 40) : const Offset(36, 24), p.on ? hot : pen);
        c.drawLine(const Offset(18, 54), p.on2 ? const Offset(68, 40) : const Offset(60, 18), p.on2 ? hot : pen);
      case Kind.pb:
        lead('1', const Offset(18, 40));
        lead('2', const Offset(52, 40));
        c.drawLine(Offset(14, p.on ? 40 : 28), Offset(56, p.on ? 40 : 28), pen);
        c.drawLine(Offset(35, p.on ? 40 : 28), const Offset(35, 12), pen);
        c.drawLine(const Offset(28, 12), const Offset(42, 12), pen);
      case Kind.lamp:
        final b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.0);
        const o = Offset(40, 40);
        if (b > .02) c.drawCircle(o, 22, Paint()..color = const Color(0xFFFFD54F).withValues(alpha: .25 + .6 * b));
        c.drawCircle(o, 20, pen);
        c.drawLine(o + const Offset(-14, -14), o + const Offset(14, 14), pen);
        c.drawLine(o + const Offset(14, -14), o + const Offset(-14, 14), pen);
        lead('L', const Offset(25, 54));
        lead('N', const Offset(55, 54));
      case Kind.socket:
        c.drawArc(const Rect.fromLTWH(18, 14, 50, 50), math.pi, math.pi, false, pen);
        c.drawLine(const Offset(18, 39), const Offset(68, 39), pen);
        c.drawLine(const Offset(43, 14), const Offset(43, 4), pen);
        for (final t in ['L', 'N', 'PE']) {
          lead(t, Offset(tp(t).dx, 39));
        }
        if (r.sockets[p.id] ?? false) c.drawCircle(const Offset(43, 30), 4, Paint()..color = const Color(0xFF00C853));
      case Kind.bell:
        final ring = r.bells.contains(p.id);
        c.drawArc(const Rect.fromLTWH(15, 15, 50, 50), math.pi, math.pi, true, ring ? hot : pen);
        lead('1', const Offset(22, 40));
        lead('2', const Offset(58, 40));
      case Kind.lock:
        c.drawRect(const Rect.fromLTWH(15, 30, 40, 40), r.locks.contains(p.id) ? hot : pen);
        text(c, '🔒', const Offset(35, 50), size: 14);
        lead('1', const Offset(20, 70));
        lead('2', const Offset(50, 70));
      case Kind.tube:
        final on = r.tubes.contains(p.id);
        if (on) c.drawRect(Rect.fromLTWH(10, 14, sz.width - 20, 24), Paint()..color = const Color(0x55FFD54F));
        c.drawRect(Rect.fromLTWH(10, 14, sz.width - 20, 24), pen);
        c.drawLine(const Offset(18, 14), const Offset(18, 38), pen);
        c.drawLine(Offset(sz.width - 18, 14), Offset(sz.width - 18, 38), pen);
      case Kind.ballast:
        final path = Path()..moveTo(12, 22);
        for (var i = 0; i < 4; i++) {
          path.arcToPoint(Offset(30.0 + i * 18, 22), radius: const Radius.circular(9));
        }
        path.lineTo(98, 22);
        c.drawPath(path, pen);
        c.drawLine(const Offset(28, 10), const Offset(84, 10), pen);
      case Kind.starter:
        c.drawCircle(const Offset(25, 26), 16, pen);
        c.drawCircle(const Offset(19, 26), 2.5, Paint()..color = ink);
        c.drawCircle(const Offset(31, 26), 2.5, Paint()..color = ink);
        lead('1', const Offset(14, 38));
        lead('2', const Offset(36, 38));
      case Kind.stair:
        c.drawRect(Rect.fromLTWH(4, 22, sz.width - 8, 66), pen);
        text(c, (s.stairLeft[p.id] ?? 0) > 0 ? '${(s.stairLeft[p.id]!).toStringAsFixed(0)}s' : 'T', mid, size: 13, color: ink, w: FontWeight.w700);
        for (final t in p.type.terms) {
          lead(t.id, Offset(t.pos.dx, t.pos.dy < 50 ? 22 : 88));
        }
      case Kind.driver:
        c.drawRect(Rect.fromLTWH(6, 4, sz.width - 12, 42), pen);
        c.drawLine(Offset(sz.width - 6, 4), Offset(6, 46), pen);
        text(c, '~', const Offset(26, 18), size: 14, color: ink);
        text(c, '=', Offset(sz.width - 26, 34), size: 14, color: ink);
      case Kind.ledpanel:
        final on = r.panels.contains(p.id);
        c.drawRect(const Rect.fromLTWH(20, 20, 80, 70), on ? hot : pen);
        c.drawLine(const Offset(48, 60), const Offset(72, 60), pen);
        final tri = Path()
          ..moveTo(52, 42)
          ..lineTo(68, 42)
          ..lineTo(60, 58)
          ..close();
        c.drawPath(tri, pen);
        lead('+', const Offset(45, 90));
        lead('-', const Offset(75, 90));
    }
    text(c, p.id, Offset(sz.width - 4, -6), size: 10, color: const Color(0xFF0D2B66), w: FontWeight.w700);
  }

  @override
  bool shouldRepaint(BoardPainter old) => true;
}

/// Small preview of a part for the component palette.
class PartIcon extends StatelessWidget {
  final Kind kind;
  final double size;
  final Skin skin;
  const PartIcon(this.kind, {this.size = 56, this.skin = Skin.board});
  @override
  Widget build(BuildContext context) {
    final t = partTypes[kind]!;
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        child: SizedBox(
          width: t.size.width + 24,
          height: t.size.height + 24,
          child: CustomPaint(painter: _IconPainter(kind, skin)),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final Kind kind;
  final Skin skin;
  _IconPainter(this.kind, this.skin);
  @override
  void paint(Canvas c, Size size) {
    final p = Part('', kind, const Offset(12, 12), watts: kind == Kind.lamp ? 60 : kind == Kind.tube || kind == Kind.ballast ? 40 : 0);
    final sim = Sim(parts: [p]);
    final st = BoardState(sim: sim, res: SimResult(), skin: skin, t: 0, fx: Fx(), showLabels: false);
    final bp = BoardPainter(st);
    c.save();
    c.translate(12, 12);
    if (skin == Skin.board) {
      bp._part(c, p);
    } else {
      bp._symbol(c, p);
    }
    c.restore();
    for (final t in p.type.terms) {
      final o = p.pos + t.pos;
      c.drawCircle(o, skin == Skin.board ? 5 : 3, Paint()..color = skin == Skin.board ? const Color(0xFFC9A13A) : const Color(0xFF1B2A4A));
    }
  }

  @override
  bool shouldRepaint(_IconPainter o) => false;
}

