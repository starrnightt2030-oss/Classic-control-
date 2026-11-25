// Control Academy — simulation engine (Dart port of the v1 web engine).
//
// Model: every terminal is "<compId>.<termId>". Wires and closed contacts join
// terminals into nets (union-find). Sources put phasors on nets; a net with two
// different phasors from the same source group is a short. Coils pull in when the
// voltage across them is inside their window; the loop repeats until the contact
// state is stable (or chatters). `tick` advances time: timers, coil burn-out,
// motor speed/current, overload heating, the cart on the track.
import 'dart:math' as math;

// ---------------------------------------------------------------- phasors
class Ph {
  final double re, im;
  const Ph(this.re, this.im);
  factory Ph.polar(double mag, double deg) {
    final r = deg * math.pi / 180;
    return Ph(mag * math.cos(r), mag * math.sin(r));
  }
  double get abs => math.sqrt(re * re + im * im);
  Ph operator -(Ph o) => Ph(re - o.re, im - o.im);
  double get angle => ((math.atan2(im, re) * 180 / math.pi) + 360) % 360;
}

const Map<String, List<double>> kPhase = {
  'L1': [220, 0],
  'L2': [220, -120],
  'L3': [220, 120],
  'N': [0, 0],
  'PE': [0, 0],
};

// ---------------------------------------------------------------- types
class Term {
  final String id, side; // side: t (top) · b (bottom) · x (internal, not wireable)
  final double x, y;
  const Term(this.id, this.x, this.y, this.side);
}

typedef Links = List<List<String>> Function(Comp c);

class CompType {
  final String key, nameAr;
  final double w, h;
  final List<Term> Function(Comp c) terms;
  final Links? links;
  final List<String>? coil; // [A1, A2]
  final double Function(Comp c)? rated;
  final bool breaker, wide, station;
  final double rating;
  const CompType({
    required this.key,
    required this.nameAr,
    required this.w,
    required this.h,
    required this.terms,
    this.links,
    this.coil,
    this.rated,
    this.breaker = false,
    this.wide = false,
    this.station = false,
    this.rating = 0,
  });
}

List<Term> _t(List<Term> t) => t;

final Map<String, CompType> kTypes = {
  'sup': CompType(
      key: 'sup', nameAr: 'مصدر التغذية ثلاثي الأطوار 380 فولت', w: 340, h: 78,
      terms: (_) => _t(const [Term('L1', 40, 62, 'b'), Term('L2', 100, 62, 'b'), Term('L3', 160, 62, 'b'), Term('N', 230, 62, 'b'), Term('PE', 290, 62, 'b')])),
  'mcb1': CompType(
      key: 'mcb1', nameAr: 'قاطع أحادي القطب', w: 44, h: 124, breaker: true, rating: 6,
      terms: (_) => _t(const [Term('1', 22, 12, 't'), Term('2', 22, 112, 'b')]),
      links: (c) => c.s.on ? [['1', '2']] : []),
  'mcb3': CompType(
      key: 'mcb3', nameAr: 'قاطع ثلاثي الأقطاب', w: 120, h: 124, breaker: true, rating: 16,
      terms: (_) => _t(const [Term('1', 22, 12, 't'), Term('3', 60, 12, 't'), Term('5', 98, 12, 't'), Term('2', 22, 112, 'b'), Term('4', 60, 112, 'b'), Term('6', 98, 112, 'b')]),
      links: (c) => c.s.on ? [['1', '2'], ['3', '4'], ['5', '6']] : []),
  'trafo': CompType(
      key: 'trafo', nameAr: 'محوّل التحكم', w: 128, h: 136,
      terms: (_) => _t(const [Term('P0', 22, 12, 't'), Term('P220', 64, 12, 't'), Term('P380', 106, 12, 't'), Term('S0', 22, 124, 'b'), Term('S24', 64, 124, 'b'), Term('S48', 106, 124, 'b')])),
  'kc': CompType(
      key: 'kc', nameAr: 'كونتاكتور', w: 136, h: 156, coil: const ['A1', 'A2'],
      rated: (c) => (c.p['coilV'] as num?)?.toDouble() ?? 220,
      terms: (c) => [
            const Term('A1', 14, 12, 't'), const Term('1', 38, 12, 't'), const Term('3', 60, 12, 't'), const Term('5', 82, 12, 't'),
            const Term('13', 104, 12, 't'), const Term('21', 124, 12, 't'),
            const Term('A2', 14, 144, 'b'), const Term('2', 38, 144, 'b'), const Term('4', 60, 144, 'b'), const Term('6', 82, 144, 'b'),
            const Term('14', 104, 144, 'b'), const Term('22', 124, 144, 'b'),
            if (c.p['aux'] == true) ...const [Term('53', 52, 54, 't'), Term('61', 86, 54, 't'), Term('54', 52, 104, 'b'), Term('62', 86, 104, 'b')],
          ],
      links: (c) {
        final aux = c.p['aux'] == true;
        if (c.s.on) return [['1', '2'], ['3', '4'], ['5', '6'], ['13', '14'], if (aux) ['53', '54']];
        return [['21', '22'], if (aux) ['61', '62']];
      }),
  'ol': CompType(
      key: 'ol', nameAr: 'أوفرلود حراري', w: 176, h: 104,
      terms: (_) => _t(const [
            Term('95', 146, 14, 't'), Term('97', 166, 14, 't'), Term('2', 38, 92, 'b'), Term('4', 60, 92, 'b'), Term('6', 82, 92, 'b'),
            Term('96', 146, 92, 'b'), Term('98', 166, 92, 'b'), Term('1', 38, -4, 'x'), Term('3', 60, -4, 'x'), Term('5', 82, -4, 'x'),
          ]),
      links: (c) => [['1', '2'], ['3', '4'], ['5', '6'], c.s.trip ? ['97', '98'] : ['95', '96']]),
  'relay': CompType(
      key: 'relay', nameAr: 'مرحّل مساعد', w: 108, h: 150, coil: const ['A1', 'A2'],
      rated: (c) => (c.p['coilV'] as num?)?.toDouble() ?? 220,
      terms: (_) => _t(const [Term('A1', 16, 12, 't'), Term('11', 52, 12, 't'), Term('21', 88, 12, 't'), Term('A2', 12, 138, 'b'), Term('12', 34, 138, 'b'), Term('14', 54, 138, 'b'), Term('22', 76, 138, 'b'), Term('24', 96, 138, 'b')]),
      links: (c) => c.s.on ? [['11', '14'], ['21', '24']] : [['11', '12'], ['21', '22']]),
  'timer': CompType(
      key: 'timer', nameAr: 'مؤقت', w: 78, h: 150, coil: const ['A1', 'A2'], rated: (_) => 230, wide: true,
      terms: (_) => _t(const [Term('A1', 18, 12, 't'), Term('15', 58, 12, 't'), Term('A2', 14, 138, 'b'), Term('16', 39, 138, 'b'), Term('18', 64, 138, 'b')]),
      links: (c) => c.s.sw ? [['15', '18']] : [['15', '16']]),
  'pb_no': CompType(
      key: 'pb_no', nameAr: 'ضاغط تشغيل NO', w: 76, h: 124, station: true,
      terms: (_) => _t(const [Term('13', 38, 12, 't'), Term('14', 38, 112, 'b')]),
      links: (c) => c.s.pr ? [['13', '14']] : []),
  'pb_nc': CompType(
      key: 'pb_nc', nameAr: 'ضاغط إيقاف NC', w: 76, h: 124, station: true,
      terms: (_) => _t(const [Term('11', 38, 12, 't'), Term('12', 38, 112, 'b')]),
      links: (c) => c.s.pr ? [] : [['11', '12']]),
  'estop': CompType(
      key: 'estop', nameAr: 'مفتاح الطوارئ', w: 84, h: 124, station: true,
      terms: (_) => _t(const [Term('11', 42, 12, 't'), Term('12', 42, 112, 'b')]),
      links: (c) => c.s.lat ? [] : [['11', '12']]),
  'sel': CompType(
      key: 'sel', nameAr: 'مفتاح اختيار', w: 84, h: 124, station: true,
      terms: (_) => _t(const [Term('13', 22, 12, 't'), Term('21', 62, 12, 't'), Term('14', 22, 112, 'b'), Term('22', 62, 112, 'b')]),
      links: (c) => c.s.pos != 0 ? [['13', '14']] : [['21', '22']]),
  'lamp': CompType(
      key: 'lamp', nameAr: 'لمبة بيان', w: 66, h: 124, station: true,
      terms: (_) => _t(const [Term('X1', 33, 12, 't'), Term('X2', 33, 112, 'b')])),
  'ls': CompType(
      key: 'ls', nameAr: 'مفتاح نهاية الشوط', w: 84, h: 118,
      terms: (_) => _t(const [Term('11', 20, 12, 't'), Term('23', 64, 12, 't'), Term('12', 20, 106, 'b'), Term('24', 64, 106, 'b')]),
      links: (c) => c.s.act ? [['23', '24']] : [['11', '12']]),
  'motor': CompType(
      key: 'motor', nameAr: 'محرك حثي ثلاثي الأطوار', w: 220, h: 236,
      terms: (_) => _t(const [Term('W2', 60, 26, 't'), Term('U2', 105, 26, 't'), Term('V2', 150, 26, 't'), Term('U1', 60, 64, 't'), Term('V1', 105, 64, 't'), Term('W1', 150, 64, 't'), Term('PE', 190, 45, 't')]),
      links: (c) => switch (c.p['links']) {
            'delta' => [['U1', 'W2'], ['V1', 'U2'], ['W1', 'V2']],
            'star' => [['U2', 'V2'], ['V2', 'W2']],
            _ => <List<String>>[],
          }),
  // single-phase capacitor motor: main winding U1-U2, auxiliary (capacitor) winding Z1-Z2.
  // Swapping Z1/Z2 against U1/U2 reverses it.
  'motor1': CompType(
      key: 'motor1', nameAr: 'محرك أحادي الطور بمكثف', w: 180, h: 160,
      terms: (_) => _t(const [Term('U1', 0, 0, 't'), Term('U2', 0, 0, 't'), Term('Z1', 0, 0, 't'), Term('Z2', 0, 0, 't'), Term('PE', 0, 0, 't')])),
  // a machine driven by a motor (p['motor']): cart on a track, hoist, lift, tank + pump.
  // Each of its position / level switches has an NC pair Sn1-Sn2 and an NO pair Sn3-Sn4.
  'mach': CompType(
      key: 'mach', nameAr: 'آلة', w: 300, h: 200,
      terms: (c) => _t([
            for (var i = 1; i <= machSwitches(c.p['kind'] as String?); i++) ...[
              Term('S${i}1', 0, 0, 'b'),
              Term('S${i}2', 0, 0, 'b'),
              Term('S${i}3', 0, 0, 'b'),
              Term('S${i}4', 0, 0, 'b'),
            ]
          ]),
      links: (c) => [
            for (var i = 1; i <= machSwitches(c.p['kind'] as String?); i++) c.s.ms[i - 1] ? ['S${i}3', 'S${i}4'] : ['S${i}1', 'S${i}2'],
          ]),
  // ---- Panel Lab devices
  'mcb2': CompType(
      key: 'mcb2', nameAr: 'قاطع ثنائي الأقطاب', w: 80, h: 124, breaker: true, rating: 10,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('3', 0, 0, 't'), Term('2', 0, 0, 'b'), Term('4', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2'], ['3', '4']] : []),
  'mcb4': CompType(
      key: 'mcb4', nameAr: 'قاطع رباعي الأقطاب', w: 150, h: 124, breaker: true, rating: 20,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('3', 0, 0, 't'), Term('5', 0, 0, 't'), Term('7', 0, 0, 't'), Term('2', 0, 0, 'b'), Term('4', 0, 0, 'b'), Term('6', 0, 0, 'b'), Term('8', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2'], ['3', '4'], ['5', '6'], ['7', '8']] : []),
  'fuse': CompType(
      key: 'fuse', nameAr: 'مصهر', w: 40, h: 124, breaker: true, rating: 2,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('2', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2']] : []),
  'rccb': CompType(
      key: 'rccb', nameAr: 'قاطع التسرب الأرضي', w: 80, h: 124, breaker: true, rating: 25,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('N', 0, 0, 't'), Term('2', 0, 0, 'b'), Term('N2', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2'], ['N', 'N2']] : []),
  'mpcb': CompType(
      key: 'mpcb', nameAr: 'قاطع حماية المحرك', w: 90, h: 124, breaker: true, rating: 12,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('3', 0, 0, 't'), Term('5', 0, 0, 't'), Term('2', 0, 0, 'b'), Term('4', 0, 0, 'b'), Term('6', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2'], ['3', '4'], ['5', '6']] : []),
  'aux': CompType(
      key: 'aux', nameAr: 'بلوك مساعد', w: 80, h: 60,
      terms: (_) => _t(const [Term('53', 0, 0, 't'), Term('61', 0, 0, 't'), Term('71', 0, 0, 't'), Term('83', 0, 0, 't'), Term('54', 0, 0, 'b'), Term('62', 0, 0, 'b'), Term('72', 0, 0, 'b'), Term('84', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['53', '54'], ['83', '84']] : [['61', '62'], ['71', '72']]),
  'tsd': CompType(
      key: 'tsd', nameAr: 'مؤقت ستار دلتا', w: 80, h: 120, coil: const ['A1', 'A2'], rated: (_) => 230, wide: true,
      terms: (_) => _t(const [Term('A1', 0, 0, 't'), Term('A2', 0, 0, 'b'), Term('17', 0, 0, 't'), Term('18', 0, 0, 'b'), Term('28', 0, 0, 'b')]),
      links: (c) {
        if (!c.s.on) return [];
        final tm = c.num_('T');
        if (c.s.el < tm) return [['17', '18']];
        if (c.s.el >= tm + 0.06) return [['17', '28']];
        return [];
      }),
  'psu': CompType(
      key: 'psu', nameAr: 'مزوّد قدرة 24 فولت', w: 120, h: 130,
      terms: (_) => _t(const [Term('L', 0, 0, 't'), Term('N', 0, 0, 't'), Term('PE', 0, 0, 't'), Term('P', 0, 0, 'b'), Term('P2', 0, 0, 'b'), Term('M', 0, 0, 'b'), Term('M2', 0, 0, 'b')]),
      links: (_) => [['P', 'P2'], ['M', 'M2']]),
  'phr': CompType(
      key: 'phr', nameAr: 'مرحّل مراقبة الأطوار', w: 80, h: 120,
      terms: (_) => _t(const [Term('L1', 0, 0, 't'), Term('L2', 0, 0, 't'), Term('L3', 0, 0, 't'), Term('11', 0, 0, 'b'), Term('12', 0, 0, 'b'), Term('14', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['11', '14']] : [['11', '12']]),
  // schematic: one auxiliary contact that follows its host device (attach = host id)
  // p['kind']: NO · NC · TNO · TNC (timer, timed state) · OLNO · OLNC (overload trip)
  'contact': CompType(
      key: 'contact', nameAr: 'تلامس', w: 40, h: 80,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('2', 0, 0, 'b')]),
      links: (c) => c.s.on ? [['1', '2']] : []),
  'tb': CompType(
      key: 'tb', nameAr: 'طرف توصيل', w: 20, h: 60,
      terms: (_) => _t(const [Term('1', 0, 0, 't'), Term('2', 0, 0, 'b')]),
      links: (_) => [['1', '2']]),
};

// ---------------------------------------------------------------- components
class CompState {
  // breakers
  bool on = false, trip = false;
  // coils
  double v = 0, burn = 0;
  bool hum = false, dead = false, blocked = false;
  // timer
  bool sw = false;
  double el = 0;
  // overload
  double heat = 0, current = 0;
  // stations
  bool pr = false, lat = false;
  int pos = 0;
  // limit switch
  bool act = false, man = false;
  // motor
  String mode = 'off';
  double spd = 0, ang = 0;
  int dir = 0;
  List<double> vw = const [0, 0, 0];
  bool load = false;
  // transformer / power supply
  double k = 0;
  // machine: position / level 0…1 and its switches
  double mx = 0;
  List<bool> ms = [false, false, false];
  bool valve = true; // tank outlet open
  // injected fault (free lab): coil_open · weld · nc_open · no_close · lamp_dead · phase_loss
  String? fault;
}

class Comp {
  final String id, type;
  final Map<String, Object?> p;
  final String? attach;
  double x, y;
  final CompState s = CompState();
  Comp(this.id, this.type, {Map<String, Object?>? p, this.attach, this.x = 0, this.y = 0}) : p = {...?p} {
    switch (type) {
      case 'mcb1':
      case 'mcb2':
      case 'mcb3':
      case 'mcb4':
      case 'fuse':
      case 'rccb':
        s.on = true;
      case 'mpcb':
        s.on = true;
        this.p['set'] ??= 8.5;
      case 'tsd':
        this.p['T'] ??= 5.0;
      case 'timer':
        this.p['mode'] ??= 'on';
        this.p['T'] ??= 3.0;
      case 'ol':
        this.p['set'] ??= 8.5;
      case 'motor':
        this.p['links'] ??= 'delta';
        this.p['In'] ??= 8.5;
      case 'lamp':
        this.p['col'] ??= 'g';
        this.p['V'] ??= 220.0;
      case 'pb_no':
        this.p['col'] ??= 'g';
      case 'pb_nc':
        this.p['col'] ??= 'r';
    }
    if (type == 'mach') {
      s.mx = (this.p['x0'] as num?)?.toDouble() ?? switch (this.p['kind']) { 'cart' => 0.5, 'tank' => 0.1, _ => 0.0 };
    }
    if (type == 'motor1') this.p['In'] ??= 4.0;
    if (this.p['burnt'] == true) s.dead = true;
  }
  CompType get t => kTypes[type]!;
  List<Term> get terms => t.terms(this);
  double num_(String k) => (p[k] as num).toDouble();
  String? get label => p['lb'] as String?;
}

class Wire {
  final String a, b, col;
  final bool power;
  const Wire(this.a, this.b, {this.col = 'rd', this.power = false});
  @override
  String toString() => '$a—$b';
}

int machSwitches(String? kind) => kind == 'lift' ? 3 : 2;

/// where each machine switch sits (cart / hoist: ends · lift: floors · tank: float levels)
List<double> machPoints(String? kind) => switch (kind) {
      'lift' => const [0.0, 0.5, 1.0],
      'tank' => const [0.2, 0.85],
      _ => const [0.0, 1.0],
    };

class Track {
  final String motor, left, right;
  double x = 0;
  Track(this.motor, this.left, this.right);
}

class SimEvent {
  final String t;
  final String? id;
  final Map<String, Object?> data;
  const SimEvent(this.t, [this.id, this.data = const {}]);
  @override
  String toString() => '$t${id == null ? '' : ':$id'}';
}

class ShortInfo {
  final String a, b;
  final String? breaker;
  final double at;
  /// terminals of the net where the two sources met (for the spark effect)
  final Set<String> terms;
  const ShortInfo(this.a, this.b, this.breaker, this.at, [this.terms = const {}]);
}

// ---------------------------------------------------------------- nets
class _UF {
  final Map<String, String> p = {};
  String f(String a) {
    final q = p[a];
    if (q == null) {
      p[a] = a;
      return a;
    }
    if (q == a) return a;
    final r = f(q);
    p[a] = r;
    return r;
  }

  void u(String a, String b) {
    final x = f(a), y = f(b);
    if (x != y) p[x] = y;
  }
}

class _Src {
  final String g, key;
  final Ph ph;
  const _Src(this.g, this.ph, this.key);
}

class Nets {
  final _UF _uf;
  final Map<String, List<_Src>> _src;
  Nets._(this._uf, this._src);
  String root(String term) => _uf.f(term);
  bool same(String a, String b) => _uf.f(a) == _uf.f(b);
  _Src? pot(String term) {
    final l = _src[_uf.f(term)];
    return (l == null || l.isEmpty) ? null : l.first;
  }

  /// true when the net carries any voltage source (used to draw live wires)
  bool live(String term) => pot(term) != null;
  double vAcross(String a, String b) {
    final pa = pot(a), pb = pot(b);
    if (pa == null || pb == null || pa.g != pb.g) return 0;
    return (pa.ph - pb.ph).abs;
  }

  /// phase key of the net (L1/L2/L3/N/PE…) or null
  String? phaseOf(String term) => pot(term)?.key;

  /// source group of the net: 'M' mains, 'T:<id>' transformer, 'D:<id>' 24 V DC supply
  String? group(String term) => pot(term)?.g;
}

// ---------------------------------------------------------------- lab
class Lab {
  final List<Comp> comps = [];
  final List<Wire> wires = [];
  /// wires with an injected break (free-lab faults): drawn, but carry nothing
  final Set<Wire> brokenWires = {};

  /// contact pairs of [c] including injected faults
  List<List<String>> linksOf(Comp c) {
    final f = c.s.fault;
    final ty = c.t;
    if (ty.links == null) return const [];
    if (f == 'weld' && (c.type == 'kc' || c.type == 'relay')) {
      final was = c.s.on;
      c.s.on = true;
      final l = ty.links!(c);
      c.s.on = was;
      return l;
    }
    var l = ty.links!(c);
    if (f == 'nc_open') {
      const nc = {'95-96', '11-12', '21-22', '61-62', '71-72', '15-16'};
      l = [for (final x in l) if (!nc.contains('${x[0]}-${x[1]}')) x];
    }
    if (f == 'no_close') {
      const no = {'13-14', '53-54', '83-84', '15-18', '11-14', '23-24'};
      l = [for (final x in l) if (!no.contains('${x[0]}-${x[1]}')) x];
    }
    if (f == 'open_pole' && l.isNotEmpty) l = l.sublist(1);
    return l;
  }

  final List<List<String>> mech = []; // mechanical interlock pairs
  Track? track;
  bool power = false;
  double t = 0;
  final List<SimEvent> events = [];
  ShortInfo? short;
  Nets? nets;
  bool chatter = false;

  Comp? byId(String id) {
    for (final c in comps) {
      if (c.id == id) return c;
    }
    return null;
  }

  Comp operator [](String id) => byId(id)!;

  void emit(SimEvent e) => events.add(e);

  /// events since the last call (for UI sounds / toasts)
  List<SimEvent> drain() {
    final out = List<SimEvent>.of(events);
    events.clear();
    return out;
  }

  Nets buildNets({String? exclude}) {
    final uf = _UF();
    for (final w in wires) {
      if (!brokenWires.contains(w)) uf.u(w.a, w.b);
    }
    for (final c in comps) {
      final ty = c.t;
      if (ty.links != null && exclude != c.id) {
        for (final l in linksOf(c)) {
          uf.u('${c.id}.${l[0]}', '${c.id}.${l[1]}');
        }
      }
      if (c.attach != null && c.type == 'ol') {
        final par = byId(c.attach!);
        if (par != null) {
          for (final pr in const [['2', '1'], ['4', '3'], ['6', '5']]) {
            uf.u('${par.id}.${pr[0]}', '${c.id}.${pr[1]}');
          }
        }
      }
    }
    final src = <String, List<_Src>>{};
    void add(String term, String g, Ph ph, String key) => (src[uf.f(term)] ??= []).add(_Src(g, ph, key));
    if (power) {
      for (final s in comps.where((c) => c.type == 'sup')) {
        kPhase.forEach((k, v) {
          if (s.s.fault == 'phase_loss' && k == (s.p['lost'] ?? 'L3')) return;
          add('${s.id}.$k', 'M', Ph.polar(v[0], v[1]), k);
        });
      }
    }
    for (final c in comps) {
      if (c.type == 'psu' && c.s.k > 0.05) {
        final g = 'D:${c.id}';
        add('${c.id}.M', g, const Ph(0, 0), '0V');
        add('${c.id}.P', g, const Ph(24, 0), '24V');
      }
      if (c.type == 'trafo' && c.s.k > 0.05) {
        final g = 'T:${c.id}';
        add('${c.id}.S0', g, const Ph(0, 0), 'S0');
        add('${c.id}.S24', g, Ph(24 * c.s.k, 0), 'S24');
        add('${c.id}.S48', g, Ph(48 * c.s.k, 0), 'S48');
      }
    }
    return Nets._(uf, src);
  }

  static (String, String, String)? _findShort(Nets n) {
    for (final e in n._src.entries) {
      final l = e.value;
      for (var i = 0; i < l.length; i++) {
        for (var j = i + 1; j < l.length; j++) {
          if (l[i].g == l[j].g && (l[i].ph - l[j].ph).abs > 5) return (l[i].key, l[j].key, e.key);
        }
      }
    }
    return null;
  }

  Set<String> _termsOfNet(Nets n, String root) => {
        for (final w in wires) ...[w.a, w.b],
        for (final c in comps)
          for (final t in c.terms) '${c.id}.${t.id}',
      }.where((t) => n.root(t) == root).toSet();

  List<double> coilWindow(Comp c) {
    if (c.t.wide) return const [20, 264, 300];
    final r = c.t.rated!(c);
    return [r * 0.8, r * 1.15, r * 1.3];
  }

  void _tripBreaker(Comp c, String why) {
    c.s.on = false;
    c.s.trip = true;
    emit(SimEvent('trip', c.id, {'why': why}));
  }

  /// Settle all contacts for the current inputs.
  void solve() {
    var guard = 0;
    for (var it = 0; it < 24; it++) {
      final n = buildNets();
      final sh = _findShort(n);
      if (sh != null) {
        final cands = comps.where((c) => c.t.breaker && c.s.on).toList()..sort((a, b) => a.t.rating.compareTo(b.t.rating));
        Comp? hit;
        for (final c in cands) {
          if (_findShort(buildNets(exclude: c.id)) == null) {
            hit = c;
            break;
          }
        }
        short = ShortInfo(sh.$1, sh.$2, hit?.id, t, _termsOfNet(n, sh.$3));
        if (hit != null) {
          _tripBreaker(hit, 'short');
        } else {
          power = false;
          emit(const SimEvent('mainTrip'));
        }
        emit(SimEvent('short', hit?.id, {'a': sh.$1, 'b': sh.$2}));
        if (++guard > 6) break;
        continue;
      }
      var changed = false;
      for (final c in comps.where((c) => c.type == 'trafo')) {
        final v220 = n.vAcross('${c.id}.P0', '${c.id}.P220'), v380 = n.vAcross('${c.id}.P0', '${c.id}.P380');
        var k = 0.0;
        if (v380 > 1) {
          k = v380 / 380;
        } else if (v220 > 1) {
          k = v220 / 220;
        }
        if ((k - c.s.k).abs() > 0.01) {
          c.s.k = k;
          changed = true;
        }
      }
      for (final c in comps.where((c) => c.type == 'psu')) {
        final v = n.vAcross('${c.id}.L', '${c.id}.N');
        final k = (v > 85 && v < 270) ? 1.0 : 0.0;
        if (k != c.s.k) {
          c.s.k = k;
          changed = true;
        }
      }
      for (final c in comps.where((c) => c.type == 'phr')) {
        final p1 = n.pot('${c.id}.L1'), p2 = n.pot('${c.id}.L2'), p3 = n.pot('${c.id}.L3');
        var ok = false;
        if (p1 != null && p2 != null && p3 != null && p1.g == 'M' && p2.g == 'M' && p3.g == 'M') {
          final all = (p1.ph - p2.ph).abs > 330 && (p2.ph - p3.ph).abs > 330 && (p3.ph - p1.ph).abs > 330;
          final d = ((p2.ph.angle - p1.ph.angle) + 360) % 360;
          ok = all && d > 180;
        }
        if (ok != c.s.on) {
          c.s.on = ok;
          changed = true;
          emit(SimEvent(ok ? 'kon' : 'koff', c.id, {'type': 'relay'}));
        }
      }
      for (final c in comps.where((c) => c.type == 'contact')) {
        final host = c.attach == null ? null : byId(c.attach!);
        final kind = (c.p['kind'] as String?) ?? 'NO';
        final bool active;
        if (host == null) {
          active = false;
        } else if (host.type == 'timer') {
          active = kind.startsWith('T') ? host.s.sw : host.s.on;
        } else if (host.type == 'ol') {
          active = host.s.trip;
        } else {
          active = host.s.on;
        }
        final closed = kind.endsWith('NO') ? active : !active;
        if (closed != c.s.on) {
          c.s.on = closed;
          changed = true;
        }
      }
      for (final c in comps.where((c) => c.type == 'aux')) {
        final host = c.attach == null ? null : byId(c.attach!);
        final on = host?.s.on ?? false;
        if (on != c.s.on) {
          c.s.on = on;
          changed = true;
        }
      }
      if (changed) continue;
      final want = <String, bool>{};
      for (final c in comps) {
        final coil = c.t.coil;
        if (coil == null) continue;
        final v = n.vAcross('${c.id}.${coil[0]}', '${c.id}.${coil[1]}');
        c.s.v = v;
        final w = coilWindow(c);
        final ok = !c.s.dead && c.s.fault != 'coil_open' && v >= w[0] && v <= w[1] * 1.3;
        want[c.id] = ok;
        c.s.hum = !c.s.dead && !ok && v > w[0] * 0.35;
        c.s.blocked = false;
      }
      for (final m in mech) {
        final a = m[0], b = m[1];
        if ((want[a] ?? false) && (want[b] ?? false)) {
          final A = this[a], B = this[b];
          if (A.s.on && !B.s.on) {
            want[b] = false;
            B.s.blocked = true;
          } else if (B.s.on && !A.s.on) {
            want[a] = false;
            A.s.blocked = true;
          } else if (!A.s.on && !B.s.on) {
            want[a] = want[b] = false;
            A.s.blocked = B.s.blocked = true;
          }
        }
      }
      for (final c in comps) {
        final nv = want[c.id];
        if (nv == null) continue;
        if (c.type == 'timer') {
          if (nv != c.s.on) {
            c.s.on = nv;
            changed = true;
            if (c.p['mode'] == 'off') {
              if (nv) {
                if (!c.s.sw) {
                  c.s.sw = true;
                  emit(SimEvent('tsw', c.id));
                }
                c.s.el = 0;
              }
            } else if (!nv) {
              if (c.s.sw) emit(SimEvent('tsw', c.id));
              c.s.sw = false;
              c.s.el = 0;
            }
          }
        } else if (nv != c.s.on) {
          c.s.on = nv;
          changed = true;
          emit(SimEvent(nv ? 'kon' : 'koff', c.id, {'type': c.type}));
        }
      }
      if (!changed) {
        nets = n;
        chatter = false;
        _loads(n);
        return;
      }
    }
    chatter = true;
    nets = buildNets();
    _loads(nets!);
    emit(const SimEvent('chatter'));
  }

  void _loads(Nets n) {
    for (final c in comps) {
      if (c.type == 'lamp') {
        final v = n.vAcross('${c.id}.X1', '${c.id}.X2');
        c.s.v = (c.s.dead || c.s.fault == 'lamp_dead') ? 0 : v;
        if (!c.s.dead && v > c.num_('V') * 1.4) {
          c.s.dead = true;
          c.s.v = 0;
          emit(SimEvent('pop', c.id));
        }
      }
      if (c.type == 'motor') _motor(n, c);
      if (c.type == 'motor1') _motor1(n, c);
    }
  }

  void _motor1(Nets n, Comp m) {
    Ph? pot(String t) {
      final p = n.pot('${m.id}.$t');
      return (p != null && p.g == 'M') ? p.ph : null;
    }

    final u1 = pot('U1'), u2 = pot('U2'), z1 = pot('Z1'), z2 = pot('Z2');
    final vm = (u1 != null && u2 != null) ? u1 - u2 : null;
    final va = (z1 != null && z2 != null) ? z1 - z2 : null;
    m.s.vw = [vm?.abs ?? 0, va?.abs ?? 0, 0];
    var mode = 'off';
    final main = vm?.abs ?? 0, aux = va?.abs ?? 0;
    if (m.s.dead) {
      mode = 'dead';
    } else if (main > 300 || aux > 300) {
      mode = 'over';
    } else if (main > 180 && aux > 180) {
      mode = 'run';
      m.s.dir = (vm!.re * va!.re + vm.im * va.im) >= 0 ? 1 : -1;
    } else if (main > 40) {
      mode = 'single'; // main winding alone: hums, no starting torque
    }
    if (mode != m.s.mode) {
      emit(SimEvent('motor', m.id, {'mode': mode, 'prev': m.s.mode}));
      m.s.mode = mode;
    }
  }

  void _motor(Nets n, Comp m) {
    const w = [['U1', 'U2'], ['V1', 'V2'], ['W1', 'W2']];
    const tt = ['U1', 'U2', 'V1', 'V2', 'W1', 'W2'];
    final pot = <String, Ph?>{};
    for (final t in tt) {
      final p = n.pot('${m.id}.$t');
      pot[t] = (p != null && p.g == 'M') ? p.ph : null;
    }
    // star point: terminals joined together with no source take the mean of the far ends
    final groups = <String, List<String>>{};
    for (final t in tt) {
      if (pot[t] == null) (groups[n.root('${m.id}.$t')] ??= []).add(t);
    }
    String other(String t) {
      for (final x in w) {
        if (x[0] == t) return x[1];
        if (x[1] == t) return x[0];
      }
      return t;
    }

    for (final ts in groups.values) {
      if (ts.length < 2) continue;
      final oth = ts.map(other).where((o) => pot[o] != null).toList();
      if (oth.length < 2) continue;
      var re = 0.0, im = 0.0;
      for (final o in oth) {
        re += pot[o]!.re;
        im += pot[o]!.im;
      }
      final p = Ph(re / ts.length, im / ts.length);
      for (final t in ts) {
        pot[t] = p;
      }
    }
    final vw = [for (final x in w) (pot[x[0]] != null && pot[x[1]] != null) ? (pot[x[0]]! - pot[x[1]]!).abs : 0.0];
    m.s.vw = vw;
    var mode = 'off';
    if (m.s.dead) {
      mode = 'dead';
    } else if (vw.any((v) => v > 460)) {
      mode = 'over';
    } else if (vw.every((v) => v > 330)) {
      mode = 'delta';
    } else if (vw.every((v) => v > 180 && v <= 260)) {
      mode = 'star';
    } else if (vw.any((v) => v > 40)) {
      mode = 'single';
    }
    if (mode == 'delta' || mode == 'star') {
      final d = ((pot['V1']!.angle - pot['U1']!.angle) + 360) % 360;
      m.s.dir = d > 180 ? 1 : -1;
    }
    if (mode != m.s.mode) {
      emit(SimEvent('motor', m.id, {'mode': mode, 'prev': m.s.mode}));
      m.s.mode = mode;
    }
  }

  /// Advance time; returns true when a contact changed and the circuit must be re-solved.
  bool tick(double dt) {
    t += dt;
    var dirty = false;
    for (final c in comps) {
      if (c.type == 'timer') {
        final tm = c.num_('T');
        if (c.p['mode'] == 'on') {
          if (c.s.on && !c.s.sw) {
            c.s.el += dt;
            if (c.s.el >= tm) {
              c.s.sw = true;
              dirty = true;
              emit(SimEvent('tsw', c.id));
            }
          }
        } else if (!c.s.on && c.s.sw) {
          c.s.el += dt;
          if (c.s.el >= tm) {
            c.s.sw = false;
            c.s.el = 0;
            dirty = true;
            emit(SimEvent('tsw', c.id));
          }
        }
        if (c.s.v > 300 && !c.s.dead) {
          c.s.dead = true;
          c.s.on = false;
          c.s.sw = false;
          dirty = true;
          emit(SimEvent('burn', c.id));
        }
      } else if (c.t.coil != null) {
        final b = coilWindow(c)[2];
        if (c.s.v > b && !c.s.dead) {
          c.s.burn += dt;
          if (c.s.burn > 1.2) {
            c.s.dead = true;
            c.s.on = false;
            dirty = true;
            emit(SimEvent('burn', c.id));
          }
        } else {
          c.s.burn = 0;
        }
      }
      if (c.type == 'tsd') {
        final tm = c.num_('T');
        if (c.s.on) {
          final before = c.s.el;
          c.s.el += dt;
          if ((before < tm && c.s.el >= tm) || (before < tm + 0.06 && c.s.el >= tm + 0.06)) {
            dirty = true;
            emit(SimEvent('tsw', c.id));
          }
        } else {
          c.s.el = 0;
        }
      }
      if (c.type == 'motor' || c.type == 'motor1') dirty = _motorTick(c, dt) || dirty;
      if (c.type == 'mach') dirty = _machTick(c, dt) || dirty;
    }
    for (final c in comps) {
      if ((c.type == 'ol' || c.type == 'mpcb') && c.s.trip) c.s.heat = math.max(0.0, c.s.heat - 25 * dt);
    }
    final tr = track;
    if (tr != null) {
      final m = byId(tr.motor);
      if (m != null) tr.x = (tr.x + m.s.spd * m.s.dir * dt * 0.16).clamp(0.0, 1.0).toDouble();
      for (final (side, lid) in [('l', tr.left), ('r', tr.right)]) {
        final ls = byId(lid);
        if (ls == null) continue;
        final hit = side == 'l' ? tr.x <= 0.05 : tr.x >= 0.95;
        final act = hit || ls.s.man;
        if (act != ls.s.act) {
          ls.s.act = act;
          dirty = true;
          emit(SimEvent('ls', lid, {'act': act}));
        }
      }
    }
    return dirty;
  }

  bool _machTick(Comp c, double dt) {
    final kind = c.p['kind'] as String?;
    Comp? m = c.p['motor'] == null ? null : byId(c.p['motor'] as String);
    m ??= comps.where((o) => o.type == 'motor' || o.type == 'motor1').firstOrNull;
    final running = m != null && (m.s.mode == 'star' || m.s.mode == 'delta' || m.s.mode == 'run');
    final v = running ? m.s.spd * (m.s.dir == 0 ? 1 : m.s.dir) : 0.0; // braked when off
    switch (kind) {
      case 'tank':
        c.s.mx += (running ? m.s.spd * 0.075 : 0) * dt - (c.s.valve ? 0.03 : 0) * dt;
      case 'lift':
        c.s.mx += v * 0.09 * dt;
      case 'hoist':
        c.s.mx += v * 0.12 * dt;
      default:
        c.s.mx += v * 0.16 * dt;
    }
    c.s.mx = c.s.mx.clamp(0.0, 1.0).toDouble();
    final pts = machPoints(kind);
    var dirty = false;
    for (var i = 0; i < pts.length; i++) {
      final x = c.s.mx, p = pts[i];
      final bool act = switch (kind) {
        'tank' => x >= p,
        'lift' => (x - p).abs() <= 0.015,
        _ => i == 0 ? x <= 0.02 : x >= 0.98,
      };
      if (act != c.s.ms[i]) {
        c.s.ms[i] = act;
        dirty = true;
        emit(SimEvent('ls', c.id, {'act': act, 'sw': i + 1}));
      }
    }
    return dirty;
  }

  bool _motorTick(Comp c, double dt) {
    final s = c.s, inom = c.num_('In');
    var dirty = false;
    var tgt = 0.0, rate = 0.5;
    if (s.mode == 'delta' || s.mode == 'run') {
      tgt = 1;
      rate = 0.9;
    } else if (s.mode == 'star') {
      tgt = 0.86;
      rate = 0.42;
    }
    if (s.load && tgt > 0) tgt *= 0.94;
    s.spd += (tgt - s.spd) * math.min(1.0, dt * (tgt > s.spd ? rate * 1.6 : 0.7));
    if (tgt == 0 && s.spd < 0.004) s.spd = 0;
    final slip = tgt > 0 ? math.max(0.0, tgt - s.spd) / tgt : 0.0;
    var i = 0.0;
    if (s.mode == 'delta' || s.mode == 'run') {
      i = inom * (1 + 5 * math.pow(slip, 0.8));
    } else if (s.mode == 'star') {
      i = inom / 3 * (1 + 5 * math.pow(slip, 0.8)) * 1.15;
    } else if (s.mode == 'single') {
      i = inom * 5;
    } else if (s.mode == 'over') {
      i = inom * 3;
    }
    if (s.load && (s.mode == 'delta' || s.mode == 'star' || s.mode == 'run')) i *= 2.2;
    s.current = i;
    s.ang = (s.ang + s.spd * (s.dir == 0 ? 1 : s.dir) * dt * 900) % 360;
    final n = nets;
    Comp? ol;
    if (n != null) {
      for (final o in comps) {
        if (o.type != 'ol' && o.type != 'mpcb') continue;
        if (['2', '4', '6'].any((t) => ['U1', 'V1', 'W1'].any((u) => n.same('${o.id}.$t', '${c.id}.$u')))) {
          ol = o;
          break;
        }
      }
    }
    if (ol != null) {
      ol.s.current = i;
      final r = i / ol.num_('set');
      if (r > 1.1 && !ol.s.trip) {
        ol.s.heat += 4 * (r * r - 1.1) * dt;
      } else if (!ol.s.trip) {
        ol.s.heat = math.max(0.0, ol.s.heat - 12 * dt);
      }
      if (ol.s.heat > 150 && !ol.s.trip) {
        ol.s.trip = true;
        ol.s.heat = 150;
        if (ol.type == 'mpcb') ol.s.on = false;
        dirty = true;
        emit(SimEvent('oltrip', ol.id));
      }
    } else if (s.mode == 'single' || s.mode == 'over') {
      s.burn += dt;
      if (s.burn > 6 && !s.dead) {
        s.dead = true;
        dirty = true;
        emit(SimEvent('mburn', c.id));
      }
    }
    return dirty;
  }

  void step(double dt) {
    if (tick(dt)) solve();
  }

  /// run `seconds` of simulated time in small steps
  void run(double seconds, {double dt = 0.05}) {
    var left = seconds;
    while (left > 1e-9) {
      final d = math.min(dt, left);
      step(d);
      left -= d;
    }
  }

  void setPower(bool on) {
    power = on;
    emit(SimEvent(on ? 'powerOn' : 'powerOff'));
    solve();
  }

  /// User action on a component. what: press · estop · sel · mcb · olreset · oltest · ls · load
  void actuate(String id, String what, [bool val = true]) {
    final c = byId(id);
    if (c == null) return;
    switch (what) {
      case 'press':
        c.s.pr = val;
      case 'estop':
        c.s.lat = !c.s.lat;
      case 'sel':
        c.s.pos = c.s.pos != 0 ? 0 : 1;
      case 'mcb':
        if (c.s.on) {
          c.s.on = false;
        } else {
          c.s.on = true;
          c.s.trip = false;
        }
      case 'olreset':
        if (c.s.trip) {
          if (c.s.heat > 40) {
            emit(SimEvent('olhot', id));
            return;
          }
          c.s.trip = false;
          c.s.heat = 0;
          emit(SimEvent('olreset', id));
        }
      case 'oltest':
        if (!c.s.trip) {
          c.s.trip = true;
          c.s.heat = 60;
          emit(SimEvent('oltrip', id));
        }
      case 'ls':
        c.s.man = val;
        final tr = track;
        final onTrack = tr != null && (tr.left == id || tr.right == id);
        c.s.act = onTrack ? (val || (tr.left == id ? tr.x <= 0.05 : tr.x >= 0.95)) : val;
      case 'load':
        c.s.load = !c.s.load;
      case 'valve':
        c.s.valve = !c.s.valve;
    }
    solve();
  }

  // ------------------------------------------------------------ current paths
  /// Which wires carry current now: wire index → +1 (flows a→b) or -1 (b→a).
  /// For every load that draws current (energised coil, lit lamp, motor winding,
  /// supply primaries) the shortest conductor path from each of its terminals back
  /// to a source terminal is traced: towards the load on the line side, away from it
  /// on the return side.
  Map<int, int> flowPaths() {
    final n = nets;
    final out = <int, int>{};
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
      if (c.type == 'sup' && power) {
        for (final k in kPhase.keys) {
          if (c.s.fault == 'phase_loss' && k == (c.p['lost'] ?? 'L3')) continue;
          src.add('${c.id}.$k');
        }
      }
      if (c.type == 'trafo' && c.s.k > 0.05) src.addAll(['${c.id}.S0', '${c.id}.S24', '${c.id}.S48']);
      if (c.type == 'psu' && c.s.k > 0.05) src.addAll(['${c.id}.P', '${c.id}.M']);
    }
    final loads = <(String, String)>[];
    for (final c in comps) {
      if (c.s.dead) continue;
      final coil = c.t.coil;
      if (coil != null && c.s.v > 15 && c.s.fault != 'coil_open') loads.add(('${c.id}.${coil[0]}', '${c.id}.${coil[1]}'));
      if (c.type == 'lamp' && c.s.v > 5) loads.add(('${c.id}.X1', '${c.id}.X2'));
      if (c.type == 'psu' && c.s.k > 0.05) loads.add(('${c.id}.L', '${c.id}.N'));
      if (c.type == 'trafo' && c.s.k > 0.05) {
        final hi = n.vAcross('${c.id}.P0', '${c.id}.P380') > 1 ? 'P380' : 'P220';
        loads.add(('${c.id}.$hi', '${c.id}.P0'));
      }
      if (c.type == 'motor1') {
        if (c.s.vw[0] > 40) loads.add(('${c.id}.U1', '${c.id}.U2'));
        if (c.s.vw[1] > 40) loads.add(('${c.id}.Z1', '${c.id}.Z2'));
      }
      if (c.type == 'motor') {
        const w = [['U1', 'U2'], ['V1', 'V2'], ['W1', 'W2']];
        for (var i = 0; i < 3; i++) {
          if (c.s.vw[i] > 40) loads.add(('${c.id}.${w[i][0]}', '${c.id}.${w[i][1]}'));
        }
      }
    }
    const cold = {'N', 'PE', 'S0', '0V'};
    void trace(String from, bool towardsLoad) {
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
        // traversal u→v went a→b when fwd; current runs opposite to the
        // traversal on the line side (source → load)
        if (i >= 0) out.putIfAbsent(i, () => (fwd != towardsLoad) ? 1 : -1);
        v = u;
      }
    }

    for (final (a, b) in loads) {
      final ka = n.phaseOf(a), kb = n.phaseOf(b);
      final aHot = !cold.contains(ka) || cold.contains(kb);
      trace(a, aHot);
      trace(b, !aHot);
    }
    return out;
  }

  // ------------------------------------------------------------ wiring check
  List<String> allTerms() => [
        for (final c in comps)
          for (final t in c.terms)
            if (t.side != 'x') '${c.id}.${t.id}'
      ];

  /// Compares the user's wires with a reference solution by connectivity
  /// (two wirings are equal when they make the same nets).
  WiringDiff wiringDiff(List<Wire> solution) {
    final terms = allTerms();
    _UF part(List<Wire> ws) {
      final uf = _UF();
      for (final t in terms) {
        uf.f(t);
      }
      for (final w in ws) {
        uf.u(w.a, w.b);
      }
      return uf;
    }

    final us = part(wires), so = part(solution);
    return WiringDiff(
      missing: [for (final w in solution) if (us.f(w.a) != us.f(w.b)) w],
      extra: [for (final w in wires) if (so.f(w.a) != so.f(w.b)) w],
    );
  }
}

class WiringDiff {
  final List<Wire> missing, extra;
  const WiringDiff({required this.missing, required this.extra});
  bool get ok => missing.isEmpty && extra.isEmpty;
}

// ---------------------------------------------------------------- helpers for tasks
/// cart position: the circuit track or the first machine in a panel lab
double? cartX(Lab l) => l.track?.x ?? l.comps.where((c) => c.type == 'mach').firstOrNull?.s.mx;

bool motorRunning(Lab l, String m) {
  final x = l.byId(m);
  return x != null && (x.s.mode == 'delta' || x.s.mode == 'star' || x.s.mode == 'run') && x.s.spd > 0.3;
}

bool motorStopped(Lab l, String m) {
  final x = l.byId(m);
  return x != null && x.s.spd < 0.05 && x.s.mode == 'off';
}

bool isOn(Lab l, String k) => l.byId(k)?.s.on ?? false;
