import 'package:classic_control/lab/catalog.dart';
import 'package:classic_control/lab/exercise.dart';
import 'package:classic_control/lab/model.dart';
import 'package:classic_control/lines/lines.dart';
import 'package:classic_control/schem/ladder.dart';
import 'package:classic_control/sim/circuits.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void press(Lab l, String id, {double hold = 0.3}) {
  l.actuate(id, 'press', true);
  l.run(hold);
  l.actuate(id, 'press', false);
}

bool until(Lab l, bool Function() cond, {double timeout = 30}) {
  var t = 0.0;
  while (t < timeout) {
    if (cond()) return true;
    l.run(0.1);
    t += 0.1;
  }
  return cond();
}

/// the line's exercise wired with its reference solution, powered
Lab wiredLine(String id) {
  final e = buildExercise(circuitById(id)!);
  for (final w in e.reference) {
    e.doc.wires.add(LabWire(w.a, w.b, 'rd'));
  }
  return e.doc.toLab()..setPower(true);
}

/// run the circuit's tasks in order, driving it with [drive] between checks
void checkTasks(Lab l, Circuit c, void Function(int i) drive) {
  for (var i = 0; i < c.tasks.length; i++) {
    drive(i);
    expect(until(l, () => c.tasks[i].done(l)), isTrue, reason: '${c.id} task ${i + 1}: ${c.tasks[i].text}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Sprites.load);

  test('15 lines, numbered in order, levels 1–4; every ready line has its circuit and sheet', () {
    expect(kLines.length, 15);
    for (var i = 0; i < kLines.length; i++) {
      expect(kLines[i].n, i + 1);
      expect(kLineLevels.containsKey(kLines[i].level), isTrue);
    }
    for (final l in kLines.where((l) => l.ready)) {
      expect(circuitById(l.circuit!), isNotNull, reason: l.circuit);
      expect(readyById(l.circuit!), isNotNull, reason: l.circuit);
      expect(kLabParts.containsKey(l.machine), isTrue, reason: l.machine);
    }
    expect(kLines.where((l) => l.ready).length, kLineCircuits.length);
  });

  group('line exercises', () {
    for (final c in kLineCircuits) {
      test('${c.id}: devices and machine mounted, reference wiring is clean', () {
        final e = buildExercise(c);
        expect(e.doc.parts.any((p) => p.d.machine != null), isTrue, reason: 'machine on the bench');
        final terms = e.doc.toLab().allTerms();
        for (final w in e.reference) {
          expect(terms.contains(w.a), isTrue, reason: '${c.id}: ${w.a}');
          expect(terms.contains(w.b), isTrue, reason: '${c.id}: ${w.b}');
        }
        final l = wiredLine(c.id);
        expect(l.wiringDiff(e.reference).ok, isTrue);
        l.run(1);
        expect(l.short, isNull);
        expect(l.events.any((x) => x.t == 'burn' || x.t == 'pop'), isFalse);
        for (final m in l.comps.where((x) => x.type == 'motor')) {
          expect(m.s.mode, 'off', reason: '${m.id} must not start by itself');
        }
      });
    }
  });

  test('l_belt: runs, boxes reach the photo eye, overload test and reset', () {
    final c = circuitById('l_belt')!, l = wiredLine('l_belt');
    checkTasks(l, c, (i) {
      if (i == 1 || i == 5) press(l, 'S1');
      if (i == 3) press(l, 'S0');
      if (i == 4) l.actuate('F2', 'oltest');
      if (i == 5) {
        l.run(1);
        l.actuate('F2', 'olreset');
        press(l, 'S1');
      }
    });
    expect(l['H1'].s.v, greaterThan(200));
    expect(l.plants['W1']!.count['كراتين اتنقلت'] ?? 0, greaterThanOrEqualTo(0));
  });

  test('l_fan: start and stop from either place; the blades turn', () {
    final c = circuitById('l_fan')!, l = wiredLine('l_fan');
    checkTasks(l, c, (i) {
      if (i > 0) press(l, const ['', 'S11', 'S02', 'S12', 'S01'][i]);
    });
    press(l, 'S11');
    until(l, () => motorRunning(l, 'M1'));
    expect(l['H1'].s.v, greaterThan(200));
    expect(l['H2'].s.v, greaterThan(200));
  });

  test('l_press2h: one hand does nothing, two hands press a part, letting go lifts the ram', () {
    final c = circuitById('l_press2h')!, l = wiredLine('l_press2h');
    l.run(0.5); // the photo eye sees the part
    expect(c.tasks[0].done(l), isTrue);
    l.actuate('S1', 'press', true);
    l.run(0.5);
    expect(c.tasks[1].done(l), isTrue);
    l.actuate('S2', 'press', true);
    expect(until(l, () => c.tasks[2].done(l)), isTrue);
    expect(until(l, () => c.tasks[3].done(l)), isTrue);
    l.actuate('S2', 'press', false);
    l.run(0.3);
    expect(l['W1'].s.v, lessThan(1), reason: 'one hand off: the valve drops');
    l.actuate('S1', 'press', false);
  });

  test('l_gate: opens to LS2 and stops, closes to LS1 and stops; never both contactors', () {
    final c = circuitById('l_gate')!, l = wiredLine('l_gate');
    expect(l['W1'].s.ms[0], isTrue, reason: 'starts closed on LS1');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 3) press(l, 'S2');
    });
    press(l, 'S1');
    l.run(1);
    press(l, 'S2'); // close while opening: the interlock blocks it
    l.run(0.2);
    expect(l['K1'].s.on && l['K2'].s.on, isFalse);
    expect(l.short, isNull);
  });
}
