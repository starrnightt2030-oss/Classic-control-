// Ready-made panels for the lab: the DOL starter wired like a real panel.
import 'catalog.dart';
import 'model.dart';

/// position an attached part (overload under / aux block above) relative to its host
void placeAttached(Placed child, Placed host) {
  if (child.def == 'ol') {
    final ht = host.d.termPos()['2'], ct = child.d.termPos()['2'];
    child.x = host.x + (ht?.$1 ?? 0) - (ct?.$1 ?? 0);
    child.y = host.y + (ht?.$2 ?? host.size.height * 0.75) - 5;
  } else if (child.def == 'aux') {
    child.x = host.x + (host.size.width - child.size.width) / 2;
    child.y = host.y - child.size.height + 7;
  }
}

LabDoc dolTemplate() {
  final d = LabDoc()
    ..plateW = 900
    ..plateH = 800;
  Placed add(String def, String id, double x, double y, {Map<String, Object?>? p, String? attach}) {
    final q = Placed(id, def, x, y, p: p, attach: attach);
    d.parts.add(q);
    return q;
  }

  double h(String def) => kLabParts[def]?.info?.hMm ?? 80;
  double w(String def) => kLabParts[def]?.info?.wMm ?? 40;

  // structure: two rails between three horizontal ducts, one vertical duct on the left
  add('duct_h', 'D1', 70, 24, p: {'len': 800});
  const rail1 = 165.0, rail2 = 405.0;
  add('din_rail', 'R1', 70, rail1 - 17.5, p: {'len': 800});
  add('duct_h', 'D2', 70, 262, p: {'len': 800});
  add('din_rail', 'R2', 70, rail2 - 17.5, p: {'len': 800});
  add('duct_h', 'D3', 70, 540, p: {'len': 800});
  add('duct_v', 'D4', 20, 24, p: {'len': 716});
  add('duct_h', 'D5', 70, 700, p: {'len': 520});

  // rail 1: supply terminals, main breaker, control breaker
  var x = 110.0;
  add('supply', 'X0', x, rail1 - h('supply') / 2);
  x += w('supply') + 30;
  add('mcb3', 'Q1', x, rail1 - h('mcb3') / 2);
  x += w('mcb3') + 18;
  add('mcb1', 'F1', x, rail1 - h('mcb1') / 2);

  // rail 2: contactor with aux block and overload
  final k1 = add('kc', 'K1', 160, rail2 - h('kc') / 2);
  final aux = add('aux', 'K1A', 0, 0, attach: 'K1');
  placeAttached(aux, k1);
  final ol = add('ol', 'F2', 0, 0, attach: 'K1');
  placeAttached(ol, k1);

  // door devices row and the motor
  var dx = 120.0;
  const dy = 600.0;
  for (final (def, id) in [('estop', 'S00'), ('pb_red', 'S0'), ('pb_green', 'S1'), ('lamp_green', 'H1'), ('lamp_red', 'H2'), ('lamp_amber', 'H3')]) {
    add(def, id, dx, dy);
    dx += w(def) + 22;
  }
  add('motor', 'M1', 650, 592);

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

LabDoc emptyPanel() {
  final d = LabDoc()
    ..plateW = 900
    ..plateH = 800;
  d.parts.add(Placed('D1', 'duct_h', 70, 24, p: {'len': 800}));
  d.parts.add(Placed('R1', 'din_rail', 70, 147.5, p: {'len': 800}));
  d.parts.add(Placed('D2', 'duct_h', 70, 262, p: {'len': 800}));
  d.parts.add(Placed('R2', 'din_rail', 70, 387.5, p: {'len': 800}));
  d.parts.add(Placed('D3', 'duct_h', 70, 540, p: {'len': 800}));
  d.parts.add(Placed('D4', 'duct_v', 20, 24, p: {'len': 716}));
  d.parts.add(Placed('D5', 'duct_h', 70, 700, p: {'len': 520}));
  return d;
}
