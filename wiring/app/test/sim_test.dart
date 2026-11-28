import 'package:flutter_test/flutter_test.dart';
import 'package:wiring_academy/data/circuits.dart';
import 'package:wiring_academy/sim/model.dart';
import 'package:wiring_academy/sim/solver.dart';

void main() {
  test('circuit ids are unique', () {
    expect(circuits.map((c) => c.id).toSet().length, circuits.length);
  });

  for (final c in allCircuits) {
    group('${c.id} ${c.title}', () {
      test('reference wiring passes every scenario with no warnings', () {
        final rep = checkCircuit(c, c.buildDone());
        expect(rep.failed, isEmpty, reason: rep.failed.join('\n'));
        expect(rep.warnings, isEmpty, reason: rep.warnings.join('\n'));
      });
      test('empty board fails', () {
        expect(checkCircuit(c, c.buildEmpty()).ok, isFalse);
      });
      test('terminals in steps exist', () {
        final s = c.buildDone();
        for (final w in s.wires) {
          for (final t in [w.a, w.b]) {
            final parts = t.split('.');
            final p = s.part(parts[0]);
            expect(p, isNotNull, reason: t);
            expect(p!.type.terms.any((x) => x.id == parts[1]), isTrue, reason: t);
          }
        }
      });
      for (final f in c.faults) {
        test('fault ${f.kind.name} ${f.target} is detectable', () {
          final s = c.buildDone()..faults.add(f);
          final rep = checkCircuit(c, s, keepFaults: true);
          if (rep.ok && f.kind == FaultKind.leakToEarth) {
            // no RCD: found with the insulation test L-PE
            final r = resistance(s, f.target, 'G1.PE');
            expect(r, isNotNull);
          } else {
            expect(rep.ok, isFalse, reason: 'fault had no effect');
          }
        });
      }
    });
  }

  test('series lamps glow dim', () {
    final s = Sim(parts: [
      Part('G', Kind.supply, Offset.zero),
      Part('A', Kind.lamp, Offset.zero, watts: 60),
      Part('B', Kind.lamp, Offset.zero, watts: 60),
    ], wires: [Wire('G.L', 'A.L', WireColor.brown), Wire('A.N', 'B.L', WireColor.brown), Wire('B.N', 'G.N', WireColor.blue)], power: true);
    final r = simulate(s);
    expect(r.lamp['A']!, closeTo(0.25, 0.01));
  });

  test('short trips the breaker', () {
    final s = Sim(parts: [
      Part('G', Kind.supply, Offset.zero),
      Part('Q', Kind.mcb, Offset.zero),
    ], wires: [Wire('G.L', 'Q.in', WireColor.brown), Wire('Q.out', 'G.N', WireColor.blue)], power: true);
    final r = simulate(s);
    expect(r.event, SimEvent.shortCircuit);
    expect(s.tripped, contains('Q'));
  });

  test('ohmmeter reads a 100W lamp', () {
    final s = Sim(parts: [Part('A', Kind.lamp, Offset.zero, watts: 100)]);
    expect(resistance(s, 'A.L', 'A.N'), closeTo(484, 1));
  });
}
