import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/board_geom.dart';
import '../../services/sprites.dart';
import '../../sim/diagnose.dart';
import '../../sim/model.dart';
import '../../sim/solver.dart';
import 'fx.dart';
import 'wires.dart';

export 'wires.dart';

/// board = the real devices (Blender renders) on the training board;
/// schematic = the same layout drawn with IEC 60617 symbols (wiring diagram)
enum Skin { board, schematic }

Color wireColor(WireColor c) => switch (c) {
      WireColor.brown => const Color(0xFF7A3E18),
      WireColor.red => const Color(0xFFD7262B),
      WireColor.blue => const Color(0xFF2C7BE5),
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
  final bool mono; // draw every wire black (as on a printed drawing)
  final List<Issue> issues;
  final Offset? dragFrom; // a wire being drawn from a terminal to the finger
  final Offset? dragTo;
  BoardState({
    required this.sim, required this.res, required this.skin, required this.t, this.selTerm, this.selWire, this.selPart,
    this.glowTerms = const {}, required this.fx, this.probes = const [], this.showLabels = true, this.mono = false,
    this.issues = const [], this.dragFrom, this.dragTo,
  });
}

Offset? termPos(Sim s, String key) => termAt(s, key);

final Map<String, TextPainter> _tcache = {};
void text(Canvas c, String s, Offset at, {double size = 11, Color color = Colors.black87, FontWeight w = FontWeight.w600, bool center = true}) {
  final key = '$s|$size|${color.toARGB32()}|${w.value}';
  final tp = _tcache.putIfAbsent(key, () {
    if (_tcache.length > 800) _tcache.clear();
    return TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Cairo', fontSize: size, color: color, fontWeight: w, height: 1.1)),
      textDirection: TextDirection.rtl,
    )..layout();
  });
  tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

/// text on a small rounded tag
void tag(Canvas c, String s, Offset at, {double size = 4.2, Color bg = const Color(0xE61B2A4A), Color fg = Colors.white}) {
  final key = '$s|$size|${fg.toARGB32()}|tag';
  final tp = _tcache.putIfAbsent(key, () => TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: 'Cairo', fontSize: size, color: fg, fontWeight: FontWeight.w700, height: 1.0)),
        textDirection: TextDirection.ltr,
      )..layout());
  final r = Rect.fromCenter(center: at, width: tp.width + size * .9, height: tp.height + size * .35);
  if (bg.a > 0) c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(size * .45)), Paint()..color = bg);
  tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
}

/// the sprite a part shows right now
String spriteFor(Part p, SimResult r, Sim s) {
  switch (p.kind) {
    case Kind.sw1:
      return p.on ? 'sw1_1' : 'sw1_0';
    case Kind.sw2:
      return p.on ? 'sw2_1' : 'sw2_0';
    case Kind.swi:
      return p.on ? 'swi_1' : 'swi_0';
    case Kind.swd:
      return 'swd_${p.on ? 1 : 0}${p.on2 ? 1 : 0}';
    case Kind.pb:
      return p.on ? 'pb_1' : 'pb_0';
    case Kind.lamp:
      return p.led ? 'ledbulb_0' : 'lamp_0';
    case Kind.lock:
      return r.locks.contains(p.id) ? 'lock_1' : 'lock_0';
    default:
      return p.type.sprite;
  }
}

/// Draw a sprite into the part's own (unrotated) box. Variants of the same device
/// are lined up on their first terminal, so the screws never jump.
void drawSprite(Canvas c, Part p, String name, {double opacity = 1}) {
  final img = Sprites.i[name];
  final g = spriteGeom[name];
  if (img == null || g == null) return;
  var off = Offset.zero;
  final base = p.type.geom;
  if (name != p.type.sprite && base.terms.isNotEmpty) {
    final k = base.terms.keys.first;
    final v = g.terms[k];
    if (v != null) off = base.terms[k]! - v;
  }
  final dst = off & Size(g.w, g.h);
  final paint = Paint()..filterQuality = FilterQuality.medium;
  if (opacity < 1) paint.color = Color.fromRGBO(0, 0, 0, opacity.clamp(0, 1));
  c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
}

class BoardPainter extends CustomPainter {
  final BoardState st;
  BoardPainter(this.st) : super(repaint: Sprites.i.ready);

  Sim get s => st.sim;
  SimResult get r => st.res;
  bool get board => st.skin == Skin.board;

  @override
  void paint(Canvas c, Size size) {
    board ? _board(c) : _paper(c);
    for (final p in s.parts) {
      c.save();
      c.translate(p.center.dx, p.center.dy);
      c.rotate(p.rot * math.pi / 2);
      c.translate(-p.type.size.width / 2, -p.type.size.height / 2);
      if (board) {
        _part(c, p);
      } else {
        _symbol(c, p);
      }
      c.restore();
      _partLabel(c, p);
    }
    if (board) _lightGlow(c);
    _wires(c);
    _terms(c);
    _issues(c);
    if (st.dragFrom != null && st.dragTo != null) {
      c.drawLine(st.dragFrom!, st.dragTo!, Paint()
        ..color = const Color(0xFF2E7DFF)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
    }
    st.fx.paint(c);
    _probes(c);
  }

  // --------------------------------------------------------------- backgrounds
  void _board(Canvas c) {
    final r = Offset.zero & boardSize;
    c.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE9EDF2), Color(0xFFC9D0D8)]).createShader(r));
    // perforated training panel
    final h = Paint()..color = const Color(0xFF8D97A3).withValues(alpha: .35);
    final hl = Paint()..color = Colors.white.withValues(alpha: .6);
    for (var x = 12.5; x < boardSize.width; x += 25) {
      for (var y = 12.5; y < boardSize.height; y += 25) {
        c.drawCircle(Offset(x, y + .5), 1.6, hl);
        c.drawCircle(Offset(x, y), 1.5, h);
      }
    }
    c.drawRect(r.deflate(4), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = const Color(0xFF5E6B7A));
  }

  void _paper(Canvas c) {
    final r = Offset.zero & boardSize;
    c.drawRect(r, Paint()..color = const Color(0xFFFDFDFB));
    final g1 = Paint()
      ..color = const Color(0xFF9EC3F0).withValues(alpha: .30)
      ..strokeWidth = .3;
    final g2 = Paint()
      ..color = const Color(0xFF6FA3E6).withValues(alpha: .40)
      ..strokeWidth = .6;
    for (var x = 0.0; x <= boardSize.width; x += 5) {
      c.drawLine(Offset(x, 0), Offset(x, boardSize.height), x % 25 == 0 ? g2 : g1);
    }
    for (var y = 0.0; y <= boardSize.height; y += 5) {
      c.drawLine(Offset(0, y), Offset(boardSize.width, y), y % 25 == 0 ? g2 : g1);
    }
    c.drawRect(r.deflate(6), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF1B2A4A));
  }

  // --------------------------------------------------------------------- wires
  void _wires(Canvas c) {
    final bad = <int>{for (final i in st.issues.where((i) => i.error)) ...i.wires};
    final warn = <int>{for (final i in st.issues.where((i) => !i.error)) ...i.wires};
    final pulse = .5 + .5 * math.sin(st.t * 6);
    for (var i = 0; i < s.wires.length; i++) {
      final w = s.wires[i];
      final pts = wirePoints(s, i);
      if (pts == null) continue;
      final path = roundedPath(pts, rad: board ? 6 : 3);
      final col = st.mono ? const Color(0xFF1D1D1F) : wireColor(w.color);
      final sel = st.selWire == i;
      if (bad.contains(i) || warn.contains(i)) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = board ? 9 : 6
          ..strokeCap = StrokeCap.round
          ..color = (bad.contains(i) ? const Color(0xFFFF1744) : const Color(0xFFFFA000)).withValues(alpha: .25 + .35 * pulse));
      }
      if (sel) {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = board ? 8 : 6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2E7DFF).withValues(alpha: .45));
      }
      if (board) {
        c.drawPath(path.shift(const Offset(1, 2)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..color = Colors.black.withValues(alpha: .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(col, Colors.black, .35)!);
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = col);
        if (w.color == WireColor.earth && !st.mono) {
          final dash = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..color = const Color(0xFFF3D21F);
          for (final m in path.computeMetrics()) {
            for (var d = 0.0; d < m.length; d += 9) {
              c.drawPath(m.extractPath(d, math.min(d + 4, m.length)), dash);
            }
          }
        }
        c.drawPath(path.shift(const Offset(-.4, -.6)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = Colors.white.withValues(alpha: .35));
        // copper end under the screw
        for (final e in [pts.first, pts.last]) {
          c.drawCircle(e, 1.6, Paint()..color = const Color(0xFFD08A3E));
        }
      } else {
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeJoin = StrokeJoin.round
          ..color = st.mono ? const Color(0xFF111111) : Color.lerp(col, const Color(0xFF1B2A4A), .2)!);
      }
      // current flow: moving dots on wires at phase voltage while power is on
      if (s.power && r.live(w.a) && r.live(w.b)) {
        for (final m in path.computeMetrics()) {
          final off = (st.t * 30) % 10;
          for (var d = off; d < m.length; d += 10) {
            c.drawCircle(m.getTangentForOffset(d)!.position, board ? .9 : .8, Paint()..color = const Color(0xFFFFB300));
          }
        }
      }
      // the bends of the selected wire can be dragged
      if (sel && w.pts.isNotEmpty) {
        for (final b in w.pts) {
          c.drawCircle(b, 2.6, Paint()..color = Colors.white);
          c.drawCircle(b, 2.6, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = const Color(0xFF2E7DFF));
        }
      }
    }
  }

  // ------------------------------------------------------------------ terminals
  void _terms(Canvas c) {
    final pulse = .5 + .5 * math.sin(st.t * 6);
    final used = <String>{for (final w in s.wires) ...[w.a, w.b]};
    for (final p in s.parts) {
      for (final t in p.type.terms) {
        final key = '${p.id}.${t.id}';
        final o = p.termPos(t.id);
        if (st.glowTerms.contains(key)) {
          c.drawCircle(o, 5 + 2 * pulse, Paint()..color = const Color(0xFFFFC107).withValues(alpha: .35 + .3 * pulse));
          c.drawCircle(o, 5 + 2 * pulse, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .9
            ..color = const Color(0xFFFF8F00));
        }
        if (st.selTerm == key) {
          c.drawCircle(o, 5.5, Paint()..color = const Color(0xFF2E7DFF).withValues(alpha: .35));
          c.drawCircle(o, 5.5, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF2E7DFF));
        }
        if (!board) {
          c.drawCircle(o, 1.5, Paint()..color = used.contains(key) ? const Color(0xFF1B2A4A) : Colors.white);
          c.drawCircle(o, 1.5, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5
            ..color = const Color(0xFF1B2A4A));
        }
        if (st.showLabels && p.type.terms.length > 1) {
          final d = p.termDir(t.id);
          tag(c, t.label, o - d * 5.2 + Offset(-d.dy, d.dx) * 3.6, size: 3.6, bg: board ? const Color(0xCC263244) : const Color(0x00FFFFFF), fg: board ? Colors.white : const Color(0xFF1B4FA0));
        }
      }
    }
  }

  void _issues(Canvas c) {
    final pulse = .5 + .5 * math.sin(st.t * 6);
    for (final i in st.issues) {
      for (final k in i.terms) {
        final o = termAt(s, k);
        if (o == null) continue;
        final col = i.error ? const Color(0xFFFF1744) : const Color(0xFFFFA000);
        c.drawCircle(o, 5 + 1.5 * pulse, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = col);
        tag(c, '!', o + const Offset(5, -6), size: 4, bg: col);
      }
    }
  }

  void _partLabel(Canvas c, Part p) {
    if (!st.showLabels) return;
    final rc = p.rect;
    tag(c, p.id, Offset(rc.center.dx, rc.top - 3.5), size: 4.6, bg: board ? const Color(0xFF0D2B66) : const Color(0x00FFFFFF), fg: board ? Colors.white : const Color(0xFF0D2B66));
    if (st.selPart == p.id) {
      c.drawRRect(RRect.fromRectAndRadius(rc.inflate(3), const Radius.circular(4)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF2E7DFF));
    }
  }

  void _probes(Canvas c) {
    for (var i = 0; i < st.probes.length; i++) {
      final o = termAt(s, st.probes[i]);
      if (o == null) continue;
      final col = i == 0 ? const Color(0xFFE53935) : const Color(0xFF222222);
      final tip = o + const Offset(0, -1);
      c.drawLine(tip, tip + const Offset(-9, -22), Paint()
        ..color = col
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round);
      c.drawLine(tip, tip + const Offset(-3, -7), Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 1);
    }
  }

  // light spilling from lamps on the board
  void _lightGlow(Canvas c) {
    for (final p in s.parts) {
      double b = 0;
      double rad = 60;
      if (p.kind == Kind.lamp) {
        b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.3);
        rad = 40 + 50 * b;
      } else if (p.kind == Kind.tube && r.tubes.contains(p.id)) {
        b = .8;
        rad = 120;
      } else if (p.kind == Kind.ledpanel && r.panels.contains(p.id)) {
        b = 1;
        rad = 100;
      }
      if (b < .02) continue;
      final at = p.toBoard(p.kind == Kind.lamp ? Offset(p.type.size.width / 2, 32) : Offset(p.type.size.width / 2, p.type.size.height * .42));
      final warm = p.kind == Kind.lamp && !p.led;
      final col = warm ? const Color(0xFFFFD27A) : const Color(0xFFF4F8FF);
      c.drawCircle(at, rad, Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(colors: [col.withValues(alpha: .5 * math.min(1, b)), col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: rad)));
    }
  }

  // -------------------------------------------------------- realistic parts
  void _part(Canvas c, Part p) {
    final sz = p.type.size;
    drawSprite(c, p, spriteFor(p, r, s));
    switch (p.kind) {
      case Kind.supply:
        if (!s.power || s.fuseBlown) {
          c.drawCircle(const Offset(105.5, 17.5), 6.5, Paint()..color = const Color(0xFF3A1010));
        }
        if (s.fuseBlown) tag(c, 'فيوز محروق', Offset(sz.width / 2, -6), size: 5, bg: const Color(0xFFD32F2F));
      case Kind.mcb:
      case Kind.rcd:
        final open = s.tripped.contains(p.id) || (p.kind == Kind.mcb && s.hasFault(FaultKind.mcbFaulty, p.id));
        if (open) {
          // the lever down: cover the toggle area and draw it in the OFF position
          final slot = Rect.fromLTWH(sz.width / 2 - 6, sz.height * .36, 12, sz.height * .26);
          c.drawRRect(RRect.fromRectAndRadius(slot.inflate(1), const Radius.circular(2)), Paint()..color = const Color(0xFFE9EAEC));
          c.drawRRect(RRect.fromRectAndRadius(slot, const Radius.circular(2)), Paint()..color = const Color(0xFF2B2B2B));
          final lever = Rect.fromLTWH(slot.left + 1.5, slot.bottom - 10, slot.width - 3, 9);
          c.drawRRect(RRect.fromRectAndRadius(lever, const Radius.circular(1.5)), Paint()..color = const Color(0xFF8E9AA6));
          tag(c, 'OFF', Offset(sz.width / 2, sz.height * .33), size: 3.4, bg: const Color(0xFF2E7D32));
        }
        if (p.kind == Kind.mcb) tag(c, 'C${p.rating}', Offset(sz.width / 2, sz.height + 4), size: 3.8);
      case Kind.meter:
        final w = r.meterW[p.id] ?? 0;
        tag(c, '${w.toStringAsFixed(0)} W', Offset(sz.width / 2, -5), size: 4.4, bg: const Color(0xFF1C3A1C), fg: const Color(0xFFB9F6CA));
        if (w > 1 && (st.t * w / 50) % 1 < .2) c.drawCircle(Offset(sz.width - 8, sz.height * .25), 1.4, Paint()..color = const Color(0xFFFF1744));
      case Kind.dimmer:
        final cc = Offset(sz.width / 2, 43);
        final ang = -math.pi * .75 + p.level * math.pi * 1.5;
        c.drawLine(cc, cc + Offset(math.cos(ang - math.pi / 2), math.sin(ang - math.pi / 2)) * 11, Paint()
          ..color = const Color(0xFF424242)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);
        tag(c, '${(p.level * 100).round()}%', Offset(sz.width / 2, 72), size: 4);
      case Kind.lamp:
        final b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.3);
        final burnt = s.hasFault(FaultKind.lampBurnt, p.id) && st.selPart == '#reveal';
        if (b > .02) drawSprite(c, p, p.led ? 'ledbulb_1' : 'lamp_1', opacity: math.min(1, b));
        if (burnt) tag(c, 'محروقة', Offset(sz.width / 2, 30), size: 5, bg: const Color(0xFF424242));
        tag(c, '${p.watts}W${p.led ? ' LED' : ''}', Offset(sz.width / 2, sz.height - 26), size: 3.8, bg: const Color(0x99000000));
      case Kind.socket:
        if (p.plug) {
          final on = r.sockets[p.id] ?? false;
          const cc = Offset(44.5, 43);
          c.drawCircle(cc + const Offset(1, 2), 19, Paint()..color = Colors.black26);
          c.drawCircle(cc, 19, Paint()..shader = const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFF4A4A4A), Color(0xFF151515)]).createShader(Rect.fromCircle(center: cc, radius: 19)));
          c.drawLine(cc + const Offset(0, 19), cc + const Offset(0, 30), Paint()
            ..color = const Color(0xFF151515)
            ..strokeWidth = 5);
          c.drawCircle(cc, 3, Paint()..color = on ? const Color(0xFF00E676) : const Color(0xFF424242));
          tag(c, 'حمل 1kW', cc + const Offset(0, -12), size: 3.6, bg: const Color(0x00000000));
        }
      case Kind.bell:
        if (r.bells.contains(p.id)) {
          final ar = Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFFF7043)
            ..strokeWidth = 1.4;
          final cc = Offset(sz.width / 2, 30);
          final k = (st.t * 8) % 1;
          for (var j = 0; j < 2; j++) {
            final rr = 33.0 + j * 6 + k * 3;
            c.drawArc(Rect.fromCircle(center: cc, radius: rr), -2.6, .9, false, ar);
            c.drawArc(Rect.fromCircle(center: cc, radius: rr), -1.4, .9, false, ar);
          }
        }
      case Kind.tube:
        final on = r.tubes.contains(p.id);
        final starting = !on && r.volts('${p.id}.A1') > 90 && (st.t * 5).floor().isEven;
        if (on || starting) drawSprite(c, p, 'tube_1', opacity: on ? 1 : .45);
      case Kind.ledpanel:
        if (r.panels.contains(p.id)) drawSprite(c, p, 'ledpanel_1');
      case Kind.starter:
        final glowing = r.volts('${p.id}.1') > 90 && !s.hasFault(FaultKind.starterDead, p.id);
        if (glowing && (st.t * 7).floor() % 2 == 0) {
          c.drawCircle(Offset(sz.width / 2, 22), 6, Paint()
            ..color = const Color(0xCCFF9100)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        }
      case Kind.stair:
        final left = s.stairLeft[p.id] ?? 0;
        if (left > 0) {
          c.drawCircle(Offset(sz.width / 2, 55), 2, Paint()..color = const Color(0xFF00E676));
          tag(c, '${left.ceil()}s', Offset(sz.width / 2, sz.height / 2), size: 5, bg: const Color(0xFF1B5E20));
        }
      case Kind.ballast:
        tag(c, '${p.watts}W', Offset(sz.width / 2, sz.height + 4), size: 3.8);
      default:
        break;
    }
  }

  // -------------------------------------------------------------- IEC symbols
  // Each symbol is drawn in the part's own box with the terminals where the real
  // device has them (bottom strip), so the drawing and the board share every wire.
  void _symbol(Canvas c, Part p) {
    final sz = p.type.size;
    const ink = Color(0xFF1B2A4A);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = ink;
    final live = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE65100);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = ink;
    final dashP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = ink;
    Offset tp(String t) => p.type.term(t).pos;
    bool hot(String t) => s.power && r.live('${p.id}.$t');
    Paint pk(String t) => hot(t) ? live : pen;
    void poly(List<Offset> pts, Paint pa) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      c.drawPath(path, pa);
    }

    void dashed(Offset a, Offset b) {
      final d = (b - a).distance;
      if (d < .1) return;
      final u = (b - a) / d;
      for (var k = 0.0; k < d; k += 2.4) {
        c.drawLine(a + u * k, a + u * math.min(d, k + 1.3), dashP);
      }
    }

    // a make contact: pivot [a] (wired), fixed contact [b] with its stop tick.
    // open = the blade lifted 30° away from b (IEC 60617 S00227)
    void make(Offset a, Offset b, bool closed, Paint blade, {bool breaker = false}) {
      final v = b - a;
      final n = Offset(-v.dy, v.dx) / v.distance;
      c.drawLine(b - n * 2.2, b, pen); // stop tick on the fixed contact
      if (breaker) {
        c.drawLine(b + const Offset(-1.6, -1.6), b + const Offset(1.6, 1.6), pen);
        c.drawLine(b + const Offset(1.6, -1.6), b + const Offset(-1.6, 1.6), pen);
      }
      const ang = -.52;
      final end = closed ? b : a + Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang), v.dx * math.sin(ang) + v.dy * math.cos(ang));
      c.drawLine(a, end, blade);
      c.drawCircle(a, .9, Paint()..color = ink);
    }

    // the hand actuator of a switch: dashed link from the blade to a small handle
    void hand(Offset from, double up) {
      dashed(from, from + Offset(0, -up));
      final h = from + Offset(0, -up);
      c.drawLine(h + const Offset(-3, 0), h + const Offset(3, 0), pen);
      c.drawLine(h + const Offset(-3, 0), h + const Offset(-3, 2), pen);
    }

    switch (p.kind) {
      case Kind.supply:
        final box = Rect.fromLTWH(8, 8, sz.width - 16, 44);
        c.drawRect(box, pen);
        text(c, '~ 220V 50Hz', Offset(sz.width / 2, 20), size: 7, color: ink);
        text(c, s.fuseBlown ? 'فيوز محروق' : (s.power ? 'التغذية شغالة' : 'التغذية مفصولة'), Offset(sz.width / 2, 36), size: 5.5, color: s.fuseBlown ? Colors.red : ink);
        for (final t in ['L', 'N', 'PE']) {
          c.drawLine(tp(t), Offset(tp(t).dx, box.bottom), pk(t));
        }
        _earthSym(c, Offset(tp('PE').dx + 9, tp('PE').dy - 6), pen);
      case Kind.mcb:
        // circuit breaker: contact with × on the fixed contact, thermal + magnetic release
        final open = s.tripped.contains(p.id) || s.hasFault(FaultKind.mcbFaulty, p.id);
        final x = tp('in').dx;
        final top = Offset(x, 34), bot = Offset(x, 58);
        c.drawLine(tp('in'), top, pk('in'));
        c.drawLine(tp('out'), bot, pk('out'));
        make(bot, top, !open, hot('out') ? live : pen, breaker: true);
        text(c, 'C${p.rating}', Offset(x, 70), size: 5, color: ink);
      case Kind.rcd:
        final open = s.tripped.contains(p.id);
        for (final pr in [('Li', 'Lo'), ('Ni', 'No')]) {
          final x = tp(pr.$1).dx;
          c.drawLine(tp(pr.$1), Offset(x, 32), pk(pr.$1));
          c.drawLine(tp(pr.$2), Offset(x, 56), pk(pr.$2));
          make(Offset(x, 56), Offset(x, 32), !open, pen);
        }
        dashed(Offset(tp('Li').dx, 44), Offset(tp('Ni').dx, 44));
        c.drawOval(Rect.fromCenter(center: Offset(sz.width / 2, 66), width: sz.width - 6, height: 6), pen);
        text(c, 'IΔn 30mA', Offset(sz.width / 2, 76), size: 4.2, color: ink);
      case Kind.meter:
        final box = Rect.fromLTWH(3, 24, sz.width - 6, 46);
        c.drawRect(box, pen);
        text(c, 'kWh', Offset(sz.width / 2, 40), size: 7, color: ink, w: FontWeight.w700);
        text(c, '${(r.meterW[p.id] ?? 0).toStringAsFixed(0)} W', Offset(sz.width / 2, 56), size: 5, color: const Color(0xFF1B4FA0));
        for (final t in p.type.terms) {
          c.drawLine(t.pos, Offset(t.pos.dx, t.pos.dy < sz.height / 2 ? box.top : box.bottom), pk(t.id));
        }
      case Kind.nbar:
      case Kind.ebar:
        final isN = p.kind == Kind.nbar;
        final y = tp(isN ? 'n1' : 'e1').dy;
        c.drawLine(Offset(6, y), Offset(sz.width - 6, y), Paint()
          ..strokeWidth = 2.4
          ..color = isN ? const Color(0xFF2C7BE5) : const Color(0xFF2FA84F));
        text(c, isN ? 'N' : 'PE', Offset(5, y - 6), size: 5.5, color: ink, w: FontWeight.w700);
        if (!isN) _earthSym(c, Offset(sz.width - 4, y), pen);
      case Kind.jbox:
      case Kind.jbox6:
      case Kind.jbox8:
      case Kind.jbox10:
        // junction box: the box outline and a connector for every point
        final rr = Rect.fromLTWH(6, 6, sz.width - 12, sz.height - 12);
        c.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(4)), pen);
        for (final t in p.type.terms) {
          c.drawRect(Rect.fromCenter(center: t.pos, width: 9, height: 7), thin);
          text(c, t.label, t.pos + const Offset(0, -6.5), size: 3.6, color: const Color(0xFF1B4FA0));
        }
        text(c, 'J-Box', Offset(sz.width / 2, sz.height - 12), size: 4.5, color: ink);
      case Kind.sw1:
      case Kind.dimmer:
        final a = Offset(tp('L').dx, 52), b = Offset(tp('1').dx, 52);
        c.drawLine(tp('L'), a, pk('L'));
        c.drawLine(tp('1'), b, pk('1'));
        final closed = p.kind == Kind.dimmer ? p.level > 0 : p.on;
        make(a, b, closed, closed && hot('L') ? live : pen);
        hand(Offset((a.dx + b.dx) / 2, closed ? 52 : 46.5), 14);
        if (p.kind == Kind.dimmer) {
          c.drawLine(Offset(a.dx - 2, 62), Offset(b.dx + 3, 38), pen);
          c.drawLine(Offset(b.dx + 3, 38), Offset(b.dx, 38.5), pen);
          c.drawLine(Offset(b.dx + 3, 38), Offset(b.dx + 2.2, 41), pen);
          text(c, '${(p.level * 100).round()}%', Offset(sz.width / 2, 72), size: 5, color: ink);
        }
      case Kind.sw2:
        // changeover: pivot on top joined to C, two fixed contacts under it
        final xc = sz.width / 2;
        final piv = Offset(xc, 30);
        final q1 = Offset(xc - 9, 56), q2 = Offset(xc + 9, 56);
        poly([tp('C'), Offset(tp('C').dx, 24), Offset(xc, 24), piv], pk('C'));
        poly([tp('1'), Offset(tp('1').dx, 66), Offset(q1.dx, 66), q1], pk('1'));
        poly([tp('2'), Offset(tp('2').dx, 70), Offset(q2.dx, 70), q2], pk('2'));
        for (final q in [q1, q2]) {
          c.drawLine(q + const Offset(-2, 0), q + const Offset(2, 0), pen);
        }
        c.drawLine(piv, p.on ? q2 : q1, hot('C') ? live : pen);
        c.drawCircle(piv, .9, Paint()..color = ink);
        text(c, '1', q1 + const Offset(-4, -3), size: 4, color: ink);
        text(c, '2', q2 + const Offset(4, -3), size: 4, color: ink);
      case Kind.swd:
        // two gangs off one common: two make contacts sharing the pivot
        final xc = sz.width / 2;
        final piv = Offset(xc, 30);
        final q1 = Offset(xc - 10, 58), q2 = Offset(xc + 10, 58);
        poly([tp('L'), Offset(tp('L').dx, 24), Offset(xc, 24), piv], pk('L'));
        poly([tp('1'), Offset(tp('1').dx, 66), Offset(q1.dx, 66), q1], pk('1'));
        poly([tp('2'), Offset(tp('2').dx, 70), Offset(q2.dx, 70), q2], pk('2'));
        for (final gang in [(q1, p.on, -1.0), (q2, p.on2, 1.0)]) {
          final q = gang.$1;
          c.drawLine(q + const Offset(-2, 0), q + const Offset(2, 0), pen);
          final v = q - piv;
          final ang = gang.$3 * .45;
          final open = piv + Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang), v.dx * math.sin(ang) + v.dy * math.cos(ang));
          c.drawLine(piv, gang.$2 ? q : open, gang.$2 && hot('L') ? live : pen);
        }
        c.drawCircle(piv, .9, Paint()..color = ink);
      case Kind.swi:
        // intermediate: straight-through or crossed pair of blades
        final xs = [tp('A1').dx, tp('A2').dx];
        final a1 = Offset(xs[0], 62), a2 = Offset(xs[1], 62);
        final top2 = Offset(xs[0], 40), top1 = Offset(xs[1], 40); // B2 above A1, B1 above A2
        c.drawLine(tp('A1'), a1, pk('A1'));
        c.drawLine(tp('A2'), a2, pk('A2'));
        poly([top1, Offset(top1.dx, 32), Offset(tp('B1').dx, 32), tp('B1')], pk('B1'));
        poly([top2, Offset(top2.dx, 26), Offset(tp('B2').dx, 26), tp('B2')], pk('B2'));
        for (final q in [top1, top2]) {
          c.drawLine(q + const Offset(-2, 0), q + const Offset(2, 0), pen);
        }
        if (p.on) {
          c.drawLine(a1, top2, hot('A1') ? live : pen); // A1-B2
          c.drawLine(a2, top1, hot('A2') ? live : pen); // A2-B1
        } else {
          c.drawLine(a1, top1, hot('A1') ? live : pen); // A1-B1
          c.drawLine(a2, top2, hot('A2') ? live : pen); // A2-B2
        }
        for (final q in [a1, a2]) {
          c.drawCircle(q, .9, Paint()..color = ink);
        }
      case Kind.pb:
        // push button, make contact (bridging), spring return
        final a = Offset(tp('1').dx, 50), b = Offset(tp('2').dx, 50);
        c.drawLine(tp('1'), a, pk('1'));
        c.drawLine(tp('2'), b, pk('2'));
        for (final q in [a, b]) {
          c.drawLine(q, q + const Offset(0, -2), pen);
        }
        final y = p.on ? 48.0 : 40.0;
        c.drawLine(Offset(a.dx - 2, y), Offset(b.dx + 2, y), p.on && hot('1') ? live : pen);
        final xm = (a.dx + b.dx) / 2;
        dashed(Offset(xm, y), Offset(xm, 24));
        poly([Offset(xm - 4, 21), Offset(xm - 4, 24), Offset(xm + 4, 24), Offset(xm + 4, 21)], pen);
      case Kind.lamp:
        final b = (r.lamp[p.id] ?? 0).clamp(0.0, 1.0);
        final o = Offset(sz.width / 2, 70);
        const rr = 12.0;
        if (b > .02) c.drawCircle(o, rr + 2, Paint()..color = const Color(0xFFFFD54F).withValues(alpha: .25 + .6 * b));
        c.drawCircle(o, rr, pen);
        const k = rr * .707;
        c.drawLine(o + const Offset(-k, -k), o + const Offset(k, k), pen);
        c.drawLine(o + const Offset(k, -k), o + const Offset(-k, k), pen);
        poly([tp('L'), Offset(tp('L').dx, o.dy + 16), Offset(o.dx - 4, o.dy + 16), Offset(o.dx - 4, o.dy + rr - .6)], pk('L'));
        poly([tp('N'), Offset(tp('N').dx, o.dy + 16), Offset(o.dx + 4, o.dy + 16), Offset(o.dx + 4, o.dy + rr - .6)], pen);
        text(c, '${p.watts}W', o + const Offset(0, -18), size: 4.5, color: ink);
      case Kind.socket:
        // socket outlet with protective contact
        final o = Offset(sz.width / 2, 46);
        c.drawArc(Rect.fromCircle(center: o, radius: 13), math.pi, math.pi, false, pen);
        c.drawLine(o + const Offset(-13, 0), o + const Offset(13, 0), pen);
        c.drawLine(o + const Offset(0, -13), o + const Offset(0, -20), pen);
        c.drawLine(o + const Offset(-7, -20), o + const Offset(7, -20), pen);
        poly([tp('L'), Offset(tp('L').dx, o.dy)], pk('L'));
        poly([tp('N'), Offset(tp('N').dx, o.dy)], pen);
        poly([tp('PE'), Offset(tp('PE').dx, o.dy + 24), Offset(o.dx + 17, o.dy + 24), Offset(o.dx + 17, o.dy - 20), Offset(o.dx + 7, o.dy - 20)], thin);
        if (r.sockets[p.id] ?? false) c.drawCircle(o + const Offset(0, -6), 2, Paint()..color = const Color(0xFF00C853));
      case Kind.bell:
        final ring = r.bells.contains(p.id);
        final o = Offset(sz.width / 2, 48);
        c.drawArc(Rect.fromCircle(center: o, radius: 12), math.pi, math.pi, false, ring ? live : pen);
        c.drawLine(o + const Offset(-12, 0), o + const Offset(12, 0), ring ? live : pen);
        poly([tp('1'), Offset(tp('1').dx, o.dy)], pk('1'));
        poly([tp('2'), Offset(tp('2').dx, o.dy)], pk('2'));
      case Kind.lock:
        final open = r.locks.contains(p.id);
        final box = Rect.fromLTWH(sz.width / 2 - 14, 30, 28, 30);
        c.drawRect(box, open ? live : pen);
        c.drawLine(box.topLeft + const Offset(0, 10), box.topRight + const Offset(0, 10), thin);
        c.drawRect(Rect.fromLTWH(open ? box.left + 8 : box.left + 14, box.top + 15, 12, 6), thin);
        text(c, 'كالون', Offset(sz.width / 2, 24), size: 4.5, color: ink);
        poly([tp('1'), Offset(tp('1').dx, box.bottom)], pk('1'));
        poly([tp('2'), Offset(tp('2').dx, box.bottom)], pk('2'));
      case Kind.tube:
        // fluorescent lamp: the tube with a two-terminal filament at each end
        final on = r.tubes.contains(p.id);
        final box = Rect.fromLTWH(24, 8, sz.width - 48, 27);
        if (on) c.drawRect(box, Paint()..color = const Color(0x44FFD54F));
        c.drawRect(box, pen);
        for (final e in [('A1', 'A2', box.left + 5), ('B1', 'B2', box.right - 5)]) {
          final x = e.$3;
          c.drawLine(Offset(x, box.top + 5), Offset(x, box.bottom - 5), pen);
          poly([tp(e.$1), Offset(x, tp(e.$1).dy), Offset(x, box.top + 5)], pk(e.$1));
          poly([tp(e.$2), Offset(x, tp(e.$2).dy), Offset(x, box.bottom - 5)], pk(e.$2));
        }
      case Kind.ballast:
        // inductor with an iron core
        final a = tp('1'), b = tp('2');
        final path = Path()..moveTo(a.dx, a.dy);
        const n = 5;
        final x0 = a.dx + 24, x1 = b.dx - 24;
        path.lineTo(x0, a.dy);
        final w = (x1 - x0) / n;
        for (var i = 0; i < n; i++) {
          path.arcToPoint(Offset(x0 + w * (i + 1), a.dy), radius: Radius.circular(w / 2));
        }
        path.lineTo(b.dx, b.dy);
        c.drawPath(path, pk('1'));
        c.drawLine(Offset(x0, a.dy - w / 2 - 3), Offset(x1, a.dy - w / 2 - 3), pen);
        c.drawLine(Offset(x0, a.dy - w / 2 - 5), Offset(x1, a.dy - w / 2 - 5), pen);
      case Kind.starter:
        // glow starter: bulb with a bimetal contact
        final o = Offset(sz.width / 2, 24);
        c.drawCircle(o, 11, pen);
        c.drawLine(o + const Offset(-5, 5), o + const Offset(-5, -3), pen);
        c.drawArc(Rect.fromCircle(center: o + const Offset(0, -3), radius: 5), math.pi, math.pi, false, pen);
        c.drawLine(o + const Offset(5, -3), o + const Offset(5, 5), pen);
        poly([tp('1'), Offset(tp('1').dx, o.dy + 5), o + const Offset(-5, 5)], pk('1'));
        poly([tp('2'), Offset(tp('2').dx, o.dy + 5), o + const Offset(5, 5)], pk('2'));
      case Kind.stair:
        final box = Rect.fromLTWH(1.5, 20, sz.width - 3, 52);
        c.drawRect(box, pen);
        final o = Offset(sz.width / 2, 40);
        c.drawCircle(o, 6, thin);
        c.drawLine(o, o + const Offset(0, -4), thin);
        c.drawLine(o, o + const Offset(3, 0), thin);
        final left = s.stairLeft[p.id] ?? 0;
        text(c, left > 0 ? '${left.ceil()}s' : 'T', Offset(sz.width / 2, 58), size: 5, color: ink, w: FontWeight.w700);
        for (final t in p.type.terms) {
          c.drawLine(t.pos, Offset(t.pos.dx, t.pos.dy < sz.height / 2 ? box.top : box.bottom), pk(t.id));
        }
      case Kind.driver:
        final box = Rect.fromLTWH(20, 4, sz.width - 40, sz.height - 8);
        c.drawRect(box, pen);
        c.drawLine(box.bottomLeft, box.topRight, thin);
        text(c, '~', box.topLeft + const Offset(12, 10), size: 9, color: ink);
        text(c, '=', box.bottomRight + const Offset(-12, -10), size: 9, color: ink);
        for (final t in p.type.terms) {
          c.drawLine(t.pos, Offset(t.pos.dx < sz.width / 2 ? box.left : box.right, t.pos.dy), pk(t.id));
        }
      case Kind.ledpanel:
        final on = r.panels.contains(p.id);
        final o = Offset(sz.width / 2, 70);
        // LED: diode triangle, bar, and two light arrows
        final tri = Path()
          ..moveTo(o.dx - 8, o.dy - 7)
          ..lineTo(o.dx + 8, o.dy - 7)
          ..lineTo(o.dx, o.dy + 6)
          ..close();
        if (on) c.drawCircle(o, 22, Paint()..color = const Color(0x44FFD54F));
        c.drawPath(tri, on ? live : pen);
        c.drawLine(o + const Offset(-8, 6), o + const Offset(8, 6), pen);
        for (final dy in [-2.0, 4.0]) {
          final a0 = o + Offset(10, dy), a1 = a0 + const Offset(7, -6);
          c.drawLine(a0, a1, thin);
          c.drawLine(a1, a1 + const Offset(-3, 0), thin);
          c.drawLine(a1, a1 + const Offset(0, 3), thin);
        }
        poly([tp('+'), Offset(tp('+').dx, o.dy - 16), Offset(o.dx, o.dy - 16), Offset(o.dx, o.dy - 7)], pk('+'));
        poly([tp('-'), Offset(tp('-').dx, o.dy + 14), Offset(o.dx, o.dy + 14), Offset(o.dx, o.dy + 6)], pen);
    }
  }

  void _earthSym(Canvas c, Offset at, Paint pen) {
    c.drawLine(at, at + const Offset(0, 4), pen);
    for (var i = 0; i < 3; i++) {
      final w = 6.0 - i * 2;
      c.drawLine(at + Offset(-w / 2, 4 + i * 1.6), at + Offset(w / 2, 4 + i * 1.6), pen);
    }
  }

  @override
  bool shouldRepaint(BoardPainter old) => true;
}

/// Small preview of a part for the component palette (the real render or the symbol).
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
          width: t.size.width + 8,
          height: t.size.height + 8,
          child: CustomPaint(painter: _IconPainter(kind, skin)),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final Kind kind;
  final Skin skin;
  _IconPainter(this.kind, this.skin) : super(repaint: Sprites.i.ready);
  @override
  void paint(Canvas c, Size size) {
    final p = Part('', kind, const Offset(4, 4), watts: kind == Kind.lamp ? 60 : kind == Kind.tube || kind == Kind.ballast ? 40 : 0);
    final sim = Sim(parts: [p]);
    final st = BoardState(sim: sim, res: SimResult(), skin: skin, t: 0, fx: Fx(), showLabels: false);
    final bp = BoardPainter(st);
    c.save();
    c.translate(4, 4);
    if (skin == Skin.board) {
      bp._part(c, p);
    } else {
      bp._symbol(c, p);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_IconPainter o) => false;
}
