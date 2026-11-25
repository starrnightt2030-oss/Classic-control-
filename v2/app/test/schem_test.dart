import 'dart:ui';

import 'package:classic_control/schem/model.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SPlaced tagged(SchemDoc d, String tag, String sym) => d.syms.firstWhere((s) => s.tag == tag && s.sym == sym);

  test('DOL schematic: start, hold-in, lamps, stop', () {
    final d = dolSchematic();
    final s = d.toSim();
    expect(s.warnings, isEmpty);
    final l = s.lab..setPower(true);
    expect(l.events.any((e) => e.t == 'short'), isFalse);
    final h1 = tagged(d, 'H1', 'lamp'), h2 = tagged(d, 'H2', 'lamp');
    expect(l[h2.id].s.v, greaterThan(200), reason: 'stop lamp through K1 NC');
    expect(l[h1.id].s.v, lessThan(1));
    final s1 = tagged(d, 'S1', 'pb_no'), s0 = tagged(d, 'S0', 'pb_nc');
    l.actuate(s1.id, 'press', true);
    l.run(0.3);
    l.actuate(s1.id, 'press', false);
    l.run(4);
    expect(l['K1'].s.on, isTrue, reason: 'held in through its own NO contact');
    expect(motorRunning(l, tagged(d, 'M1', 'motor3').id), isTrue);
    expect(l[h1.id].s.v, greaterThan(200));
    expect(l[h2.id].s.v, lessThan(1));
    // current animation reaches the motor feed
    final flows = l.flowPaths();
    expect(flows.isNotEmpty, isTrue);
    l.actuate(s0.id, 'press', true);
    l.run(0.3);
    l.actuate(s0.id, 'press', false);
    l.run(3);
    expect(l['K1'].s.on, isFalse);
  });

  test('contact numbering, BOM and JSON round trip', () {
    final d = dolSchematic();
    final n = d.contactNumbers();
    final nos = d.syms.where((s) => s.sym == 'no').map((s) => n[s.id]).toList();
    expect(nos, containsAll(['13-14', '23-24']));
    expect(n[d.syms.firstWhere((s) => s.sym == 'olnc').id], '95-96');
    final bom = d.bom();
    expect(bom.map((e) => e.$1), containsAll(['K1', 'Q1', 'F1', 'F2', 'S0', 'S1', 'H1', 'H2', 'M1']));
    expect(bom.where((e) => e.$1 == 'K1').length, 1);
    final e = SchemDoc.fromJsonString(d.toJsonString());
    expect(e.syms.length, d.syms.length);
    expect(e.wires.length, d.wires.length);
  });

  test('wrong wiring in the schematic: short trips the breaker, 24 V coil on 230 V burns', () {
    final d = SchemDoc();
    final l1 = SPlaced('_1', 'L1', 2, 2, 'L1'), n = SPlaced('_2', 'N', 2, 14, 'N'), f = SPlaced('_3', 'mcb1', 2, 5, 'F1');
    d.syms.addAll([l1, n, f]);
    d.wires
      ..add(SWire('_1.o', '_3.1'))
      ..add(SWire('_3.2', '_2.o'));
    final s = d.toSim();
    s.lab.setPower(true);
    expect(s.lab.short, isNotNull);
    expect(s.lab['_3'].s.trip, isTrue);

    final d2 = SchemDoc();
    d2.syms.addAll([SPlaced('_1', 'L1', 2, 2, 'L1'), SPlaced('_2', 'N', 2, 14, 'N'), SPlaced('_3', 'coil_kc', 1, 6, 'K1', p: {'coilV': 24.0})]);
    d2.wires
      ..add(SWire('_1.o', '_3.A1'))
      ..add(SWire('_3.A2', '_2.o'));
    final l = d2.toSim().lab..setPower(true);
    l.run(2);
    expect(l['K1'].s.dead, isTrue);
  });

  test('orthogonal routes', () {
    expect(schemRoute(const Offset(1, 4), false, const Offset(1, 7), true).length, 2);
    final r = schemRoute(const Offset(1, 4), false, const Offset(5, 8), true);
    expect(r.first, const Offset(1, 4));
    expect(r.last, const Offset(5, 8));
    for (var i = 0; i < r.length - 1; i++) {
      expect(r[i].dx == r[i + 1].dx || r[i].dy == r[i + 1].dy, isTrue);
    }
  });
}
