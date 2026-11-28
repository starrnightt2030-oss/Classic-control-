import 'dart:ui' show Offset, Rect, Size;

import '../data/board_geom.dart';

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
  final Offset pos; // inside the unrotated part box, in mm
  const TermDef(this.id, this.label, this.pos);
}

/// What kind of electrical behaviour a part has.
enum Kind {
  supply, mcb, rcd, meter, nbar, ebar, jbox, jbox6, jbox8, jbox10,
  sw1, sw2, swi, swd, pb, dimmer,
  lamp, socket, bell, lock, tube, ballast, starter, stair, driver, ledpanel,
}

const jboxKinds = {Kind.jbox, Kind.jbox6, Kind.jbox8, Kind.jbox10};

/// A part type. Its size and terminal positions come from the Blender front render
/// of the real device (lib/data/board_geom.dart), so the board view, the hit tests
/// and the wires all agree with the picture. Board units are millimetres.
class PartType {
  final Kind kind;
  final String name;
  final String en;
  final String sprite; // base sprite in assets/board
  final List<(String, String)> termIds; // (id, label)
  PartType(this.kind, this.name, this.en, this.sprite, this.termIds);

  SpriteGeom get geom => spriteGeom[sprite]!;
  late final Size size = Size(geom.w, geom.h);
  late final List<TermDef> terms = [for (final t in termIds) TermDef(t.$1, t.$2, geom.terms[t.$1]!)];

  TermDef term(String id) => terms.firstWhere((t) => t.id == id);
}

List<(String, String)> _jt(int n) => [for (var i = 1; i <= n; i++) ('t$i', '$i')];

/// Board units: 1 unit = 1 mm on a 1000 x 620 mm training board.
final partTypes = <Kind, PartType>{
  Kind.supply: PartType(Kind.supply, 'مصدر التغذية', 'Supply 220V', 'supply', [('L', 'L'), ('N', 'N'), ('PE', 'PE')]),
  Kind.mcb: PartType(Kind.mcb, 'قاطع آلي', 'MCB', 'mcb_1p', [('in', '1'), ('out', '2')]),
  Kind.rcd: PartType(Kind.rcd, 'مفتاح تسريب أرضي', 'RCD 30mA', 'rccb', [('Li', 'L'), ('Ni', 'N'), ('Lo', 'L'), ('No', 'N')]),
  Kind.meter: PartType(Kind.meter, 'العداد الكهربي', 'Energy meter', 'kwh_meter', [('Li', '1'), ('Lo', '3'), ('Ni', '4'), ('No', '6')]),
  Kind.nbar: PartType(Kind.nbar, 'قضيب النيوترال', 'Neutral bar', 'nbar', [('n1', 'N'), ('n2', 'N'), ('n3', 'N'), ('n4', 'N')]),
  Kind.ebar: PartType(Kind.ebar, 'قضيب الأرضي', 'Earth bar', 'ebar', [('e1', 'PE'), ('e2', 'PE'), ('e3', 'PE'), ('e4', 'PE')]),
  Kind.jbox: PartType(Kind.jbox, 'علبة تجميع 4 نقط', 'Junction box 4', 'jbox4', _jt(4)),
  Kind.jbox6: PartType(Kind.jbox6, 'علبة تجميع 6 نقط', 'Junction box 6', 'jbox6', _jt(6)),
  Kind.jbox8: PartType(Kind.jbox8, 'علبة تجميع 8 نقط', 'Junction box 8', 'jbox8', _jt(8)),
  Kind.jbox10: PartType(Kind.jbox10, 'علبة تجميع 10 نقط', 'Junction box 10', 'jbox10', _jt(10)),
  Kind.sw1: PartType(Kind.sw1, 'مفتاح مفرد', 'One-way switch', 'sw1_0', [('L', 'L'), ('1', 'L1')]),
  Kind.sw2: PartType(Kind.sw2, 'مفتاح دفياتير', 'Two-way switch', 'sw2_0', [('C', 'C'), ('1', 'L1'), ('2', 'L2')]),
  Kind.swi: PartType(Kind.swi, 'مفتاح انترميديت', 'Intermediate switch', 'swi_0', [('A1', 'A1'), ('A2', 'A2'), ('B1', 'B1'), ('B2', 'B2')]),
  Kind.swd: PartType(Kind.swd, 'مفتاح توالي (مزدوج)', 'Two-gang switch', 'swd_00', [('L', 'L'), ('1', 'L1'), ('2', 'L2')]),
  Kind.pb: PartType(Kind.pb, 'ضاغط جرس', 'Push button', 'pb_0', [('1', '1'), ('2', '2')]),
  Kind.dimmer: PartType(Kind.dimmer, 'دايمر', 'Dimmer', 'dimmer', [('L', 'L'), ('1', 'L1')]),
  Kind.lamp: PartType(Kind.lamp, 'لمبة ودواية', 'Lamp holder', 'lamp_0', [('L', 'L'), ('N', 'N')]),
  Kind.socket: PartType(Kind.socket, 'بريزة بأرضي', 'Socket 16A', 'socket', [('L', 'L'), ('N', 'N'), ('PE', 'PE')]),
  Kind.bell: PartType(Kind.bell, 'جرس كهربي', 'Bell', 'bell', [('1', '1'), ('2', '2')]),
  Kind.lock: PartType(Kind.lock, 'كالون كهربي', 'Electric lock', 'lock_0', [('1', '1'), ('2', '2')]),
  Kind.tube: PartType(Kind.tube, 'أنبوبة فلورسنت', 'Fluorescent tube', 'tube_0', [('A1', 'A1'), ('A2', 'A2'), ('B1', 'B1'), ('B2', 'B2')]),
  Kind.ballast: PartType(Kind.ballast, 'ملف خانق (بلاست)', 'Ballast', 'ballast', [('1', '1'), ('2', '2')]),
  Kind.starter: PartType(Kind.starter, 'ستارتر', 'Starter', 'starter', [('1', '1'), ('2', '2')]),
  Kind.stair: PartType(Kind.stair, 'ماكينة السلم', 'Staircase timer', 'stair', [('L', 'L'), ('N', 'N'), ('S', '3'), ('O', '4')]),
  Kind.driver: PartType(Kind.driver, 'درايفر LED', 'LED driver', 'driver', [('L', 'L'), ('N', 'N'), ('+', '+'), ('-', '−')]),
  Kind.ledpanel: PartType(Kind.ledpanel, 'كشاف LED', 'LED panel', 'ledpanel_0', [('+', '+'), ('-', '−')]),
};

/// Rotate [v] (relative to a box centre) by [rot] quarter turns clockwise (screen axes).
Offset rotQ(Offset v, int rot) => switch (rot & 3) {
      0 => v,
      1 => Offset(-v.dy, v.dx),
      2 => Offset(-v.dx, -v.dy),
      _ => Offset(v.dy, -v.dx),
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
  int rot; // quarter turns clockwise
  Part(this.id, this.kind, this.pos,
      {this.on = false, this.on2 = false, this.level = 1, this.watts = 0, this.led = false, this.plug = false, this.rating = 10, this.rot = 0});

  PartType get type => partTypes[kind]!;

  /// size of the part on the board (after rotation)
  Size get box => rot.isOdd ? Size(type.size.height, type.size.width) : type.size;
  Rect get rect => pos & box;
  Offset get center => pos + Offset(box.width / 2, box.height / 2);

  /// a point of the unrotated part (mm from its top-left) on the board
  Offset toBoard(Offset local) => center + rotQ(local - Offset(type.size.width / 2, type.size.height / 2), rot);

  /// a board point in the part's own (unrotated) coordinates
  Offset toLocal(Offset board) => rotQ(board - center, (4 - (rot & 3)) & 3) + Offset(type.size.width / 2, type.size.height / 2);

  Offset termPos(String t) => toBoard(type.term(t).pos);

  /// the way a wire leaves terminal [t]: away from the part, towards the nearest edge
  Offset termDir(String t) {
    final p = type.term(t).pos, s = type.size;
    final d = [p.dy, s.height - p.dy, p.dx, s.width - p.dx];
    var k = 0;
    for (var i = 1; i < 4; i++) {
      if (d[i] < d[k]) k = i;
    }
    const dirs = [Offset(0, -1), Offset(0, 1), Offset(-1, 0), Offset(1, 0)];
    return rotQ(dirs[k], rot);
  }

  Part copy() => Part(id, kind, pos, on: on, on2: on2, level: level, watts: watts, led: led, plug: plug, rating: rating, rot: rot);

  Map<String, dynamic> toJson() => {
        'id': id, 'k': kind.name, 'x': pos.dx, 'y': pos.dy, 'on': on, 'on2': on2, 'lv': level,
        'w': watts, 'led': led, 'plug': plug, 'r': rating, 'rot': rot,
      };
  static Part fromJson(Map<String, dynamic> j) => Part(j['id'], Kind.values.byName(j['k']), Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
      on: j['on'] ?? false, on2: j['on2'] ?? false, level: (j['lv'] ?? 1).toDouble(), watts: j['w'] ?? 0, led: j['led'] ?? false, plug: j['plug'] ?? false, rating: j['r'] ?? 10, rot: j['rot'] ?? 0);
}

/// A wire between two terminals, written as "PART.TERM".
class Wire {
  final String a;
  final String b;
  WireColor color;
  /// bend points chosen by the student or by "tidy" (board mm); empty = automatic route
  List<Offset> pts;
  Wire(this.a, this.b, this.color, {List<Offset>? pts}) : pts = pts ?? [];
  bool joins(String x, String y) => (a == x && b == y) || (a == y && b == x);
  bool touches(String t) => a == t || b == t;
  Wire copy() => Wire(a, b, color, pts: List.of(pts));
  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'c': color.name, if (pts.isNotEmpty) 'p': [for (final o in pts) [o.dx, o.dy]]};
  static Wire fromJson(Map<String, dynamic> j) => Wire(j['a'], j['b'], WireColor.values.byName(j['c']),
      pts: [for (final o in (j['p'] as List? ?? const [])) Offset((o[0] as num).toDouble(), (o[1] as num).toDouble())]);
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
