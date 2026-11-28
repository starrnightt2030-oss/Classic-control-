import 'dart:ui' show Offset, Size;

/// Wire insulation colours used in residential wiring (IEC).
enum WireColor { brown, blue, earth, black, grey, red }

const wireColorNames = {
  WireColor.brown: 'بني (فاز)',
  WireColor.red: 'أحمر (فاز)',
  WireColor.blue: 'أزرق (نيوترال)',
  WireColor.earth: 'أخضر وأصفر (أرضي)',
  WireColor.black: 'أسود (راجع)',
  WireColor.grey: 'رمادي (متنقل)',
};

/// One connection point on a part.
class TermDef {
  final String id;
  final String label;
  final Offset pos; // inside the part box, in board units
  const TermDef(this.id, this.label, this.pos);
}

/// What kind of electrical behaviour a part has.
enum Kind {
  supply, mcb, rcd, meter, nbar, ebar, jbox,
  sw1, sw2, swi, swd, pb, dimmer,
  lamp, socket, bell, lock, tube, ballast, starter, stair, driver, ledpanel,
}

class PartType {
  final Kind kind;
  final String name;
  final String en;
  final Size size;
  final List<TermDef> terms;
  final String symbol; // key of the IEC symbol painter
  const PartType(this.kind, this.name, this.en, this.size, this.terms, {this.symbol = ''});

  TermDef term(String id) => terms.firstWhere((t) => t.id == id);
}

/// Board units: 1 unit = 1 logical px on a 1000 x 700 board.
const partTypes = <Kind, PartType>{
  Kind.supply: PartType(Kind.supply, 'مصدر التغذية', 'Supply 220V', Size(120, 90), [
    TermDef('L', 'L', Offset(25, 75)), TermDef('N', 'N', Offset(60, 75)), TermDef('PE', 'PE', Offset(95, 75)),
  ]),
  Kind.mcb: PartType(Kind.mcb, 'قاطع آلي', 'MCB', Size(46, 110), [
    TermDef('in', '1', Offset(23, 10)), TermDef('out', '2', Offset(23, 100)),
  ]),
  Kind.rcd: PartType(Kind.rcd, 'مفتاح تسريب أرضي', 'RCD 30mA', Size(90, 110), [
    TermDef('Li', 'L', Offset(25, 10)), TermDef('Ni', 'N', Offset(65, 10)),
    TermDef('Lo', 'L', Offset(25, 100)), TermDef('No', 'N', Offset(65, 100)),
  ]),
  Kind.meter: PartType(Kind.meter, 'العداد الكهربي', 'Energy meter', Size(120, 150), [
    TermDef('Li', '1', Offset(18, 138)), TermDef('Lo', '3', Offset(46, 138)),
    TermDef('Ni', '4', Offset(74, 138)), TermDef('No', '6', Offset(102, 138)),
  ]),
  Kind.nbar: PartType(Kind.nbar, 'قضيب النيوترال', 'Neutral bar', Size(110, 34), [
    TermDef('n1', 'N', Offset(15, 17)), TermDef('n2', 'N', Offset(42, 17)), TermDef('n3', 'N', Offset(68, 17)), TermDef('n4', 'N', Offset(95, 17)),
  ]),
  Kind.ebar: PartType(Kind.ebar, 'قضيب الأرضي', 'Earth bar', Size(110, 34), [
    TermDef('e1', 'PE', Offset(15, 17)), TermDef('e2', 'PE', Offset(42, 17)), TermDef('e3', 'PE', Offset(68, 17)), TermDef('e4', 'PE', Offset(95, 17)),
  ]),
  Kind.jbox: PartType(Kind.jbox, 'علبة تجميع', 'Junction box', Size(110, 110), [
    TermDef('a', '1', Offset(30, 30)), TermDef('b', '2', Offset(80, 30)), TermDef('c', '3', Offset(30, 80)), TermDef('d', '4', Offset(80, 80)),
  ]),
  Kind.sw1: PartType(Kind.sw1, 'مفتاح مفرد', 'One-way switch', Size(86, 86), [
    TermDef('L', 'L', Offset(25, 74)), TermDef('1', 'L1', Offset(61, 74)),
  ]),
  Kind.sw2: PartType(Kind.sw2, 'مفتاح دفياتير', 'Two-way switch', Size(86, 86), [
    TermDef('C', 'C', Offset(18, 74)), TermDef('1', 'L1', Offset(43, 74)), TermDef('2', 'L2', Offset(68, 74)),
  ]),
  Kind.swi: PartType(Kind.swi, 'مفتاح انترميديت', 'Intermediate switch', Size(86, 86), [
    TermDef('A1', 'A1', Offset(16, 74)), TermDef('A2', 'A2', Offset(34, 74)), TermDef('B1', 'B1', Offset(52, 74)), TermDef('B2', 'B2', Offset(70, 74)),
  ]),
  Kind.swd: PartType(Kind.swd, 'مفتاح توالي (مزدوج)', 'Two-gang switch', Size(86, 86), [
    TermDef('L', 'L', Offset(18, 74)), TermDef('1', 'L1', Offset(43, 74)), TermDef('2', 'L2', Offset(68, 74)),
  ]),
  Kind.pb: PartType(Kind.pb, 'ضاغط جرس', 'Push button', Size(70, 70), [
    TermDef('1', '1', Offset(18, 60)), TermDef('2', '2', Offset(52, 60)),
  ]),
  Kind.dimmer: PartType(Kind.dimmer, 'دايمر', 'Dimmer', Size(86, 86), [
    TermDef('L', 'L', Offset(25, 74)), TermDef('1', 'L1', Offset(61, 74)),
  ]),
  Kind.lamp: PartType(Kind.lamp, 'لمبة ودواية', 'Lamp holder', Size(80, 100), [
    TermDef('L', 'L', Offset(25, 90)), TermDef('N', 'N', Offset(55, 90)),
  ]),
  Kind.socket: PartType(Kind.socket, 'بريزة بأرضي', 'Socket 16A', Size(86, 86), [
    TermDef('L', 'L', Offset(18, 74)), TermDef('N', 'N', Offset(43, 74)), TermDef('PE', 'PE', Offset(68, 74)),
  ]),
  Kind.bell: PartType(Kind.bell, 'جرس كهربي', 'Bell', Size(80, 80), [
    TermDef('1', '1', Offset(22, 70)), TermDef('2', '2', Offset(58, 70)),
  ]),
  Kind.lock: PartType(Kind.lock, 'كالون كهربي', 'Electric lock', Size(70, 110), [
    TermDef('1', '1', Offset(20, 100)), TermDef('2', '2', Offset(50, 100)),
  ]),
  Kind.tube: PartType(Kind.tube, 'أنبوبة فلورسنت', 'Fluorescent tube', Size(300, 50), [
    TermDef('A1', 'A1', Offset(10, 14)), TermDef('A2', 'A2', Offset(10, 38)),
    TermDef('B1', 'B1', Offset(290, 14)), TermDef('B2', 'B2', Offset(290, 38)),
  ]),
  Kind.ballast: PartType(Kind.ballast, 'ملف خانق (بلاست)', 'Ballast', Size(110, 44), [
    TermDef('1', '1', Offset(12, 22)), TermDef('2', '2', Offset(98, 22)),
  ]),
  Kind.starter: PartType(Kind.starter, 'ستارتر', 'Starter', Size(50, 60), [
    TermDef('1', '1', Offset(14, 52)), TermDef('2', '2', Offset(36, 52)),
  ]),
  Kind.stair: PartType(Kind.stair, 'ماكينة السلم', 'Staircase timer', Size(60, 110), [
    TermDef('L', 'L', Offset(12, 10)), TermDef('N', 'N', Offset(30, 10)), TermDef('S', '3', Offset(48, 10)),
    TermDef('O', '4', Offset(30, 100)),
  ]),
  Kind.driver: PartType(Kind.driver, 'درايفر LED', 'LED driver', Size(120, 50), [
    TermDef('L', 'L', Offset(12, 14)), TermDef('N', 'N', Offset(12, 36)),
    TermDef('+', '+', Offset(108, 14)), TermDef('-', '−', Offset(108, 36)),
  ]),
  Kind.ledpanel: PartType(Kind.ledpanel, 'كشاف LED', 'LED panel', Size(120, 120), [
    TermDef('+', '+', Offset(45, 110)), TermDef('-', '−', Offset(75, 110)),
  ]),
};

/// A part placed on a board.
class Part {
  final String id; // E1, S1, Q1 ...
  final Kind kind;
  Offset pos; // top-left on the board
  /// user-visible state
  bool on; // switch position (sw1/swd gang a/pb pressed/sw2 position 2/swi crossed)
  bool on2; // second gang of swd
  double level; // dimmer 0..1
  int watts; // lamp/tube/ballast rating
  bool led; // lamp is an LED bulb
  bool plug; // socket has a load plugged in
  int rating; // MCB rating (A)
  Part(this.id, this.kind, this.pos,
      {this.on = false, this.on2 = false, this.level = 1, this.watts = 0, this.led = false, this.plug = false, this.rating = 10});

  PartType get type => partTypes[kind]!;
  Offset termPos(String t) => pos + type.term(t).pos;

  Part copy() => Part(id, kind, pos, on: on, on2: on2, level: level, watts: watts, led: led, plug: plug, rating: rating);

  Map<String, dynamic> toJson() => {
        'id': id, 'k': kind.name, 'x': pos.dx, 'y': pos.dy, 'on': on, 'on2': on2, 'lv': level,
        'w': watts, 'led': led, 'plug': plug, 'r': rating,
      };
  static Part fromJson(Map<String, dynamic> j) => Part(j['id'], Kind.values.byName(j['k']), Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
      on: j['on'] ?? false, on2: j['on2'] ?? false, level: (j['lv'] ?? 1).toDouble(), watts: j['w'] ?? 0, led: j['led'] ?? false, plug: j['plug'] ?? false, rating: j['r'] ?? 10);
}

/// A wire between two terminals, written as "PART.TERM".
class Wire {
  final String a;
  final String b;
  WireColor color;
  Wire(this.a, this.b, this.color);
  bool joins(String x, String y) => (a == x && b == y) || (a == y && b == x);
  bool touches(String t) => a == t || b == t;
  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'c': color.name};
  static Wire fromJson(Map<String, dynamic> j) => Wire(j['a'], j['b'], WireColor.values.byName(j['c']));
}

/// Hidden faults the trainer can put in a working circuit.
enum FaultKind {
  wireCut, // a wire is broken inside its insulation
  looseTerm, // a terminal screw is loose (no contact)
  lampBurnt,
  switchBroken, // contacts never close
  mcbFaulty, // breaker stays open
  starterDead,
  ballastOpen,
  tubeDead, // filament broken
  bellDead,
  switchOnNeutral, // wiring mistake: switch breaks N instead of L (lamp works, holder stays live)
  leakToEarth, // insulation damaged: phase touches earth -> RCD trips
  driverDead,
}

class Fault {
  final FaultKind kind;
  final String target; // part id, wire index "w3", or terminal "S1.L"
  const Fault(this.kind, this.target);
}

const faultNames = {
  FaultKind.wireCut: 'سلك مقطوع جوه العزل',
  FaultKind.looseTerm: 'طرف سايب (مسمار مش مربوط)',
  FaultKind.lampBurnt: 'لمبة محروقة',
  FaultKind.switchBroken: 'مفتاح بايظ (مش بيقفل)',
  FaultKind.mcbFaulty: 'قاطع بايظ',
  FaultKind.starterDead: 'ستارتر بايظ',
  FaultKind.ballastOpen: 'بلاست مقطوع',
  FaultKind.tubeDead: 'فتيلة الأنبوبة مقطوعة',
  FaultKind.bellDead: 'جرس بايظ',
  FaultKind.switchOnNeutral: 'المفتاح متركّب على النيوترال',
  FaultKind.leakToEarth: 'تسريب أرضي (فاز لامس الأرضي)',
  FaultKind.driverDead: 'درايفر بايظ',
};
