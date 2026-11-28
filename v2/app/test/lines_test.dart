import 'dart:io';

import 'package:classic_control/lab/catalog.dart';
import 'package:classic_control/lab/exercise.dart';
import 'package:classic_control/lab/machine_sprites.dart';
import 'package:classic_control/sim/plant.dart';
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
  test('l_crusher: star then delta, the flywheel turns, stops', () {
    final c = circuitById('l_crusher')!, l = wiredLine('l_crusher');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 3) press(l, 'S0');
    });
    expect(l['KM2'].s.on && l['KM3'].s.on, isFalse);
  });

  test('l_crane: each motion runs only while held and stops at its limit', () {
    final c = circuitById('l_crane')!, l = wiredLine('l_crane');
    void hold(String s, bool Function() cond) {
      l.actuate(s, 'press', true);
      expect(until(l, cond, timeout: 30), isTrue, reason: s);
      l.actuate(s, 'press', false);
      l.run(0.3);
    }

    expect(c.tasks[0].done(l), isTrue);
    // hold-to-run: letting go stops the hoist
    l.actuate('S1', 'press', true);
    l.run(0.5);
    expect(isOn(l, 'K1'), isTrue);
    l.actuate('S1', 'press', false);
    l.run(0.2);
    expect(isOn(l, 'K1'), isFalse);
    hold('S1', () => c.tasks[1].done(l));
    hold('S3', () => c.tasks[2].done(l));
    hold('S5', () => c.tasks[3].done(l));
    hold('S2', () => c.tasks[4].done(l));
    // pressing both directions: the interlock keeps one
    l.actuate('S3', 'press', true);
    l.actuate('S4', 'press', true);
    l.run(0.5);
    expect(isOn(l, 'K3') && isOn(l, 'K4'), isFalse);
    expect(l.short, isNull);
  });

  test('l_oven: heaters with the fan, thermostat cuts, fan runs on after stop', () {
    final c = circuitById('l_oven')!, l = wiredLine('l_oven');
    for (var i = 0; i < c.tasks.length; i++) {
      if (i == 1) press(l, 'S1');
      if (i == 3) press(l, 'S0', hold: 0.1);
      expect(until(l, () => c.tasks[i].done(l), timeout: 60), isTrue, reason: 'l_oven task ${i + 1}');
    }
    expect(l.plants['W1']!.count['سخونية من غير مروحة'] ?? 0, 0);
  });

  test('l_mixer: right, left, right again by the timers; lifting the guard stops it', () {
    final c = circuitById('l_mixer')!, l = wiredLine('l_mixer');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 4) l.plants['W1']!.tap(0, 0);
    });
    expect(l.short, isNull);
  });

  test('l_fill: a bottle stops the belt, fills, and moves on', () {
    final c = circuitById('l_fill')!, l = wiredLine('l_fill');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 4) press(l, 'S0');
    });
    expect(l.plants['W1']!.count['مية وقعت على السير'] ?? 0, 0);
  });

  test('l_sort: metal is pushed into the bin', () {
    final c = circuitById('l_sort')!, l = wiredLine('l_sort');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 3) press(l, 'S0');
    });
  });

  test('l_tank2: floats start and stop the duty pump; a trip hands over to the standby', () {
    final c = circuitById('l_tank2')!, l = wiredLine('l_tank2');
    for (var i = 0; i < c.tasks.length; i++) {
      if (i == 3) l.actuate('F2', 'oltest');
      expect(until(l, () => c.tasks[i].done(l), timeout: 60), isTrue, reason: 'l_tank2 task ${i + 1}');
    }
  });

  test('l_washer: wash, rinse, dry in order and the cycle ends by itself', () {
    final c = circuitById('l_washer')!, l = wiredLine('l_washer');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
    });
  });

  test('l_lift: goes to the called floor and stops there', () {
    final c = circuitById('l_lift')!, l = wiredLine('l_lift');
    for (var i = 0; i < c.tasks.length; i++) {
      if (i > 0) press(l, const ['', 'S3', 'S2', 'S1'][i]);
      expect(until(l, () => c.tasks[i].done(l), timeout: 40), isTrue, reason: 'l_lift task ${i + 1}');
    }
    // calling the floor it is on does nothing
    press(l, 'S1');
    l.run(0.5);
    expect(isOn(l, 'KA1'), isFalse);
  });

  test('l_hpress: one press of S2 runs a full stroke', () {
    final c = circuitById('l_hpress')!, l = wiredLine('l_hpress');
    checkTasks(l, c, (i) {
      if (i == 1) press(l, 'S1');
      if (i == 2) press(l, 'S2');
    });
  });

  test('l_line3: starts last belt first, stops feed belt first; E-stop cuts all', () {
    final c = circuitById('l_line3')!, l = wiredLine('l_line3');
    for (var i = 0; i < c.tasks.length; i++) {
      if (i == 1) press(l, 'S1');
      if (i == 5) press(l, 'S0', hold: 0.1);
      expect(until(l, () => c.tasks[i].done(l), timeout: 60), isTrue, reason: 'l_line3 task ${i + 1}');
    }
    expect(l.plants['W1']!.count['كراتين اتكومت'] ?? 0, 0);
    press(l, 'S1');
    until(l, () => isOn(l, 'K1'));
    l.actuate('S00', 'press', true); // a mushroom E-stop stays pushed in
    l.run(0.3);
    expect(isOn(l, 'K1') || isOn(l, 'K2') || isOn(l, 'K3'), isFalse);
    l.run(8);
    l.actuate('S00', 'press', false);
    l.run(0.5);
    expect(isOn(l, 'K1') || isOn(l, 'K2') || isOn(l, 'K3'), isFalse, reason: 'released: nothing restarts by itself');
  });
  test('the fan turns visibly: well under the frame-rate aliasing limit', () {
    final l = wiredLine('l_fan');
    press(l, 'S11');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    l.run(2);
    final f = l.plants['W1']! as FanPlant;
    final a0 = f.angle;
    l.run(1 / 30);
    final step = ((f.angle - a0) % 360);
    expect(step, greaterThan(2));
    expect(step, lessThan(15), reason: 'blades repeat every 90°: big steps look frozen');
  });

  test('local buttons on the machine press the panel button they double', () {
    const fan = [('S01', 'pb_nc', 'إيقاف جنبها'), ('S02', 'pb_nc', 'إيقاف التحكم'), ('S11', 'pb_no', 'تشغيل جنبها'), ('S12', 'pb_no', 'تشغيل التحكم')];
    expect(localButtonTarget('start', fan), 'S11');
    expect(localButtonTarget('stop', fan), 'S01');
    const belt = [('S0', 'pb_nc', 'إيقاف'), ('S1', 'pb_no', 'تشغيل')];
    expect(localButtonTarget('start', belt), 'S1');
    expect(localButtonTarget('stop', belt), 'S0');
    expect(localButtonTarget('S2', belt), isNull);
    expect(localButtonTarget('start', const []), isNull);
    for (final k in kLocalButtons.keys) {
      expect(kLabParts.containsKey('mach_$k'), isTrue, reason: k);
    }
  });
  test('turning parts are rendered at different angles (not six copies of one frame)', () {
    for (final (k, n) in const [('fan', 'blades'), ('crusher', 'fly'), ('oven', 'fan'), ('mixer', 'hook')]) {
      final frames = {for (var i = 0; i < 6; i++) File('assets/panel/mach_${k}_$n$i.webp').readAsBytesSync().join(',')};
      expect(frames.length, 6, reason: '$k $n frames are identical');
    }
  });
  test('every line machine moves on the bench when its motors and coils are on', () {
    String look(MachineLook m) => '${m.x.toStringAsFixed(3)} ${m.y.toStringAsFixed(3)} ${m.z.toStringAsFixed(3)} ${m.angle.toStringAsFixed(1)} '
        '${m.heat.toStringAsFixed(3)} ${m.ext.toStringAsFixed(3)} ${m.boxes} ${m.bottles} ${m.lamps}';
    for (final k in const ['belt', 'fan', 'crusher', 'crane', 'oven', 'mixer', 'fill', 'sort', 'tank2', 'washer', 'hpress', 'line3', 'press']) {
      final p = makeLabPlant(k)!;
      for (final coils in const [<String>{}, {'Y1', 'E1'}, {'Y2'}, {'Y3'}]) {
        final io = _AllOn(coils);
        final before = look(MachineLook.ofPlant(p, io));
        for (var i = 0; i < 40; i++) {
          p.tick(0.1, io);
        }
        final after = look(MachineLook.ofPlant(p, io));
        if (before != after) break;
        expect(coils, isNot(equals(const {'Y3'})), reason: '$k does not move');
      }
    }
  });
}

class _AllOn implements PlantIo {
  final Set<String> coils;
  _AllOn(this.coils);
  @override
  double motor(String tag) => 1;
  @override
  bool on(String tag) => coils.contains(tag);
  @override
  void sense(String tag, bool active) {}
  @override
  bool has(String tag) => true;
}
