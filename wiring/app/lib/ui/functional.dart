// The functional (current-path) diagram of a circuit, laid out automatically from its
// reference wiring: the phase rail on top, the neutral rail at the bottom, and every
// device drawn upright on the path the current takes between them (IEC 60617 symbols,
// contacts shown in the switch positions of the chosen scenario).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/circuits.dart';
import '../sim/diagnose.dart';
import '../sim/model.dart';
import '../sim/solver.dart';
import 'lab/painters.dart' show text;

const _skip = {Kind.supply, Kind.mcb, Kind.rcd, Kind.meter, Kind.nbar, Kind.ebar, Kind.jbox, Kind.jbox6, Kind.jbox8, Kind.jbox10};

/// terminal pairs a current can flow through, whatever the switch positions
List<(String, String)> _paths(Kind k) => switch (k) {
      Kind.sw1 || Kind.dimmer => [('L', '1')],
      Kind.sw2 => [('C', '1'), ('C', '2')],
      Kind.swd => [('L', '1'), ('L', '2')],
      Kind.swi => [('A1', 'B1'), ('A1', 'B2'), ('A2', 'B1'), ('A2', 'B2')],
      Kind.pb || Kind.bell || Kind.lock || Kind.ballast || Kind.starter => [('1', '2')],
      Kind.lamp || Kind.socket => [('L', 'N')],
      Kind.tube => [('A1', 'A2'), ('B1', 'B2'), ('A1', 'B1'), ('A1', 'B2'), ('A2', 'B1'), ('A2', 'B2')],
      Kind.stair => [('L', 'O'), ('S', 'N')],
      Kind.driver => [('L', 'N'), ('L', '+'), ('+', '-')],
      Kind.ledpanel => [('+', '-')],
      _ => const [],
    };

class _Dev {
  final Part p;
  List<String> top = [], bot = [];
  bool flip = false;
  double x = 0, w = 0, y0 = 0, y1 = 0;
  final Map<String, Offset> at = {};
  _Dev(this.p);
}

class FunctionalLayout {
  final Sim sim;
  final List<_Dev> devs = [];
  final Map<String, int> depth = {}; // net root -> level
  late final Nets nets;
  late final String lRail, nRail;
  int levels = 1;
  double width = 0;
  static const lev = 66.0, top = 34.0;

  FunctionalLayout(this.sim) {
    nets = netsOf(sim);
    final g = sim.parts.firstWhere((p) => p.kind == Kind.supply);
    lRail = nets.find('${g.id}.L');
    nRail = nets.find('${g.id}.N');
    final pe = nets.find('${g.id}.PE');
    for (final p in sim.parts.where((p) => !_skip.contains(p.kind))) {
      devs.add(_Dev(p));
    }
    // levels: device hops from the phase rail
    depth[lRail] = 0;
    var changed = true;
    while (changed) {
      changed = false;
      for (final d in devs) {
        for (final (a, b) in _paths(d.p.kind)) {
          final na = nets.find('${d.p.id}.$a'), nb = nets.find('${d.p.id}.$b');
          for (final (x, y) in [(na, nb), (nb, na)]) {
            final dx = depth[x];
            if (dx == null || y == nRail || y == pe) continue;
            if (depth[y] == null || depth[y]! > dx + 1) {
              depth[y] = dx + 1;
              changed = true;
            }
          }
        }
      }
    }
    final maxD = depth.values.fold(0, math.max);
    levels = maxD + 1;
    depth[nRail] = levels;
    // which terminals of a device go up, which go down
    for (final d in devs) {
      final ts = [
        for (final t in d.p.type.terms)
          if (nets.find('${d.p.id}.${t.id}') != pe) t.id
      ];
      int dp(String t) => depth[nets.find('${d.p.id}.$t')] ?? levels;
      final m = ts.map(dp).fold(1 << 20, math.min);
      d.top = ts.where((t) => dp(t) == m).toList();
      d.bot = ts.where((t) => dp(t) != m).toList();
      if (d.bot.isEmpty && d.top.length > 1) d.bot = [d.top.removeLast()];
      // canonical orientation of the multi-way switches: common on top
      const common = {Kind.sw2: 'C', Kind.swd: 'L'};
      final cm = common[d.p.kind];
      if (cm != null) {
        final others = d.p.type.terms.map((t) => t.id).where((t) => t != cm).toList();
        d.flip = !d.top.contains(cm);
        d.top = d.flip ? others : [cm];
        d.bot = d.flip ? [cm] : others;
      }
      if (d.p.kind == Kind.swi) {
        final a = ['A1', 'A2'], b = ['B1', 'B2'];
        d.flip = !d.top.any(a.contains);
        d.top = d.flip ? b : a;
        d.bot = d.flip ? a : b;
      }
    }
    // columns, in the order the devices sit on the board
    devs.sort((a, b) => a.p.pos.dx.compareTo(b.p.pos.dx));
    var x = 40.0;
    for (final d in devs) {
      final n = math.max(d.top.length, d.bot.length);
      d.w = d.p.kind == Kind.tube ? 70 : math.max(34.0, n * 18.0 + 10);
      d.x = x;
      x += d.w + 22;
      final l0 = depth[nets.find('${d.p.id}.${d.top.first}')] ?? 0;
      d.y0 = top + l0 * lev + 12;
      d.y1 = d.y0 + lev - 24;
      for (var i = 0; i < d.top.length; i++) {
        d.at[d.top[i]] = Offset(d.x + d.w * (i + 1) / (d.top.length + 1), d.y0);
      }
      for (var i = 0; i < d.bot.length; i++) {
        d.at[d.bot[i]] = Offset(d.x + d.w * (i + 1) / (d.bot.length + 1), d.y1);
      }
    }
    width = x + 30;
  }

  double get height => top + levels * lev + 40;
  double railY(String net) => top + (depth[net] ?? levels) * lev;
}

class FunctionalPainter extends CustomPainter {
  final Sim sim;
  final SimResult res;
  late final FunctionalLayout lay = FunctionalLayout(sim);
  FunctionalPainter(this.sim, this.res);

  @override
  void paint(Canvas c, Size size) {
    final k = math.min(size.width / lay.width, size.height / lay.height);
    c.translate((size.width - lay.width * k) / 2, (size.height - lay.height * k) / 2);
    c.scale(k);
    const ink = Color(0xFF1B2A4A);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = ink;
    final live = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE65100);
    final dot = Paint()..color = ink;
    bool hot(String key) => sim.power && res.live(key);

    // rails
    final ly = lay.railY(lay.lRail), ny = lay.railY(lay.nRail);
    c.drawLine(Offset(16, ly), Offset(lay.width - 10, ly), Paint()
      ..strokeWidth = 2.2
      ..color = sim.power ? const Color(0xFFE65100) : const Color(0xFF7A3E18));
    c.drawLine(Offset(16, ny), Offset(lay.width - 10, ny), Paint()
      ..strokeWidth = 2.2
      ..color = const Color(0xFF2C7BE5));
    text(c, 'L', Offset(9, ly), size: 11, color: ink, w: FontWeight.w700);
    text(c, 'N', Offset(9, ny), size: 11, color: ink, w: FontWeight.w700);

    // nets between devices: a bus per net on its own track
    final byNet = <String, List<Offset>>{};
    for (final d in lay.devs) {
      for (final e in d.at.entries) {
        byNet.putIfAbsent(lay.nets.find('${d.p.id}.${e.key}'), () => []).add(e.value);
      }
    }
    final tracks = <int, List<(double, double)>>{};
    for (final e in byNet.entries) {
      final pts = e.value;
      final net = e.key;
      final key = _keyOf(net);
      final hp = key.isNotEmpty && hot(key);
      final paint = hp ? live : pen;
      if (net == lay.lRail || net == lay.nRail) {
        final y = lay.railY(net);
        for (final q in pts) {
          c.drawLine(q, Offset(q.dx, y), paint);
          c.drawCircle(Offset(q.dx, y), 2.2, dot);
        }
        continue;
      }
      if (pts.length < 2) {
        for (final q in pts) {
          c.drawCircle(q, 2.2, Paint()
            ..style = PaintingStyle.stroke
            ..color = ink);
        }
        continue;
      }
      final lvl = lay.depth[net] ?? 0;
      final xs = pts.map((q) => q.dx).toList()..sort();
      final span = (xs.first, xs.last);
      final lt = tracks.putIfAbsent(lvl, () => []);
      var tr = 0;
      while (_spans['$lvl/$tr']?.any((u) => !(span.$2 < u.$1 - 6 || span.$1 > u.$2 + 6)) ?? false) {
        tr++;
      }
      lt.add((tr.toDouble(), 0));
      _spans.putIfAbsent('$lvl/$tr', () => []).add(span);
      final y = lay.railY(net) + 4 + tr * 7.0;
      c.drawLine(Offset(span.$1, y), Offset(span.$2, y), paint);
      for (final q in pts) {
        c.drawLine(q, Offset(q.dx, y), paint);
        if (pts.length > 2) c.drawCircle(Offset(q.dx, y), 2.2, dot);
      }
    }

    for (final d in lay.devs) {
      _device(c, d, pen, live, hot);
      text(c, d.p.id, Offset(d.x + d.w / 2 + (d.w / 2 + 6), (d.y0 + d.y1) / 2 - 12), size: 8.5, color: const Color(0xFF0D2B66), w: FontWeight.w700);
    }
  }

  final Map<String, List<(double, double)>> _spans = {};

  String _keyOf(String net) {
    for (final p in sim.parts) {
      for (final t in p.type.terms) {
        final k = '${p.id}.${t.id}';
        if (lay.nets.find(k) == net) return k;
      }
    }
    return '';
  }

  void _device(Canvas c, _Dev d, Paint pen, Paint live, bool Function(String) hot) {
    final p = d.p;
    final cx = d.x + d.w / 2, y0 = d.y0, y1 = d.y1, h = y1 - y0;
    const ink = Color(0xFF1B2A4A);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = ink;
    Offset at(String t) => d.at[t]!;
    bool hk(String t) => hot('${p.id}.$t');
    Paint pk(String t) => hk(t) ? live : pen;
    void dashed(Offset a, Offset b) {
      final l = (b - a).distance;
      if (l < .1) return;
      final u = (b - a) / l;
      for (var s = 0.0; s < l; s += 3.4) {
        c.drawLine(a + u * s, a + u * math.min(l, s + 1.8), thin);
      }
    }

    // a vertical make contact from [a] (pivot) towards [b]
    void make(Offset a, Offset b, bool closed, Paint blade) {
      c.drawLine(b + const Offset(-3.5, 0), b, pen);
      final v = b - a;
      const ang = .52;
      final end = closed ? b : a + Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang), v.dx * math.sin(ang) + v.dy * math.cos(ang));
      c.drawLine(a, end, blade);
    }

    switch (p.kind) {
      case Kind.sw1:
      case Kind.dimmer:
      case Kind.pb:
        final a = at(d.top.first), b = at(d.bot.first);
        final m0 = Offset(a.dx, y0 + h * .3), m1 = Offset(a.dx, y0 + h * .72);
        c.drawLine(a, m0, pk(d.top.first));
        c.drawLine(b, m1, pk(d.bot.first));
        if (p.kind == Kind.pb) {
          final y = p.on ? m1.dy : m1.dy - 6;
          c.drawLine(Offset(a.dx - 6, y), Offset(a.dx + 6, y), p.on && hk(d.top.first) ? live : pen);
          c.drawLine(m0, Offset(a.dx, y - 0), pen);
          dashed(Offset(a.dx + 6, y), Offset(a.dx + 16, y));
          c.drawLine(Offset(a.dx + 16, y - 4), Offset(a.dx + 16, y + 4), pen);
        } else {
          final closed = p.kind == Kind.dimmer ? p.level > 0 : p.on;
          make(m1, m0, closed, closed && hk(d.top.first) ? live : pen);
          dashed(Offset(a.dx + (closed ? 0 : 4), (m0.dy + m1.dy) / 2), Offset(a.dx - 14, (m0.dy + m1.dy) / 2));
          c.drawLine(Offset(a.dx - 14, (m0.dy + m1.dy) / 2 - 4), Offset(a.dx - 14, (m0.dy + m1.dy) / 2 + 4), pen);
          if (p.kind == Kind.dimmer) c.drawLine(Offset(a.dx - 8, m1.dy + 2), Offset(a.dx + 9, m0.dy - 2), thin);
        }
      case Kind.sw2:
      case Kind.swd:
        // common at the pivot, the two ways below (mirrored when the common is at the bottom)
        final cm = p.kind == Kind.sw2 ? 'C' : 'L';
        final o1 = d.flip ? d.top : d.bot;
        final pc = at(cm);
        final q1 = at(o1[0]), q2 = at(o1[1]);
        final s = d.flip ? -1.0 : 1.0;
        final piv = Offset(cx, pc.dy + s * h * .25);
        final c1 = Offset(q1.dx, q1.dy - s * h * .3), c2 = Offset(q2.dx, q2.dy - s * h * .3);
        c.drawPath(Path()
          ..moveTo(pc.dx, pc.dy)
          ..lineTo(pc.dx, piv.dy)
          ..lineTo(piv.dx, piv.dy), pk(cm));
        c.drawLine(q1, c1, pk(o1[0]));
        c.drawLine(q2, c2, pk(o1[1]));
        for (final q in [c1, c2]) {
          c.drawLine(q + const Offset(-3, 0), q + const Offset(3, 0), pen);
        }
        if (p.kind == Kind.sw2) {
          c.drawLine(piv, p.on ? c2 : c1, hk(cm) ? live : pen);
        } else {
          for (final g in [(c1, p.on, -1.0), (c2, p.on2, 1.0)]) {
            final v = g.$1 - piv;
            final ang = g.$3 * .4 * s;
            final open = piv + Offset(v.dx * math.cos(ang) - v.dy * math.sin(ang), v.dx * math.sin(ang) + v.dy * math.cos(ang));
            c.drawLine(piv, g.$2 ? g.$1 : open, g.$2 && hk(cm) ? live : pen);
          }
        }
        c.drawCircle(piv, 1.6, Paint()..color = ink);
      case Kind.swi:
        final a = d.flip ? d.bot : d.top; // A1, A2
        final b = d.flip ? d.top : d.bot; // B1, B2
        final a1 = Offset(at(a[0]).dx, at(a[0]).dy + (d.top.contains(a[0]) ? h * .28 : -h * .28));
        final a2 = Offset(at(a[1]).dx, at(a[1]).dy + (d.top.contains(a[1]) ? h * .28 : -h * .28));
        final b1 = Offset(at(b[0]).dx, at(b[0]).dy + (d.top.contains(b[0]) ? h * .28 : -h * .28));
        final b2 = Offset(at(b[1]).dx, at(b[1]).dy + (d.top.contains(b[1]) ? h * .28 : -h * .28));
        for (final e in [(a[0], a1), (a[1], a2), (b[0], b1), (b[1], b2)]) {
          c.drawLine(at(e.$1), e.$2, pk(e.$1));
        }
        for (final q in [b1, b2]) {
          c.drawLine(q + const Offset(-3, 0), q + const Offset(3, 0), pen);
        }
        if (p.on) {
          c.drawLine(a1, b2, hk('A1') ? live : pen);
          c.drawLine(a2, b1, hk('A2') ? live : pen);
        } else {
          c.drawLine(a1, b1, hk('A1') ? live : pen);
          c.drawLine(a2, b2, hk('A2') ? live : pen);
        }
      case Kind.lamp:
        final a = at(d.top.first), b = at(d.bot.first);
        final o = Offset(a.dx, (y0 + y1) / 2);
        const r = 10.0;
        final br = (res.lamp[p.id] ?? 0).clamp(0.0, 1.0);
        if (br > .02) c.drawCircle(o, r + 3, Paint()..color = const Color(0xFFFFD54F).withValues(alpha: .3 + .6 * br));
        c.drawLine(a, o - const Offset(0, r), pk(d.top.first));
        c.drawLine(b, o + const Offset(0, r), pen);
        c.drawCircle(o, r, pen);
        c.drawLine(o + const Offset(-7, -7), o + const Offset(7, 7), pen);
        c.drawLine(o + const Offset(7, -7), o + const Offset(-7, 7), pen);
      case Kind.socket:
        final a = at(d.top.first), b = at(d.bot.first);
        final o = Offset(cx, (y0 + y1) / 2 + 4);
        c.drawLine(a, Offset(a.dx, o.dy), pk(d.top.first));
        c.drawLine(b, Offset(b.dx, o.dy), pen);
        c.drawArc(Rect.fromCircle(center: o, radius: 11), math.pi, math.pi, false, pen);
        c.drawLine(o + const Offset(-11, 0), o + const Offset(11, 0), pen);
        c.drawLine(o + const Offset(0, -11), o + const Offset(0, -16), pen);
        c.drawLine(o + const Offset(-6, -16), o + const Offset(6, -16), pen);
        if (res.sockets[p.id] ?? false) c.drawCircle(o + const Offset(0, -5), 2.2, Paint()..color = const Color(0xFF00C853));
      case Kind.bell:
      case Kind.lock:
      case Kind.ballast:
      case Kind.starter:
      case Kind.ledpanel:
        final a = at(d.top.first), b = at(d.bot.first);
        final o = Offset(a.dx, (y0 + y1) / 2);
        final on = (p.kind == Kind.bell && res.bells.contains(p.id)) || (p.kind == Kind.lock && res.locks.contains(p.id)) || (p.kind == Kind.ledpanel && res.panels.contains(p.id));
        final body = on ? live : pen;
        double half;
        switch (p.kind) {
          case Kind.bell:
            half = 7;
            c.drawArc(Rect.fromCircle(center: o + const Offset(0, 4), radius: 11), math.pi, math.pi, false, body);
            c.drawLine(o + const Offset(-11, 4), o + const Offset(11, 4), body);
            c.drawLine(a, o - Offset(0, half), pk(d.top.first));
            c.drawLine(b, o + const Offset(0, 4), pen);
          case Kind.lock:
            half = 10;
            c.drawRect(Rect.fromCenter(center: o, width: 18, height: 20), body);
            c.drawLine(o + const Offset(-9, -3), o + const Offset(9, -3), pen);
          case Kind.ballast:
            half = 14;
            final path = Path()..moveTo(o.dx, o.dy - half);
            for (var i = 0; i < 4; i++) {
              path.arcToPoint(Offset(o.dx, o.dy - half + (i + 1) * 7), radius: const Radius.circular(3.5));
            }
            c.drawPath(path, pen);
            c.drawLine(Offset(o.dx - 7, o.dy - half), Offset(o.dx - 7, o.dy + half), pen);
          case Kind.starter:
            half = 9;
            c.drawCircle(o, 9, pen);
            c.drawLine(o + const Offset(-3, -9), o + const Offset(-3, 3), thin);
            c.drawLine(o + const Offset(3, 9), o + const Offset(3, -1), thin);
          default:
            half = 7;
            final tri = Path()
              ..moveTo(o.dx - 7, o.dy - 6)
              ..lineTo(o.dx + 7, o.dy - 6)
              ..lineTo(o.dx, o.dy + 6)
              ..close();
            c.drawPath(tri, body);
            c.drawLine(o + const Offset(-7, 6), o + const Offset(7, 6), pen);
            c.drawLine(o + const Offset(9, -2), o + const Offset(15, -8), thin);
            c.drawLine(o + const Offset(9, 4), o + const Offset(15, -2), thin);
        }
        if (p.kind != Kind.bell) {
          c.drawLine(a, Offset(a.dx, o.dy - half), pk(d.top.first));
          c.drawLine(b, Offset(b.dx, o.dy + half), pen);
        }
      default:
        // tube, staircase timer, driver: a labelled block with its terminals
        final r = Rect.fromLTRB(d.x + 2, y0 + 10, d.x + d.w - 2, y1 - 10);
        final on = (p.kind == Kind.tube && res.tubes.contains(p.id));
        if (on) c.drawRect(r, Paint()..color = const Color(0x44FFD54F));
        c.drawRect(r, on ? live : pen);
        if (p.kind == Kind.tube) {
          c.drawLine(r.topLeft + const Offset(6, 4), r.topRight + const Offset(-6, 4), thin);
          c.drawLine(r.bottomLeft + const Offset(6, -4), r.bottomRight + const Offset(-6, -4), thin);
        }
        text(c, switch (p.kind) { Kind.tube => 'فلورسنت', Kind.stair => 'تايمر سلم', Kind.driver => 'درايفر', _ => p.type.name }, r.center, size: 7, color: ink);
        for (final t in d.top) {
          c.drawLine(at(t), Offset(at(t).dx, r.top), pk(t));
          text(c, p.type.term(t).label, Offset(at(t).dx + 5, r.top + 5), size: 5.5, color: const Color(0xFF1B4FA0));
        }
        for (final t in d.bot) {
          c.drawLine(at(t), Offset(at(t).dx, r.bottom), pk(t));
          text(c, p.type.term(t).label, Offset(at(t).dx + 5, r.bottom - 5), size: 5.5, color: const Color(0xFF1B4FA0));
        }
    }
  }

  @override
  bool shouldRepaint(FunctionalPainter o) => true;
}

/// The functional diagram of [c] in the state of its last steady scenario.
class FunctionalDiagram extends StatelessWidget {
  final CircuitDef c;
  final bool lit;
  const FunctionalDiagram(this.c, {this.lit = true});
  @override
  Widget build(BuildContext context) {
    final sim = c.buildDone();
    var res = SimResult();
    if (lit && c.tests.isNotEmpty) {
      sim.power = true;
      applyScenario(sim, c.tests.lastWhere((s) => s.wait == 0, orElse: () => c.tests.last));
      res = simulate(sim);
    }
    return CustomPaint(painter: FunctionalPainter(sim, res), size: Size.infinite);
  }
}
