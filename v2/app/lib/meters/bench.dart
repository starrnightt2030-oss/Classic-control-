// The practice benches of «أجهزة القياس»: a real distribution board and a three-phase motor.
//
// A bench knows, for its present switch positions:
//  * the voltage (an RMS phasor) on every test point; a dead point is at 0 V,
//  * the current through every clamp place (phasor sum of the wires inside the jaw),
//  * the resistance between two points while they are dead (a small nodal analysis
//    over windings, links, heater, insulation and earth bonds),
//  * what a low-impedance instrument (ammeter, wattmeter current coil) does when it
//    bridges two points: carries the load current, or shorts the supply.
// The test-point names are the empties pt_<name> in v2/models/instruments.py.
import 'dart:math' as math;

class Cx {
  final double re, im;
  const Cx(this.re, this.im);
  static const zero = Cx(0, 0);
  factory Cx.polar(double mag, double deg) => Cx(mag * math.cos(deg * math.pi / 180), mag * math.sin(deg * math.pi / 180));
  Cx operator +(Cx o) => Cx(re + o.re, im + o.im);
  Cx operator -(Cx o) => Cx(re - o.re, im - o.im);
  Cx operator -() => Cx(-re, -im);
  Cx operator *(double k) => Cx(re * k, im * k);
  double get abs => math.sqrt(re * re + im * im);

  /// Re(this × conj(o)): active power when this is a voltage and o a current
  double dotRe(Cx o) => re * o.re + im * o.im;

  /// Im(this × conj(o)): reactive power
  double crossIm(Cx o) => im * o.re - re * o.im;
}

const double kInf = double.infinity;
const double vPhase = 230;

/// the supply: 400/230 V, 50 Hz, L1 at 0°, L2 at −120°, L3 at +120°
Cx phase(int i) => Cx.polar(vPhase, [0.0, -120.0, 120.0][i]);

/// A resistor network: nodes are names, edges are resistances in ohms.
class Net {
  final _edges = <(String, String, double)>[];
  void add(String a, String b, double ohms) {
    if (ohms.isFinite && a != b) _edges.add((a, b, math.max(ohms, 1e-4)));
  }

  /// the resistance an ohmmeter reads between [a] and [b] (infinity when not connected)
  double between(String a, String b) {
    if (a == b) return 0;
    // the part of the network connected to a
    final adj = <String, List<(String, double)>>{};
    for (final (x, y, r) in _edges) {
      (adj[x] ??= []).add((y, r));
      (adj[y] ??= []).add((x, r));
    }
    if (!adj.containsKey(a) || !adj.containsKey(b)) return kInf;
    final seen = <String>{a};
    final todo = [a];
    while (todo.isNotEmpty) {
      final n = todo.removeLast();
      for (final (m, _) in adj[n]!) {
        if (seen.add(m)) todo.add(m);
      }
    }
    if (!seen.contains(b)) return kInf;
    // nodal analysis: b is the reference, 1 A goes in at a
    final nodes = seen.where((n) => n != b).toList();
    final idx = {for (var i = 0; i < nodes.length; i++) nodes[i]: i};
    final n = nodes.length;
    final g = List.generate(n, (_) => List<double>.filled(n + 1, 0));
    for (final (x, y, r) in _edges) {
      if (!seen.contains(x)) continue;
      final c = 1 / r;
      final i = idx[x], j = idx[y];
      if (i != null) g[i][i] += c;
      if (j != null) g[j][j] += c;
      if (i != null && j != null) {
        g[i][j] -= c;
        g[j][i] -= c;
      }
    }
    g[idx[a]!][n] = 1;
    // Gaussian elimination with partial pivoting
    for (var c = 0; c < n; c++) {
      var p = c;
      for (var r = c + 1; r < n; r++) {
        if (g[r][c].abs() > g[p][c].abs()) p = r;
      }
      final t = g[c];
      g[c] = g[p];
      g[p] = t;
      final d = g[c][c];
      if (d.abs() < 1e-30) return kInf;
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        final f = g[r][c] / d;
        if (f == 0) continue;
        for (var k = c; k <= n; k++) {
          g[r][k] -= f * g[c][k];
        }
      }
    }
    return g[idx[a]!][n] / g[idx[a]!][idx[a]!];
  }
}

class TestPoint {
  final String id, label, about;
  const TestPoint(this.id, this.label, this.about);
}

/// what happens when an instrument puts a (near) zero-ohm path between two points
class Bridge {
  /// the current through it, from the first point to the second
  final Cx current;

  /// it shorted two points at different voltages
  final bool short;
  const Bridge(this.current, {this.short = false});
}

abstract class Bench {
  String get key;
  String get nameAr;
  List<TestPoint> get points;

  /// clamp places: id -> label
  Map<String, String> get clamps => const {};

  /// switch node -> on (tog_* in the 3D model)
  final Map<String, bool> switches = {};

  /// seconds since the bench was made (inrush, polarisation)
  double t = 0;
  void tick(double dt) => t += dt;

  /// low-impedance paths the instruments put in now (ammeter, wattmeter current coil)
  final Set<(String, String)> bridges = {};

  Cx voltage(String p);
  Cx clampCurrent(String id) => Cx.zero;
  Net deadNet();
  Bridge bridge(String a, String b);

  /// the voltage between two points (what a voltmeter reads)
  Cx between(String a, String b) => voltage(a) - voltage(b);
  bool live(String a, String b) => between(a, b).abs > 12;
  double resistance(String a, String b) => deadNet().between(a, b);
  String label(String id) => points.firstWhere((p) => p.id == id, orElse: () => TestPoint(id, id.replaceFirst('pt_', ''), '')).label;
  Map<String, Object?> view3d();
}

// ======================================================================= board
enum HeaterLoad { heater, motor, lamps }

extension HeaterLoadInfo on HeaterLoad {
  String get nameAr => switch (this) {
        HeaterLoad.heater => 'سخان 1000 وات',
        HeaterLoad.motor => 'طلمبة 1 فاز (موتور)',
        HeaterLoad.lamps => 'كشافات LED',
      };

  /// active power (W) and power factor at 230 V
  (double, double) get pq => switch (this) {
        HeaterLoad.heater => (1000.0, 1.0),
        HeaterLoad.motor => (750.0, 0.72),
        HeaterLoad.lamps => (300.0, 0.92),
      };
}

class BoardBench extends Bench {
  @override
  String get key => 'board';
  @override
  String get nameAr => 'لوحة توزيع';

  /// motor load (0 = no load, 1 = full load)
  double motorLoad = 0.7;
  HeaterLoad heater = HeaterLoad.heater;

  /// the X2 test link between L and L'
  bool linkX2 = true;
  double _motorStart = -100;

  BoardBench() {
    switches.addAll({'tog_main': true, 'tog_Q1': true, 'tog_Q2': true, 'tog_Q3': true});
  }

  bool get mainOn => switches['tog_main'] ?? false;
  bool on(String q) => mainOn && (switches['tog_$q'] ?? false);
  bool get motorRuns => on('Q1');

  void setSwitch(String k, bool v) {
    final was = motorRuns;
    switches[k] = v;
    if (!was && motorRuns) _motorStart = t;
  }

  static const _ph = ['L1', 'L2', 'L3'];

  @override
  List<TestPoint> get points => const [
        TestPoint('pt_IN_L1', 'L1 دخول', 'طرف دخول الفاز الأولى على المفتاح الرئيسي (دايمًا فيها كهربا)'),
        TestPoint('pt_IN_L2', 'L2 دخول', 'طرف دخول الفاز التانية'),
        TestPoint('pt_IN_L3', 'L3 دخول', 'طرف دخول الفاز التالتة'),
        TestPoint('pt_IN_N', 'N دخول', 'طرف دخول النيوترال على المفتاح الرئيسي'),
        TestPoint('pt_Q1_L1', 'Q1:1', 'خرج قاطع المحرك، الفاز الأولى'),
        TestPoint('pt_Q1_L2', 'Q1:2', 'خرج قاطع المحرك، الفاز التانية'),
        TestPoint('pt_Q1_L3', 'Q1:3', 'خرج قاطع المحرك، الفاز التالتة'),
        TestPoint('pt_Q2_L', 'Q2', 'خرج قاطع الإنارة'),
        TestPoint('pt_Q3_L', 'Q3', 'خرج قاطع السخان'),
        TestPoint('pt_N', 'N', 'بارة النيوترال'),
        TestPoint('pt_PE', 'PE', 'بارة الأرضي'),
        TestPoint('pt_X1_L1', 'X1:1', 'ترمينال خروج المحرك، الفاز الأولى'),
        TestPoint('pt_X1_L2', 'X1:2', 'ترمينال خروج المحرك، الفاز التانية'),
        TestPoint('pt_X1_L3', 'X1:3', 'ترمينال خروج المحرك، الفاز التالتة'),
        TestPoint('pt_X1_PE', 'X1:PE', 'ترمينال أرضي المحرك'),
        TestPoint('pt_X2_L', "X2:L", 'ترمينال السخان، الفاز الجاية من القاطع Q3'),
        TestPoint('pt_X2_Lo', "X2:L'", 'ترمينال السخان، الفاز الخارجة للحمل (بعد الكوبري)'),
        TestPoint('pt_X2_N', 'X2:N', 'ترمينال نيوترال السخان'),
      ];

  @override
  Map<String, String> get clamps => const {
        'clamp_L1': 'سلك L1 للمحرك',
        'clamp_L2': 'سلك L2 للمحرك',
        'clamp_L3': 'سلك L3 للمحرك',
        'clamp_CABLE': 'كابل المحرك كله',
        'clamp_Q3': 'سلك السخان',
      };

  /// the X2 load path is closed: by its link, or by an instrument bridging L and L'
  bool get x2Closed => linkX2 || bridges.contains(('pt_X2_L', 'pt_X2_Lo')) || bridges.contains(('pt_X2_Lo', 'pt_X2_L'));

  static const _nPe = Cx(0.35, -0.06); // a little N-PE voltage, as on a real loaded installation

  @override
  Cx voltage(String p) {
    switch (p) {
      case 'pt_IN_L1':
      case 'pt_IN_L2':
      case 'pt_IN_L3':
        return phase(_ph.indexOf(p.substring(6)));
      case 'pt_IN_N':
      case 'pt_N':
      case 'pt_X2_N':
        return _nPe;
      case 'pt_PE':
      case 'pt_X1_PE':
        return Cx.zero;
      case 'pt_Q1_L1':
      case 'pt_Q1_L2':
      case 'pt_Q1_L3':
        return on('Q1') ? phase(_ph.indexOf(p.substring(6))) : Cx.zero;
      case 'pt_X1_L1':
      case 'pt_X1_L2':
      case 'pt_X1_L3':
        return on('Q1') ? phase(_ph.indexOf(p.substring(6))) : Cx.zero;
      case 'pt_Q2_L':
        return on('Q2') ? phase(0) : Cx.zero;
      case 'pt_Q3_L':
      case 'pt_X2_L':
        return on('Q3') ? phase(0) : Cx.zero;
      case 'pt_X2_Lo':
        return on('Q3') && x2Closed ? phase(0) : _nPe; // open: the load pulls it to N
    }
    return Cx.zero;
  }

  /// the motor's line current: magnetising + load part, 6× rated for a moment after a start
  double get motorAmps {
    if (!motorRuns) return 0;
    const iMag = 4.7, iAct = 6.7;
    final run = math.sqrt(iMag * iMag + math.pow(iAct * motorLoad, 2));
    final since = t - _motorStart;
    if (since < 1.6) {
      final k = math.exp(-since / 0.55);
      return run + (8.2 * 6 - run) * k;
    }
    return run;
  }

  double get motorPf {
    const iMag = 4.7, iAct = 6.7;
    final a = iAct * math.max(0.02, motorLoad);
    return a / math.sqrt(iMag * iMag + a * a);
  }

  Cx motorCurrent(int i) {
    final a = motorAmps;
    final phi = math.acos(motorPf) * 180 / math.pi;
    return Cx.polar(a, [0.0, -120.0, 120.0][i] - phi);
  }

  /// the X2 load current (L -> L' -> load -> N)
  Cx get heaterCurrent {
    if (!on('Q3') || !x2Closed) return Cx.zero;
    final (w, pf) = heater.pq;
    final amps = w / (vPhase * pf);
    return Cx.polar(amps, -math.acos(pf) * 180 / math.pi);
  }

  @override
  Cx clampCurrent(String id) {
    switch (id) {
      case 'clamp_L1':
        return motorCurrent(0);
      case 'clamp_L2':
        return motorCurrent(1);
      case 'clamp_L3':
        return motorCurrent(2);
      case 'clamp_CABLE':
        // L1 + L2 + L3 (+ PE carrying nothing) inside the jaw: they cancel
        return motorCurrent(0) + motorCurrent(1) + motorCurrent(2) + const Cx(0.012, 0.004) * (motorRuns ? 1 : 0);
      case 'clamp_Q3':
        return heaterCurrent;
    }
    return Cx.zero;
  }

  @override
  Bridge bridge(String a, String b) {
    final ab = {a, b};
    if (ab.containsAll(['pt_X2_L', 'pt_X2_Lo']) && !linkX2) {
      final i = on('Q3') ? _bridgedHeater : Cx.zero;
      return Bridge(a == 'pt_X2_L' ? i : -i);
    }
    if (ab.containsAll(['pt_X2_L', 'pt_X2_Lo']) && linkX2) {
      // the link is still in: it carries (almost) all of the current
      final i = on('Q3') ? heaterCurrent * 0.004 : Cx.zero;
      return Bridge(a == 'pt_X2_L' ? i : -i);
    }
    final v = between(a, b);
    if (v.abs > 12) return Bridge(v * (1 / 0.05), short: true);
    return const Bridge(Cx.zero);
  }

  Cx get _bridgedHeater {
    final (w, pf) = heater.pq;
    return Cx.polar(w / (vPhase * pf), -math.acos(pf) * 180 / math.pi);
  }

  @override
  Net deadNet() {
    final n = Net();
    // bonds
    n.add('pt_PE', 'pt_X1_PE', 0.04);
    n.add('pt_N', 'pt_X2_N', 0.03);
    n.add('pt_N', 'pt_IN_N', 0.02);
    if (mainOn) {
      // through the main switch the outgoing side joins the incoming terminals
      for (final p in _ph) {
        n.add('pt_IN_$p', 'MAIN_$p', 0.005);
      }
    }
    // Q1 -> X1 -> motor windings (star, 1.5 ohm each) -> insulated from earth
    for (final p in _ph) {
      if (on('Q1') || switches['tog_Q1'] == true) n.add('MAIN_$p', 'pt_Q1_$p', 0.005);
      n.add('pt_Q1_$p', 'pt_X1_$p', 0.01);
      n.add('pt_X1_$p', 'M_star', 1.5);
      n.add('pt_X1_$p', 'pt_PE', 600e6);
    }
    if (switches['tog_Q2'] == true) n.add('MAIN_L1', 'pt_Q2_L', 0.005);
    if (switches['tog_Q3'] == true) n.add('MAIN_L1', 'pt_Q3_L', 0.005);
    n.add('pt_Q3_L', 'pt_X2_L', 0.01);
    if (linkX2) n.add('pt_X2_L', 'pt_X2_Lo', 0.002);
    final (w, pf) = heater.pq;
    final cold = heater == HeaterLoad.heater ? vPhase * vPhase / w : (heater == HeaterLoad.motor ? 4.2 : 1.2e3);
    n.add('pt_X2_Lo', 'pt_X2_N', cold * (pf > 0 ? 1 : 1));
    n.add('pt_X2_Lo', 'pt_PE', 900e6);
    return n;
  }

  @override
  Map<String, Object?> view3d() => {
        'switches': {...switches},
        'linkX2': linkX2,
      };
}

// ======================================================================= motor
enum MotorFault { none, damp, earth, open, turns, phaseShort }

extension MotorFaultInfo on MotorFault {
  String get nameAr => switch (this) {
        MotorFault.none => 'محرك سليم',
        MotorFault.damp => 'رطوبة في الملفات',
        MotorFault.earth => 'ملف لامس في الجسم',
        MotorFault.open => 'ملف مقطوع',
        MotorFault.turns => 'قصر بين لفّات ملف',
        MotorFault.phaseShort => 'قصر بين ملفين',
      };
}

class MotorBench extends Bench {
  @override
  String get key => 'motor';
  @override
  String get nameAr => 'محرك 3 فاز';

  /// 'star' | 'delta' | 'none' (links taken out)
  String links = 'star';
  MotorFault fault = MotorFault.none;

  MotorBench() {
    switches['tog_iso'] = false;
  }

  bool get supply => switches['tog_iso'] ?? false;
  bool get runs => supply && links != 'none' && fault != MotorFault.open;

  @override
  List<TestPoint> get points => const [
        TestPoint('pt_U1', 'U1', 'بداية الملف الأول (هنا بتدخل الفاز L1)'),
        TestPoint('pt_V1', 'V1', 'بداية الملف التاني (L2)'),
        TestPoint('pt_W1', 'W1', 'بداية الملف التالت (L3)'),
        TestPoint('pt_U2', 'U2', 'نهاية الملف الأول'),
        TestPoint('pt_V2', 'V2', 'نهاية الملف التاني'),
        TestPoint('pt_W2', 'W2', 'نهاية الملف التالت'),
        TestPoint('pt_PE', 'PE', 'مسمار الأرضي جوه علبة الترامل'),
        TestPoint('pt_BODY', 'الجسم', 'جسم المحرك (حتة معدن مكشوفة عند الرجل)'),
      ];

  static const _w = ['U', 'V', 'W'];

  @override
  Cx voltage(String p) {
    if (!supply) return Cx.zero;
    final n = p.replaceFirst('pt_', '');
    if (n == 'PE' || n == 'BODY') return Cx.zero;
    final i = _w.indexOf(n[0]);
    if (i < 0) return Cx.zero;
    if (n[1] == '1') return phase(i);
    // end of a winding
    if (fault == MotorFault.open && i == 2) {
      // W winding broken: its end follows whatever it is linked to
      if (links == 'star') return Cx.zero;
    }
    switch (links) {
      case 'star':
        return Cx.zero; // the star point sits at (almost) neutral potential
      case 'delta':
        // U1-W2, V1-U2, W1-V2
        return phase(const [1, 2, 0][i]);
      default:
        return fault == MotorFault.open && i == 2 ? Cx.zero : phase(i); // no current: the end is at its start's voltage
    }
  }

  double windingR(int i) {
    if (fault == MotorFault.open && i == 2) return kInf;
    if (fault == MotorFault.turns && i == 0) return 1.08;
    return const [1.52, 1.5, 1.51][i];
  }

  /// insulation of each winding to the body, ohms
  double insulationToBody(int i) {
    switch (fault) {
      case MotorFault.damp:
        return i == 0 ? 0.6e6 : 45e6;
      case MotorFault.earth:
        return i == 1 ? 2.2e3 : 700e6;
      default:
        return const [850e6, 780e6, 920e6][i];
    }
  }

  double insulationBetween(int i, int j) {
    if (fault == MotorFault.phaseShort && {i, j}.containsAll([0, 1])) return 8e3;
    if (fault == MotorFault.damp) return 120e6;
    return 2.5e9;
  }

  @override
  Net deadNet() {
    final n = Net();
    for (var i = 0; i < 3; i++) {
      final w = _w[i];
      final r = windingR(i);
      if (r.isFinite) {
        n.add('pt_${w}1', 'pt_${w}2', r);
      } else {
        // a broken winding: both ends still sit on the same insulation
        n.add('pt_${w}2', 'pt_${w}1_open', 1e-3);
      }
      n.add('pt_${w}1', 'pt_BODY', insulationToBody(i));
    }
    for (final (i, j) in const [(0, 1), (1, 2), (2, 0)]) {
      n.add('pt_${_w[i]}1', 'pt_${_w[j]}1', insulationBetween(i, j));
    }
    n.add('pt_PE', 'pt_BODY', 0.03);
    if (links == 'star') {
      n.add('pt_U2', 'pt_V2', 0.002);
      n.add('pt_V2', 'pt_W2', 0.002);
    } else if (links == 'delta') {
      n.add('pt_U1', 'pt_W2', 0.002);
      n.add('pt_V1', 'pt_U2', 0.002);
      n.add('pt_W1', 'pt_V2', 0.002);
    }
    return n;
  }

  @override
  Bridge bridge(String a, String b) {
    final v = between(a, b);
    if (v.abs > 12) return Bridge(v * (1 / 0.05), short: true);
    return const Bridge(Cx.zero);
  }

  @override
  Map<String, Object?> view3d() => {
        'switches': {...switches},
        'links': links,
        'run': runs ? 1.0 : 0.0,
      };
}
