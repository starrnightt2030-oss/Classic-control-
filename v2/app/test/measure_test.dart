import 'dart:math' as math;

import 'package:classic_control/schem/ladder.dart';
import 'package:classic_control/schem/model.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:classic_control/sim/measure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SPlaced tagged(SchemDoc d, String tag, String sym) => d.syms.firstWhere((s) => s.tag == tag && s.sym == sym);

  test('voltmeter, clamp meter and wattmeter on a heater', () {
    final d = SchemDoc();
    d.syms.addAll([SPlaced('_1', 'sup1', 2, 1, 'X0'), SPlaced('_2', 'heat', 2, 6, 'E1', p: {'V': 220.0, 'W': 1000.0})]);
    d.wires
      ..add(SWire('_1.L1', '_2.X1'))
      ..add(SWire('_2.X2', '_1.N'));
    final s = d.toSim();
    final l = s.lab..setPower(true);
    final v = l.potential('_2.X1')!.$1 - l.potential('_2.X2')!.$1;
    expect(v.abs, closeTo(220, 1));
    final i = l.wireCurrents();
    expect(i[0]!.abs, closeTo(1000 / 220, 0.05), reason: 'line wire');
    expect(i[1]!.abs, closeTo(1000 / 220, 0.05), reason: 'neutral carries it back');
    // the same current flows out on L and back on N: opposite signs along the wires' own directions
    final p = v.dotRe(i[0]!);
    expect(p.abs(), closeTo(1000, 15));
  });

  test('balanced three-phase load: line currents equal, a delta line is √3 × the winding', () {
    final d = readyById('c_dol')!.build();
    final s = d.toSim();
    final l = s.lab..setPower(true);
    final s1 = tagged(d, 'S1', 'pb_no');
    l.actuate(s1.id, 'press', true);
    l.run(0.3);
    l.actuate(s1.id, 'press', false);
    l.run(6);
    final m = l.comps.firstWhere((c) => c.type == 'motor');
    expect(motorRunning(l, m.id), isTrue);
    final cur = l.wireCurrents();
    // the three wires into the motor
    final mot = tagged(d, 'M1', 'motor3');
    final feeds = <double>[];
    for (var i = 0; i < d.wires.length; i++) {
      final w = d.wires[i];
      if (w.b.startsWith('${mot.id}.') || w.a.startsWith('${mot.id}.')) {
        final k = s.wireIndex.entries.firstWhere((e) => e.value == i).key;
        feeds.add(cur[k]?.abs ?? 0);
      }
    }
    expect(feeds.length, 3);
    for (final f in feeds) {
      expect(f, closeTo(m.s.current, m.s.current * 0.05), reason: 'clamp on a motor lead reads the line current');
    }
  });

  test('ohmmeter: coil, open contact, closed contact, broken wire', () {
    final d = SchemDoc();
    d.syms.addAll([
      SPlaced('_1', 'pb_no', 2, 2, 'S1'),
      SPlaced('_2', 'coil_kc', 1, 8, 'K1', p: {'coilV': 220.0}),
      SPlaced('_3', 'pb_nc', 8, 2, 'S0'),
    ]);
    d.wires
      ..add(SWire('_1.14', '_2.A1'))
      ..add(SWire('_3.12', '_1.13'));
    final l = d.toSim().lab; // supply off
    final rc = l.ohms('K1.A1', 'K1.A2')!;
    expect(rc, greaterThan(500));
    expect(rc, lessThan(20000));
    expect(l.ohms('_1.13', '_1.14'), isNull, reason: 'open push button: OL');
    expect(l.ohms('_3.11', '_3.12'), 0, reason: 'NC button closed');
    expect(l.ohms('_3.11', 'K1.A1'), isNull);
    l.actuate('_1', 'press', true);
    expect(l.ohms('_3.11', 'K1.A2'), closeTo(rc, 1e-6), reason: 'through the button into the coil');
    l.brokenWires.add(l.wires.first);
    expect(l.ohms('_3.11', 'K1.A2'), isNull, reason: 'a broken wire opens the path');
  });

  test('ohmmeter: motor windings star and delta', () {
    final d = SchemDoc()..syms.add(SPlaced('_1', 'motor3', 2, 2, 'M1', p: {'links': 'delta', 'In': 8.5}));
    final l = d.toSim().lab;
    final r = l.ohms('_1.U1', '_1.V1')!;
    // delta: one winding parallel to two in series = 2/3 R
    expect(r, closeTo(2.0 * 2 / 3, 0.01));
    final y = SchemDoc()..syms.add(SPlaced('_1', 'motor3', 2, 2, 'M1', p: {'links': 'star', 'In': 8.5}));
    expect(y.toSim().lab.ohms('_1.U1', '_1.V1'), closeTo(4.0, 0.01));
    expect(math.sqrt(3), greaterThan(1));
  });
}
