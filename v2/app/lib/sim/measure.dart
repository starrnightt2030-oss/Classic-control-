// Measuring a running (or switched-off) circuit the way a technician does:
// voltage between two probe points, current through one wire (clamp meter),
// resistance between two points with the supply off, and active power.
//
// Voltages come straight from the engine's nets. Currents are traced the same way
// as the current-flow animation: every load draws a phasor current, and that
// current is added on every wire of its path back to the source, so a balanced
// neutral sums to zero and a delta motor's line wire carries √3 × its winding current.
// Resistance is a small nodal analysis over wires, closed contacts and the cold
// resistance of every coil, lamp, winding and heater.
import 'dart:math' as math;

import 'engine.dart';

class Cx {
  final double re, im;
  const Cx(this.re, this.im);
  static const zero = Cx(0, 0);
  factory Cx.ph(Ph p) => Cx(p.re, p.im);
  factory Cx.polar(double mag, double rad) => Cx(mag * math.cos(rad), mag * math.sin(rad));
  Cx operator +(Cx o) => Cx(re + o.re, im + o.im);
  Cx operator -(Cx o) => Cx(re - o.re, im - o.im);
  Cx operator *(double k) => Cx(re * k, im * k);
  double get abs => math.sqrt(re * re + im * im);
  double get arg => math.atan2(im, re);

  /// real part of this × conj(o): active power when this is V and o is I
  double dotRe(Cx o) => re * o.re + im * o.im;
}

/// One load as the tracer sees it: current enters at [a] and leaves at [b].
class LoadDraw {
  final String a, b;
  final double amps, pf;
  final String comp;
  const LoadDraw(this.comp, this.a, this.b, this.amps, this.pf);
}

/// rated apparent power (VA) of a coil
double _coilVa(Comp c) => switch (c.type) { 'kc' => 10, 'relay' => 3, 'timer' || 'tsd' => 2, _ => 3 };

/// rated power (W) of a lamp-type load (lamp, buzzer, horn, solenoid valve, heater)
double loadWatts(Comp c) => (c.p['W'] as num?)?.toDouble() ?? 3;

extension Measure on Lab {
  /// every load drawing current now
  List<LoadDraw> loadDraws() {
    final n = nets;
    final out = <LoadDraw>[];
    if (n == null) return out;
    for (final c in comps) {
      if (c.s.dead) continue;
      final coil = c.t.coil;
      if (coil != null && c.s.v > 15 && c.s.fault != 'coil_open') {
        out.add(LoadDraw(c.id, '${c.id}.${coil[0]}', '${c.id}.${coil[1]}', _coilVa(c) / c.s.v, c.s.on ? 0.35 : 0.6));
      }
      if (c.type == 'lamp' && c.s.v > 5) {
        final rated = c.num_('V');
        final w = loadWatts(c) * (c.s.v / rated) * (c.s.v / rated);
        out.add(LoadDraw(c.id, '${c.id}.X1', '${c.id}.X2', w / c.s.v, (c.p['pf'] as num?)?.toDouble() ?? 1));
      }
      if (c.type == 'psu' && c.s.k > 0.05) {
        final v = n.vAcross('${c.id}.L', '${c.id}.N');
        if (v > 1) out.add(LoadDraw(c.id, '${c.id}.L', '${c.id}.N', 30 / v, 0.95));
      }
      if (c.type == 'trafo' && c.s.k > 0.05) {
        final hi = n.vAcross('${c.id}.P0', '${c.id}.P380') > 1 ? 'P380' : 'P220';
        final v = n.vAcross('${c.id}.$hi', '${c.id}.P0');
        if (v > 1) out.add(LoadDraw(c.id, '${c.id}.$hi', '${c.id}.P0', 8 / v, 0.4));
      }
      if (c.type == 'motor1') {
        final run = c.s.mode == 'run';
        final pf = run ? 0.75 : 0.35;
        if (c.s.vw[0] > 40) out.add(LoadDraw(c.id, '${c.id}.U1', '${c.id}.U2', c.s.current * (run ? 0.8 : 1), pf));
        if (c.s.vw[1] > 40 && run) out.add(LoadDraw(c.id, '${c.id}.Z1', '${c.id}.Z2', c.s.current * 0.35, 0.95));
      }
      if (c.type == 'motor') {
        // c.s.current is the line current; a delta winding carries line / √3
        final delta = c.s.mode == 'delta';
        final iw = delta ? c.s.current / math.sqrt(3) : c.s.current;
        final pf = c.s.mode == 'single' ? 0.3 : (c.s.spd > 0.9 ? 0.82 : 0.4);
        const w = [['U1', 'U2'], ['V1', 'V2'], ['W1', 'W2']];
        for (var i = 0; i < 3; i++) {
          if (c.s.vw[i] > 40) out.add(LoadDraw(c.id, '${c.id}.${w[i][0]}', '${c.id}.${w[i][1]}', iw, pf));
        }
      }
    }
    return out;
  }

  /// current phasor through every wire (index → A, positive from wire.a to wire.b)
  Map<int, Cx> wireCurrents() {
    final n = nets;
    final out = <int, Cx>{};
    if (n == null) return out;
    final adj = <String, List<(String, int, bool)>>{};
    void edge(String a, String b, int i) {
      (adj[a] ??= []).add((b, i, true));
      (adj[b] ??= []).add((a, i, false));
    }

    for (var i = 0; i < wires.length; i++) {
      final w = wires[i];
      if (!brokenWires.contains(w)) edge(w.a, w.b, i);
    }
    final src = <String>{};
    for (final c in comps) {
      for (final l in linksOf(c)) {
        edge('${c.id}.${l[0]}', '${c.id}.${l[1]}', -1);
      }
      if (c.attach != null && c.type == 'ol') {
        for (final pr in const [['2', '1'], ['4', '3'], ['6', '5']]) {
          edge('${c.attach}.${pr[0]}', '${c.id}.${pr[1]}', -1);
        }
      }
      if (c.type == 'sup' && power && supLive(c)) {
        for (final k in kPhase.keys) {
          src.add('${c.id}.$k');
        }
      }
      if (c.type == 'trafo' && c.s.k > 0.05) src.addAll(['${c.id}.S0', '${c.id}.S24', '${c.id}.S48']);
      if (c.type == 'psu' && c.s.k > 0.05) src.addAll(['${c.id}.P', '${c.id}.M']);
    }
    // the current of one load, added along the shortest conductor path from
    // [from] back to a source; [into]: the current runs towards [from]
    void trace(String from, Cx cur, bool into) {
      final prev = <String, (String, int, bool)>{from: ('', -1, true)};
      final q = <String>[from];
      String? hit;
      for (var h = 0; h < q.length; h++) {
        final u = q[h];
        if (u != from && src.contains(u)) {
          hit = u;
          break;
        }
        for (final (v, i, fwd) in adj[u] ?? const <(String, int, bool)>[]) {
          if (prev.containsKey(v)) continue;
          prev[v] = (u, i, fwd);
          q.add(v);
        }
      }
      if (hit == null) return;
      var v = hit;
      while (v != from) {
        final (u, i, fwd) = prev[v]!;
        // the walk u → v ran along the wire (a → b) when fwd; the current runs
        // against the walk when it flows towards the load
        if (i >= 0) {
          final along = fwd != into;
          out[i] = (out[i] ?? Cx.zero) + (along ? cur : cur * -1);
        }
        v = u;
      }
    }

    for (final d in loadDraws()) {
      final pa = n.pot(d.a), pb = n.pot(d.b);
      if (pa == null || pb == null || pa.g != pb.g) continue;
      final v = Cx.ph(pa.ph) - Cx.ph(pb.ph);
      if (v.abs < 1) continue;
      final cur = Cx.polar(d.amps, v.arg - math.acos(d.pf.clamp(0.0, 1.0)));
      trace(d.a, cur, true);
      trace(d.b, cur, false);
    }
    return out;
  }

  /// voltage phasor of a terminal and its source group, null when the net is dead
  (Cx, String)? potential(String term) {
    final p = nets?.pot(term);
    if (p == null) return null;
    return (Cx.ph(p.ph), p.g);
  }

  /// Resistance between two terminals (Ω) with the circuit as it stands
  /// (contacts in their present state), null when there is no path (OL).
  double? ohms(String a, String b) {
    // 0 Ω conductors merge terminals into nodes
    final parent = <String, String>{};
    String f(String x) {
      var r = x;
      while (parent[r] != null && parent[r] != r) {
        r = parent[r]!;
      }
      parent[x] = r;
      return r;
    }

    void join(String x, String y) {
      final rx = f(x), ry = f(y);
      if (rx != ry) parent[rx] = ry;
    }

    for (final w in wires) {
      if (!brokenWires.contains(w)) join(w.a, w.b);
    }
    for (final c in comps) {
      for (final l in linksOf(c)) {
        join('${c.id}.${l[0]}', '${c.id}.${l[1]}');
      }
      if (c.attach != null && c.type == 'ol') {
        for (final pr in const [['2', '1'], ['4', '3'], ['6', '5']]) {
          join('${c.attach}.${pr[0]}', '${c.id}.${pr[1]}');
        }
      }
    }
    if (f(a) == f(b)) return 0;
    // resistive elements
    final res = <(String, String, double)>[];
    void r(Comp c, String x, String y, double ohm) => res.add(('${c.id}.$x', '${c.id}.$y', ohm));
    for (final c in comps) {
      if (c.s.dead) continue;
      final coil = c.t.coil;
      if (coil != null && c.s.fault != 'coil_open') {
        final v = c.t.wide ? 230.0 : c.t.rated!(c);
        r(c, coil[0], coil[1], math.max(2.0, 0.3 * v * v / _coilVa(c)));
      }
      if (c.type == 'lamp' && c.s.fault != 'lamp_dead') {
        final v = c.num_('V');
        r(c, 'X1', 'X2', math.max(1.0, 0.12 * v * v / loadWatts(c)));
      }
      if (c.type == 'motor') {
        final rw = 2.0 * 8.5 / c.num_('In');
        r(c, 'U1', 'U2', rw);
        r(c, 'V1', 'V2', rw);
        r(c, 'W1', 'W2', rw);
      }
      if (c.type == 'motor1') {
        r(c, 'U1', 'U2', 6);
        r(c, 'Z1', 'Z2', 14);
      }
      if (c.type == 'trafo') {
        r(c, 'P0', 'P220', 18);
        r(c, 'P220', 'P380', 12);
        r(c, 'S0', 'S24', 0.4);
        r(c, 'S24', 'S48', 0.4);
      }
    }
    // nodal analysis: 1 A into a, b grounded
    final idx = <String, int>{};
    final ga = f(a), gb = f(b);
    for (final (x, y, _) in res) {
      for (final t in [f(x), f(y)]) {
        if (t != gb) idx.putIfAbsent(t, () => idx.length);
      }
    }
    if (!idx.containsKey(ga)) return null;
    final m = idx.length;
    final g = List.generate(m, (_) => List<double>.filled(m + 1, 0));
    for (final (x, y, ohm) in res) {
      final rx = f(x), ry = f(y);
      if (rx == ry) continue;
      final k = 1 / ohm;
      final i = idx[rx], j = idx[ry];
      if (i != null) g[i][i] += k;
      if (j != null) g[j][j] += k;
      if (i != null && j != null) {
        g[i][j] -= k;
        g[j][i] -= k;
      }
    }
    // nodes not connected to b make the matrix singular: tie them weakly to ground
    for (var i = 0; i < m; i++) {
      g[i][i] += 1e-9;
    }
    g[idx[ga]!][m] = 1;
    // Gaussian elimination with partial pivoting
    for (var col = 0; col < m; col++) {
      var piv = col;
      for (var r2 = col + 1; r2 < m; r2++) {
        if (g[r2][col].abs() > g[piv][col].abs()) piv = r2;
      }
      final t = g[col];
      g[col] = g[piv];
      g[piv] = t;
      final d = g[col][col];
      if (d.abs() < 1e-15) continue;
      for (var r2 = 0; r2 < m; r2++) {
        if (r2 == col) continue;
        final k = g[r2][col] / d;
        if (k == 0) continue;
        for (var c2 = col; c2 <= m; c2++) {
          g[r2][c2] -= k * g[col][c2];
        }
      }
    }
    final i = idx[ga]!;
    final v = g[i][m] / g[i][i];
    // anything above 20 MΩ is the weak tie, i.e. no real path
    if (!v.isFinite || v > 2e7) return null;
    return v;
  }
}
