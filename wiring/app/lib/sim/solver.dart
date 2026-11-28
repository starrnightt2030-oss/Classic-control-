import 'dart:math' as math;

import 'model.dart';

/// Mains voltage used by the simulator (single phase).
const double mains = 220;

/// Everything the simulator knows about one circuit on the board.
class Sim {
  final List<Part> parts;
  final List<Wire> wires;
  final List<Fault> faults;
  bool power;
  /// breakers that tripped and stay open until the student resets them
  final Set<String> tripped = {};
  /// main fuse (before the board) blew because of a dead short
  bool fuseBlown = false;
  /// staircase timers: part id -> seconds left
  final Map<String, double> stairLeft = {};
  double stairTime = 12;

  Sim({List<Part>? parts, List<Wire>? wires, List<Fault>? faults, this.power = false})
      : parts = parts ?? [],
        wires = wires ?? [],
        faults = faults ?? [];

  Part? part(String id) {
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool hasFault(FaultKind k, String target) => faults.any((f) => f.kind == k && f.target == target);

  Sim clone() {
    final s = Sim(parts: parts.map((p) => p.copy()).toList(), wires: wires.map((w) => w.copy()).toList(), faults: List.of(faults), power: power);
    s.tripped.addAll(tripped);
    s.fuseBlown = fuseBlown;
    s.stairLeft.addAll(stairLeft);
    s.stairTime = stairTime;
    return s;
  }

  /// close every breaker and replace the fuse
  void resetProtection() {
    tripped.clear();
    fuseBlown = false;
  }

  /// advance staircase timers
  void tick(double dt) {
    for (final k in stairLeft.keys.toList()) {
      final v = stairLeft[k]! - dt;
      if (v <= 0) {
        stairLeft.remove(k);
      } else {
        stairLeft[k] = v;
      }
    }
  }

  Map<String, dynamic> toJson() => {'parts': parts.map((p) => p.toJson()).toList(), 'wires': wires.map((w) => w.toJson()).toList()};
  static Sim fromJson(Map<String, dynamic> j) => Sim(
        parts: (j['parts'] as List).map((e) => Part.fromJson(Map<String, dynamic>.from(e))).toList(),
        wires: (j['wires'] as List).map((e) => Wire.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

enum SimEvent { none, shortCircuit, overload, leakage, fuse, noBallast }

class SimResult {
  final Map<String, double> v = {}; // "P.T" -> volts to earth
  final Map<String, double> lamp = {}; // part id -> brightness 0..1.3
  final Set<String> bells = {};
  final Set<String> locks = {};
  final Set<String> tubes = {};
  final Set<String> panels = {};
  final Map<String, bool> sockets = {}; // id -> live with correct polarity
  final Map<String, double> meterW = {};
  final Map<String, double> amps = {}; // breakers/meter current
  final Set<String> newlyTripped = {};
  final List<String> notes = [];
  SimEvent event = SimEvent.none;
  String? eventAt; // part id where the event shows (sparks / smoke)
  double volts(String a) => v[a] ?? 0;
  bool live(String a) => volts(a) > 90;
}

class _Res {
  final String a, b;
  final double r;
  final String tag; // part id or element name
  _Res(this.a, this.b, this.r, this.tag);
}

class _UF {
  final Map<String, String> p = {};
  String find(String x) {
    p.putIfAbsent(x, () => x);
    var r = x;
    while (p[r] != r) {
      r = p[r]!;
    }
    var c = x;
    while (p[c] != r) {
      final n = p[c]!;
      p[c] = r;
      c = n;
    }
    return r;
  }

  void join(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) p[ra] = rb;
  }
}

/// Network built from the board: ideal joins (wires, closed contacts) + resistors.
class _Net {
  final _UF uf = _UF();
  final List<_Res> res = [];
  final List<String> keys = [];
  String? srcL, srcN, srcPE;
}

const double _rClosed = 0.02; // breaker / meter contact resistance
const double _rFil = 10; // tube filament
const double _rBallast = 110;

_Net _build(Sim s, {required bool sources, Map<String, bool>? stairClosed}) {
  final n = _Net();
  final loose = s.faults.where((f) => f.kind == FaultKind.looseTerm).map((f) => f.target).toSet();
  for (final p in s.parts) {
    for (final t in p.type.terms) {
      final k = '${p.id}.${t.id}';
      n.keys.add(k);
      n.uf.find(k);
    }
  }
  for (var i = 0; i < s.wires.length; i++) {
    final w = s.wires[i];
    if (s.hasFault(FaultKind.wireCut, 'w$i')) continue;
    if (loose.contains(w.a) || loose.contains(w.b)) continue;
    n.uf.join(w.a, w.b);
  }
  void j(Part p, String a, String b) => n.uf.join('${p.id}.$a', '${p.id}.$b');
  void r(Part p, String a, String b, double ohm, [String? tag]) => n.res.add(_Res('${p.id}.$a', '${p.id}.$b', ohm, tag ?? p.id));

  for (final p in s.parts) {
    final broken = s.hasFault(FaultKind.switchBroken, p.id);
    switch (p.kind) {
      case Kind.supply:
        if (sources && !s.fuseBlown) {
          n.srcL = '${p.id}.L';
          n.srcN = '${p.id}.N';
          n.srcPE = '${p.id}.PE';
        }
      case Kind.mcb:
        if (!s.tripped.contains(p.id) && !s.hasFault(FaultKind.mcbFaulty, p.id)) r(p, 'in', 'out', _rClosed);
      case Kind.rcd:
        if (!s.tripped.contains(p.id)) {
          r(p, 'Li', 'Lo', _rClosed, '${p.id}#L');
          r(p, 'Ni', 'No', _rClosed, '${p.id}#N');
        }
      case Kind.meter:
        r(p, 'Li', 'Lo', _rClosed, '${p.id}#L');
        r(p, 'Ni', 'No', _rClosed, '${p.id}#N');
      case Kind.nbar:
        j(p, 'n1', 'n2');
        j(p, 'n2', 'n3');
        j(p, 'n3', 'n4');
      case Kind.ebar:
        j(p, 'e1', 'e2');
        j(p, 'e2', 'e3');
        j(p, 'e3', 'e4');
      case Kind.jbox:
      case Kind.jbox6:
      case Kind.jbox8:
      case Kind.jbox10:
        break;
      case Kind.sw1:
        if (p.on && !broken) j(p, 'L', '1');
      case Kind.sw2:
        if (!broken) j(p, 'C', p.on ? '2' : '1');
      case Kind.swi:
        if (!broken) {
          if (p.on) {
            j(p, 'A1', 'B2');
            j(p, 'A2', 'B1');
          } else {
            j(p, 'A1', 'B1');
            j(p, 'A2', 'B2');
          }
        }
      case Kind.swd:
        if (!broken) {
          if (p.on) j(p, 'L', '1');
          if (p.on2) j(p, 'L', '2');
        }
      case Kind.pb:
        if (p.on && !broken) j(p, '1', '2');
      case Kind.dimmer:
        if (p.level > 0.03 && !broken) r(p, 'L', '1', (1 - p.level) * 900 + _rClosed);
      case Kind.lamp:
        if (!s.hasFault(FaultKind.lampBurnt, p.id)) r(p, 'L', 'N', mains * mains / math.max(1, p.watts));
      case Kind.socket:
        // a plugged load, or the tiny current of the tester lamp used to check the outlet
        r(p, 'L', 'N', p.plug ? mains * mains / 1000 : 1e6);
      case Kind.bell:
        if (!s.hasFault(FaultKind.bellDead, p.id)) r(p, '1', '2', mains * mains / 10);
      case Kind.lock:
        r(p, '1', '2', mains * mains / 12);
      case Kind.tube:
        if (!s.hasFault(FaultKind.tubeDead, p.id)) r(p, 'A1', 'A2', _rFil, '${p.id}#A');
        r(p, 'B1', 'B2', _rFil, '${p.id}#B');
      case Kind.ballast:
        if (!s.hasFault(FaultKind.ballastOpen, p.id)) r(p, '1', '2', _rBallast * 40 / math.max(10, p.watts));
      case Kind.starter:
        if (!s.hasFault(FaultKind.starterDead, p.id)) j(p, '1', '2');
      case Kind.stair:
        r(p, 'S', 'N', mains * mains / 3, '${p.id}#coil');
        if (stairClosed?[p.id] ?? false) j(p, 'L', 'O');
      case Kind.driver:
        if (!s.hasFault(FaultKind.driverDead, p.id)) r(p, 'L', 'N', mains * mains / 20);
      case Kind.ledpanel:
        break;
    }
  }
  for (final f in s.faults.where((f) => f.kind == FaultKind.leakToEarth)) {
    final pe = s.parts.where((p) => p.kind == Kind.supply).map((p) => '${p.id}.PE').firstOrNull;
    if (pe != null) n.res.add(_Res(f.target, pe, 1200, 'leak'));
  }
  return n;
}

/// Solves G·V = I for the groups of the network. [fixed] maps a group root to its voltage.
Map<String, double> _solve(_Net n, Map<String, double> fixed) {
  final groups = <String>{};
  for (final k in n.keys) {
    groups.add(n.uf.find(k));
  }
  for (final r in n.res) {
    groups.add(n.uf.find(r.a));
    groups.add(n.uf.find(r.b));
  }
  final free = groups.where((g) => !fixed.containsKey(g)).toList();
  final idx = {for (var i = 0; i < free.length; i++) free[i]: i};
  final m = free.length;
  final a = List.generate(m, (_) => List<double>.filled(m + 1, 0));
  for (var i = 0; i < m; i++) {
    a[i][i] += 1e-9; // a floating node settles at earth potential
  }
  for (final r in n.res) {
    final ga = n.uf.find(r.a), gb = n.uf.find(r.b);
    if (ga == gb) continue;
    final g = 1 / r.r;
    final ia = idx[ga], ib = idx[gb];
    if (ia != null) {
      a[ia][ia] += g;
      if (ib != null) {
        a[ia][ib] -= g;
      } else {
        a[ia][m] += g * fixed[gb]!;
      }
    }
    if (ib != null) {
      a[ib][ib] += g;
      if (ia != null) {
        a[ib][ia] -= g;
      } else {
        a[ib][m] += g * fixed[ga]!;
      }
    }
  }
  // Gaussian elimination with partial pivoting
  for (var c = 0; c < m; c++) {
    var piv = c;
    for (var r = c + 1; r < m; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    if (a[piv][c].abs() < 1e-15) continue;
    final t = a[c];
    a[c] = a[piv];
    a[piv] = t;
    for (var r = 0; r < m; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      if (f == 0) continue;
      for (var k = c; k <= m; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  final out = <String, double>{...fixed};
  for (var i = 0; i < m; i++) {
    out[free[i]] = a[i][i].abs() < 1e-15 ? 0 : a[i][m] / a[i][i];
  }
  return out;
}

/// Runs the circuit. Trips breakers, starts staircase timers, works out what lights up.
SimResult simulate(Sim s) {
  final res = SimResult();
  if (!s.power) {
    _fill(s, res, null, null);
    return res;
  }
  for (var round = 0; round < 8; round++) {
    final stair = {for (final p in s.parts.where((p) => p.kind == Kind.stair)) p.id: (s.stairLeft[p.id] ?? 0) > 0};
    final n = _build(s, sources: true, stairClosed: stair);
    if (n.srcL == null) {
      _fill(s, res, null, null);
      return res;
    }
    final gL = n.uf.find(n.srcL!), gN = n.uf.find(n.srcN!), gE = n.uf.find(n.srcPE!);
    if (gL == gN || gL == gE) {
      // dead short straight on the supply, before any breaker: the main fuse blows
      s.fuseBlown = true;
      res.event = SimEvent.fuse;
      res.eventAt = s.parts.firstWhere((p) => p.kind == Kind.supply).id;
      _fill(s, res, null, null);
      return res;
    }
    final fixed = <String, double>{gL: mains, gN: 0, gE: 0};
    final v = _solve(n, fixed);
    double cur(_Res r) => ((v[n.uf.find(r.a)] ?? 0) - (v[n.uf.find(r.b)] ?? 0)) / r.r;

    var changed = false;
    // breakers
    for (final r in n.res) {
      final p = s.part(r.tag.split('#').first);
      if (p == null) continue;
      if (p.kind == Kind.mcb) {
        final i = cur(r).abs();
        res.amps[p.id] = i;
        if (i > p.rating * 1.05) {
          s.tripped.add(p.id);
          res.newlyTripped.add(p.id);
          res.event = i > p.rating * 20 ? SimEvent.shortCircuit : SimEvent.overload;
          res.eventAt = p.id;
          changed = true;
        }
      }
    }
    for (final p in s.parts.where((p) => p.kind == Kind.rcd && !s.tripped.contains(p.id))) {
      final rl = n.res.firstWhere((r) => r.tag == '${p.id}#L');
      final rn = n.res.firstWhere((r) => r.tag == '${p.id}#N');
      final il = cur(rl), inn = cur(rn);
      res.amps[p.id] = il.abs();
      if ((il + inn).abs() > 0.03) {
        s.tripped.add(p.id);
        res.newlyTripped.add(p.id);
        res.event = SimEvent.leakage;
        res.eventAt = p.id;
        changed = true;
      } else if (il.abs() > 40) {
        s.tripped.add(p.id);
        res.newlyTripped.add(p.id);
        res.event = SimEvent.shortCircuit;
        res.eventAt = p.id;
        changed = true;
      }
    }
    // a short with no breaker in the way: the main fuse goes
    var total = 0.0;
    for (final r in n.res) {
      final ga = n.uf.find(r.a), gb = n.uf.find(r.b);
      if (ga == gL && gb != gL) total += cur(r);
      if (gb == gL && ga != gL) total -= cur(r);
    }
    if (!changed && total.abs() > 63) {
      s.fuseBlown = true;
      res.event = SimEvent.fuse;
      res.eventAt = s.parts.firstWhere((p) => p.kind == Kind.supply).id;
      _fill(s, res, null, null);
      return res;
    }
    // staircase timers: the push buttons feed terminal 3
    for (final p in s.parts.where((p) => p.kind == Kind.stair)) {
      final coil = n.res.firstWhere((r) => r.tag == '${p.id}#coil');
      if (cur(coil).abs() * (mains * mains / 3) > 150 && (s.stairLeft[p.id] ?? 0) < s.stairTime - 0.01) {
        s.stairLeft[p.id] = s.stairTime;
        changed = true;
      }
    }
    if (changed) continue;
    _fill(s, res, n, v);
    // tubes: both filaments must carry the starting current through a ballast
    for (final p in s.parts.where((p) => p.kind == Kind.tube)) {
      final fa = n.res.where((r) => r.tag == '${p.id}#A').firstOrNull;
      final fb = n.res.firstWhere((r) => r.tag == '${p.id}#B');
      final ia = fa == null ? 0.0 : cur(fa).abs(), ib = cur(fb).abs();
      if (ia > 0.12 && ib > 0.12 && (ia - ib).abs() < 0.05) {
        final ballasts = n.res.where((r) => s.part(r.tag)?.kind == Kind.ballast && (cur(r).abs() - ia).abs() < 0.05).toList();
        if (ballasts.isEmpty) {
          res.event = SimEvent.noBallast;
          res.eventAt = p.id;
          res.notes.add('الأنبوبة ${p.id} متوصلة من غير بلاست');
        } else {
          final bw = ballasts.map((r) => s.part(r.tag)!.watts).fold<int>(0, (a, b) => a + b);
          final tubesOnIt = s.parts.where((q) => q.kind == Kind.tube).where((q) {
            final r2 = n.res.firstWhere((r) => r.tag == '${q.id}#B');
            return (cur(r2).abs() - ia).abs() < 0.02;
          }).fold<int>(0, (a, q) => a + q.watts);
          if (bw >= tubesOnIt - 1) {
            res.tubes.add(p.id);
          } else {
            res.notes.add('البلاست أصغر من قدرة الأنابيب اللي عليه');
          }
        }
      }
    }
    break;
  }
  return res;
}

void _fill(Sim s, SimResult res, _Net? n, Map<String, double>? v) {
  double at(String k) => (n == null || v == null) ? 0 : (v[n.uf.find(k)] ?? 0);
  for (final p in s.parts) {
    for (final t in p.type.terms) {
      final k = '${p.id}.${t.id}';
      res.v[k] = at(k);
    }
  }
  if (n == null) return;
  for (final p in s.parts) {
    double dv(String a, String b) => (at('${p.id}.$a') - at('${p.id}.$b')).abs();
    switch (p.kind) {
      case Kind.lamp:
        if (!s.hasFault(FaultKind.lampBurnt, p.id)) {
          final d = dv('L', 'N');
          res.lamp[p.id] = math.min(1.3, (d * d) / (mains * mains));
        }
      case Kind.bell:
        if (!s.hasFault(FaultKind.bellDead, p.id) && dv('1', '2') > 150) res.bells.add(p.id);
      case Kind.lock:
        if (dv('1', '2') > 150) res.locks.add(p.id);
      case Kind.socket:
        final ok = at('${p.id}.L') > 150 && at('${p.id}.N').abs() < 40;
        res.sockets[p.id] = ok;
      case Kind.meter:
        final i = (at('${p.id}.Li') - at('${p.id}.Lo')) / _rClosed;
        res.meterW[p.id] = (i * at('${p.id}.Lo')).abs();
      case Kind.ledpanel:
        for (final d in s.parts.where((d) => d.kind == Kind.driver && !s.hasFault(FaultKind.driverDead, d.id))) {
          final powered = (at('${d.id}.L') - at('${d.id}.N')).abs() > 150;
          final same = n.uf.find('${d.id}.+') == n.uf.find('${p.id}.+') && n.uf.find('${d.id}.-') == n.uf.find('${p.id}.-');
          if (powered && same) res.panels.add(p.id);
        }
      default:
        break;
    }
  }
}

/// Ohmmeter between two terminals with the power off. Returns null for open circuit.
double? resistance(Sim s, String a, String b) {
  final n = _build(s, sources: false, stairClosed: {for (final p in s.parts.where((p) => p.kind == Kind.stair)) p.id: (s.stairLeft[p.id] ?? 0) > 0});
  final ga = n.uf.find(a), gb = n.uf.find(b);
  if (ga == gb) return 0;
  final v = _solve(n, {ga: 1, gb: 0});
  var i = 0.0;
  for (final r in n.res) {
    final x = n.uf.find(r.a), y = n.uf.find(r.b);
    if (x == ga && y != ga) i += (1 - (v[y] ?? 0)) / r.r;
    if (y == ga && x != ga) i += (1 - (v[x] ?? 0)) / r.r;
  }
  if (i < 1e-6) return null;
  return 1 / i;
}
