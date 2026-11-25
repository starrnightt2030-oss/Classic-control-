// The machines of the schematic exercises (sorting belt, press, filling line) wired
// in the panel lab: their sensors are switches on the machine, their valve a coil.
import 'package:classic_control/lab/catalog.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:classic_control/sim/plant.dart';
import 'package:flutter_test/flutter_test.dart';

Lab lab(String kind, List<Wire> wires, {bool motor = false}) {
  final l = Lab();
  l.comps.add(Comp('X1', 'sup'));
  if (motor) l.comps.add(Comp('M1', 'motor', p: {'links': 'delta'}));
  l.comps.add(Comp('W1', 'mach', p: {'kind': kind, if (motor) 'motor': 'M1'}));
  l.wires.addAll(wires);
  l.solve();
  l.setPower(true);
  return l;
}

void main() {
  test('every lab machine has its switches and valve terminals laid out', () {
    for (final k in ['sort', 'press', 'fill']) {
      final t = MachineGeo.terms(k);
      expect(t.length, machSwitches(k) * 4 + 2, reason: k);
      expect(t.containsKey('A1') && t.containsKey('A2'), isTrue);
      final c = Comp('W1', 'mach', p: {'kind': k});
      expect({for (final x in c.terms) x.id}, t.keys.toSet(), reason: 'engine and plate agree for $k');
    }
    expect(kLabParts['mach_sort']!.machine, 'sort');
  });

  test('press: the part sensor B3 drives the valve, the ram strokes and comes back', () {
    // L1 → B3 NO (S33-S34) → coil A1-A2 → N: a part in the die makes one stroke
    final l = lab('press', const [Wire('X1.L1', 'W1.S33'), Wire('W1.S34', 'W1.A1'), Wire('W1.A2', 'X1.N')]);
    l.run(0.2);
    final w = l['W1'];
    expect(w.s.ms[2], isTrue, reason: 'B3 sees the part');
    expect(w.s.v, greaterThan(200), reason: 'the valve coil is energised through B3');
    final pl = l.plants['W1']! as PressPlant;
    l.run(1.5);
    expect(pl.count['قطع اتكبست'], 1);
    l.run(1.0);
    expect(w.s.v, lessThan(1), reason: 'pressed part: B3 opens, the spring lifts the ram');
    expect(w.s.ms[0], isTrue, reason: 'B1 ram up');
  });

  test('filling line: the belt runs, a bottle stops under the nozzle and fills', () {
    // motor straight on line; valve through B1 (bottle under the nozzle, NO S13-S14)
    // and B2's NC (S21-S22: not full yet)
    final l = lab('fill', const [
      Wire('X1.L1', 'M1.U1'),
      Wire('X1.L2', 'M1.V1'),
      Wire('X1.L3', 'M1.W1'),
      Wire('X1.L1', 'W1.S13'),
      Wire('W1.S14', 'W1.S21'),
      Wire('W1.S22', 'W1.A1'),
      Wire('W1.A2', 'X1.N'),
    ], motor: true);
    final pl = () => l.plants['W1']! as FillPlant;
    var t = 0.0, filled = false;
    while (t < 30 && !filled) {
      l.run(0.1);
      t += 0.1;
      filled = pl().bottles.any((b) => b.fill > 0.1);
    }
    expect(l['M1'].s.mode, 'delta');
    expect(filled, isTrue, reason: 'the valve opened over a bottle');
    expect(l.flowPaths().values.isNotEmpty, isTrue);
  });

  test('a sorting belt that is not wired stays still and its sensors stay off', () {
    final l = lab('sort', const []);
    l.run(3);
    final pl = l.plants['W1']! as SortPlant;
    expect(pl.boxes, isEmpty);
    expect(l['W1'].s.ms.take(2), [false, false]);
    expect(l['W1'].s.ms[2], isTrue, reason: 'B3: the pusher is retracted');
  });

  test('flow paths are reused until the circuit changes', () {
    final l = lab('press', const [Wire('X1.L1', 'W1.S33'), Wire('W1.S34', 'W1.A1'), Wire('W1.A2', 'X1.N')]);
    l.run(0.1);
    final a = l.flowPaths();
    expect(identical(a, l.flowPaths()), isTrue);
    l.actuate('X1', 'noop');
    expect(identical(a, l.flowPaths()), isFalse, reason: 'solved again');
  });
}
