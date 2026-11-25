// Lab worksheets: the empty default plate and the DOL starter example.
import 'catalog.dart';
import 'model.dart';

/// position an attached part (overload under / aux block above) relative to its host
void placeAttached(Placed child, Placed host) {
  if (child.def == 'ol') {
    final ht = host.d.termPos()['2'], ct = child.d.termPos()['2'];
    child.x = host.x + (ht?.$1 ?? 0) - (ct?.$1 ?? 0);
    child.y = host.y + (ht?.$2 ?? host.size.height * 0.75) - 5;
  } else if (child.def == 'aux') {
    // side-mounted auxiliary contact block, clipped to the contactor's left flank
    child.x = host.x - child.size.width + 3;
    child.y = host.y + (host.size.height - child.size.height) / 2;
  }
}

LabDoc dolTemplate() {
  final d = LabDoc()
    ..plateW = 570
    ..plateH = 712;
  Placed add(String def, String id, double x, double y, {Map<String, Object?>? p, String? attach}) {
    final q = Placed(id, def, x, y, p: p, attach: attach);
    d.parts.add(q);
    return q;
  }

  double h(String def) => kLabParts[def]?.info?.hMm ?? 80;
  double w(String def) => kLabParts[def]?.info?.wMm ?? 40;
  _structure(d);
  const rail1 = 140.0, rail2 = 360.0;

  // rail 1: supply terminals, main breaker, control breaker
  var x = 80.0;
  add('supply', 'X0', x, rail1 - h('supply') / 2);
  x += w('supply') + 24;
  add('mcb3', 'Q1', x, rail1 - h('mcb3') / 2);
  x += w('mcb3') + 14;
  add('mcb1', 'F1', x, rail1 - h('mcb1') / 2);

  // rail 2: contactor with aux block and overload
  final k1 = add('kc', 'K1', 150, rail2 - h('kc') / 2);
  final aux = add('aux', 'K1A', 0, 0, attach: 'K1');
  placeAttached(aux, k1);
  final ol = add('ol', 'F2', 0, 0, attach: 'K1');
  placeAttached(ol, k1);

  // door devices row and the motor
  var dx = 70.0;
  const dy = 532.0;
  for (final (def, id) in [('estop', 'S00'), ('pb_red', 'S0'), ('pb_green', 'S1'), ('lamp_green', 'H1'), ('lamp_red', 'H2'), ('lamp_amber', 'H3')]) {
    add(def, id, dx, dy);
    dx += w(def) + 11;
  }
  add('motor_d', 'M1', 344, 526);

  void wire(String a, String b, String c) => d.wires.add(LabWire(a, b, c));
  // power
  wire('X0.L1', 'Q1.1', 'br');
  wire('X0.L2', 'Q1.3', 'bk');
  wire('X0.L3', 'Q1.5', 'gy');
  wire('Q1.2', 'K1.1', 'br');
  wire('Q1.4', 'K1.3', 'bk');
  wire('Q1.6', 'K1.5', 'gy');
  wire('F2.2', 'M1.U1', 'br');
  wire('F2.4', 'M1.V1', 'bk');
  wire('F2.6', 'M1.W1', 'gy');
  wire('X0.PE', 'M1.PE', 'ge');
  // control
  wire('Q1.2', 'F1.1', 'rd');
  wire('F1.2', 'F2.95', 'rd');
  wire('F1.2', 'F2.97', 'rd');
  wire('F2.96', 'S00.11', 'rd');
  wire('S00.12', 'S0.11', 'rd');
  wire('S0.12', 'S1.13', 'rd');
  wire('S1.13', 'K1.13', 'rd');
  wire('S1.14', 'K1.14', 'rd');
  wire('K1.14', 'K1.A1', 'rd');
  wire('F2.96', 'K1A.53', 'rd');
  wire('K1A.53', 'K1A.61', 'rd');
  wire('K1A.54', 'H1.X1', 'rd');
  wire('K1A.62', 'H2.X1', 'rd');
  wire('F2.98', 'H3.X1', 'rd');
  // neutral chain
  wire('X0.N', 'K1.A2', 'bu');
  wire('K1.A2', 'H1.X2', 'bu');
  wire('H1.X2', 'H2.X2', 'bu');
  wire('H2.X2', 'H3.X2', 'bu');
  return d;
}

/// two DIN rails; everything else (devices and every wire) is added by the student
void _structure(LabDoc d) {
  d.parts.add(Placed('R1', 'din_rail', 40, 122.5, p: {'len': 490}));
  d.parts.add(Placed('R2', 'din_rail', 40, 342.5, p: {'len': 490}));
}

/// the default worksheet: a compact mounting plate with two DIN rails (parts look
/// big on screen) and a work bench beside it for motors, machines and door devices
LabDoc emptyPanel() {
  final d = LabDoc()
    ..plateW = 430
    ..plateH = 520
    ..benchW = 420;
  d.parts.add(Placed('R1', 'din_rail', 25, 95, p: {'len': 380}));
  d.parts.add(Placed('R2', 'din_rail', 25, 285, p: {'len': 380}));
  return d;
}

/// a wrong wiring that shorts L1 to L2 behind the breaker (spark + trip)
LabDoc shortDemo() {
  final d = emptyPanel();
  final x = kLabParts['supply']!.info?.hMm ?? 60, q = kLabParts['mcb3']!.info?.hMm ?? 90;
  d.parts.add(Placed('X0', 'supply', 90, 140 - x / 2));
  d.parts.add(Placed('Q1', 'mcb3', 260, 140 - q / 2));
  d.wires
    ..add(LabWire('X0.L1', 'Q1.1', 'br'))
    ..add(LabWire('X0.L2', 'Q1.3', 'bk'))
    ..add(LabWire('X0.L3', 'Q1.5', 'gy'))
    ..add(LabWire('Q1.2', 'Q1.4', 'rd'));
  return d;
}

/// a 230 V pilot lamp connected between two phases (400 V): it burns out
LabDoc burnDemo() {
  final d = emptyPanel();
  final x = kLabParts['supply']!.info?.hMm ?? 60, f = kLabParts['mcb2']!.info?.hMm ?? 90;
  d.parts.add(Placed('X0', 'supply', 90, 140 - x / 2));
  d.parts.add(Placed('F1', 'mcb2', 260, 140 - f / 2));
  d.parts.add(Placed('H1', 'lamp_red', 270, 470, p: {'col': 'r', 'V': 220.0}));
  d.wires
    ..add(LabWire('X0.L1', 'F1.1', 'br'))
    ..add(LabWire('X0.L2', 'F1.3', 'bk'))
    ..add(LabWire('F1.2', 'H1.X1', 'rd'))
    ..add(LabWire('F1.4', 'H1.X2', 'rd'));
  return d;
}

/// bench preview: a motor fed straight from a breaker drives the cart; lift, tank
/// and door devices stand beside it
LabDoc benchDemo() {
  final d = emptyPanel();
  final bx = d.plateW + LabDoc.benchGap;
  d.parts.add(Placed('X0', 'supply', 40, 95 + 17.5 - (kLabParts['supply']!.info?.hMm ?? 60) / 2));
  d.parts.add(Placed('Q1', 'mcb3', 160, 95 + 17.5 - (kLabParts['mcb3']!.info?.hMm ?? 90) / 2));
  d.parts.add(Placed('M1', 'motor_d', bx + 10, 20));
  d.parts.add(Placed('W1', 'mach_cart', bx + 10, 215, p: {'kind': 'cart', 'motor': 'M1'}));
  d.parts.add(Placed('S1', 'pb_green', 40, 400));
  d.parts.add(Placed('S2', 'pb_red', 110, 400));
  d.parts.add(Placed('H1', 'lamp_green', 180, 400, p: {'col': 'g', 'V': 220.0}));
  d.parts.add(Placed('M2', 'motor1', 240, 330));
  d.wires
    ..add(LabWire('X0.L1', 'Q1.1', 'br'))
    ..add(LabWire('X0.L2', 'Q1.3', 'bk'))
    ..add(LabWire('X0.L3', 'Q1.5', 'gy'))
    ..add(LabWire('Q1.2', 'M1.U1', 'br'))
    ..add(LabWire('Q1.4', 'M1.V1', 'bk'))
    ..add(LabWire('Q1.6', 'M1.W1', 'gy'))
    ..add(LabWire('Q1.2', 'H1.X1', 'rd'))
    ..add(LabWire('X0.N', 'H1.X2', 'bu'));
  return d;
}
