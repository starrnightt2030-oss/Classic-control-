// The 17 classic circuits as panel-lab exercises: the real devices are already mounted
// (DIN devices on rails, motors / door devices / cart on the bench), no wires. The
// student wires from the schematic and checks the result against the reference wiring.
import 'dart:math' as math;

import '../sim/circuits.dart';
import '../sim/engine.dart';
import 'catalog.dart';
import 'model.dart';
import 'templates.dart';

class LabExercise {
  final Circuit circuit;
  final LabDoc doc;
  final List<Wire> reference; // in lab terminal names
  const LabExercise(this.circuit, this.doc, this.reference);
}

const _auxTerms = {'53', '54', '61', '62', '71', '72', '83', '84'};

LabExercise buildExercise(Circuit c) {
  final comps = [for (final p in c.parts) p()];
  final d = LabDoc()
    ..plateW = 560
    ..plateH = 560
    ..benchW = 470;
  d.mech.addAll(c.mech);
  double w(String def) => kLabParts[def]?.frame.width ?? 40;
  double h(String def) => kLabParts[def]?.frame.height ?? 80;
  Placed add(String def, String id, double x, double y, {Map<String, Object?>? p, String? attach}) {
    final q = Placed(id, def, x, y, p: {...?kLabParts[def]?.params, ...?p}, attach: attach);
    d.parts.add(q);
    return q;
  }

  // ---- plate: rails of DIN devices
  final rows = <List<Comp>>[[], []];
  for (final x in comps) {
    if (const {'sup', 'mcb3', 'mcb1', 'relay', 'timer'}.contains(x.type)) rows[0].add(x);
    if (x.type == 'kc') rows[1].add(x);
  }
  const railGap = 200.0;
  var railY = 95.0;
  var rail = 1;
  void newRail() {
    d.parts.add(Placed('R$rail', 'din_rail', 20, railY - 17.5, p: {'len': d.plateW - 40}));
    rail++;
  }

  var x = 30.0;
  newRail();
  for (final cp in rows[0]) {
    final def = switch (cp.type) { 'sup' => 'supply', 'relay' => 'relay', 'timer' => 'timer', _ => cp.type };
    if (x + w(def) > d.plateW - 25) {
      railY += railGap;
      x = 30;
      newRail();
    }
    final id = cp.type == 'sup' ? 'X0' : cp.id;
    add(def, id, x, railY - h(def) / 2, p: cp.type == 'timer' ? {'mode': cp.p['mode'], 'T': cp.p['T']} : null);
    x += w(def) + 14;
  }
  railY += railGap;
  x = 30;
  newRail();
  final hasAux = {for (final k in rows[1]) if (k.p['aux'] == true) k.id};
  for (final k in rows[1]) {
    final auxW = hasAux.contains(k.id) ? w('aux') - 3 : 0.0;
    if (x + auxW + w('kc') > d.plateW - 25) {
      railY += railGap + 40;
      x = 30;
      newRail();
    }
    final host = add('kc', k.id, x + auxW, railY - h('kc') / 2);
    if (hasAux.contains(k.id)) placeAttached(add('aux', '${k.id}A', 0, 0, attach: k.id), host);
    for (final o in comps.where((o) => o.type == 'ol' && o.attach == k.id)) {
      placeAttached(add('ol', o.id, 0, 0, attach: k.id, p: {'set': 8.5}), host);
    }
    x += auxW + w('kc') + 22;
  }
  d.plateH = math.max(560, railY + 190);

  // ---- bench: door devices, motors, cart
  final bx = d.plateW + LabDoc.benchGap + 14;
  var by = 18.0, bxx = bx;
  for (final cp in comps.where((o) => const {'pb_no', 'pb_nc', 'lamp'}.contains(o.type))) {
    final col = cp.p['col'] as String?;
    final def = switch (cp.type) {
      'pb_no' => 'pb_green',
      'pb_nc' => 'pb_red',
      _ => switch (col) { 'r' => 'lamp_red', 'y' => 'lamp_amber', _ => 'lamp_green' },
    };
    if (bxx + w(def) > bx + d.benchW - 28) {
      bxx = bx;
      by += 50;
    }
    add(def, cp.id, bxx, by, p: cp.type == 'lamp' ? {'col': col ?? 'g', 'V': 220.0} : null);
    bxx += w(def) + 10;
  }
  by += 62;
  var mx = bx;
  final motors = comps.where((o) => o.type == 'motor').toList();
  for (var i = 0; i < motors.length; i++) {
    final m = motors[i];
    if (mx + MotorPlate.w > bx + d.benchW - 10) {
      mx = bx;
      by += MotorPlate.h + 12;
    }
    add(m.p['links'] == 'none' ? 'motor' : 'motor_d', m.id, mx, by);
    mx += MotorPlate.w + 12;
  }
  by += MotorPlate.h + 14;
  final tr = c.track;
  if (tr != null) {
    add('mach_cart', 'W1', bx, by, p: {'kind': 'cart', 'motor': tr.$1, 'x0': c.trackStart});
    by += MachineGeo.size('cart').height + 14;
  }
  d.plateH = math.max(d.plateH, by + 10);

  // ---- reference wiring in lab names
  String ren(String t) {
    final i = t.indexOf('.');
    final id = t.substring(0, i), term = t.substring(i + 1);
    if (id == 'SUP') return 'X0.$term';
    if (hasAux.contains(id) && _auxTerms.contains(term)) return '${id}A.$term';
    if (tr != null && (id == tr.$2 || id == tr.$3)) {
      final n = id == tr.$2 ? 1 : 2;
      final k = const {'11': 1, '12': 2, '23': 3, '24': 4}[term] ?? 1;
      return 'W1.S$n$k';
    }
    return t;
  }

  final ref = [
    for (final wr in c.wires) Wire(ren(wr.a), ren(wr.b), col: wr.col, power: wr.power)
  ];
  return LabExercise(c, d, ref);
}

/// readable terminal name for the check results: "K1 · 13"
String prettyTerm(String t) {
  final i = t.indexOf('.');
  if (i < 0) return t;
  var id = t.substring(0, i), term = t.substring(i + 1);
  if (id == 'W1' && term.length == 3) {
    id = 'LS${term[1]}';
    term = const {'1': '11', '2': '12', '3': '23', '4': '24'}[term[2]] ?? term;
  }
  if (id.endsWith('A') && _auxTerms.contains(term)) id = id.substring(0, id.length - 1);
  return '$id · $term';
}
