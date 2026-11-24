import 'package:classic_control/sim/circuits.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:flutter_test/flutter_test.dart';

Lab powered(String id) {
  final l = circuitById(id)!.build();
  l.setPower(true);
  return l;
}

void press(Lab l, String id, {double hold = 0.3}) {
  l.actuate(id, 'press', true);
  l.run(hold);
  l.actuate(id, 'press', false);
}

/// run until [cond] holds (or [timeout] seconds pass); returns whether it held
bool until(Lab l, bool Function() cond, {double timeout = 20}) {
  var t = 0.0;
  while (t < timeout) {
    if (cond()) return true;
    l.run(0.1);
    t += 0.1;
  }
  return cond();
}

bool hadEvent(Lab l, String t) => l.events.any((e) => e.t == t);

void main() {
  group('every circuit', () {
    for (final c in kCircuits) {
      test('${c.id}: reference wiring is consistent and safe at power-up', () {
        final l = c.build();
        expect(l.wiringDiff(c.wires).ok, isTrue);
        for (final w in c.wires) {
          for (final t in [w.a, w.b]) {
            final comp = l.byId(t.split('.').first);
            expect(comp, isNotNull, reason: 'unknown component in $w');
            expect(comp!.terms.map((x) => x.id), contains(t.split('.').last), reason: 'unknown terminal $t');
          }
        }
        l.setPower(true);
        l.run(1);
        expect(hadEvent(l, 'short'), isFalse);
        expect(l.chatter, isFalse);
        expect(c.tasks.first.done(l), isTrue);
        for (final m in l.comps.where((x) => x.type == 'motor')) {
          expect(m.s.mode, 'off', reason: '${m.id} must not start by itself');
        }
      });
    }
  });

  test('DOL: start, stop, overload test and reset', () {
    final l = powered('c_dol');
    expect(l['H2'].s.v, greaterThan(200));
    press(l, 'S1');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    expect(l['H1'].s.v, greaterThan(200));
    expect(l['H2'].s.v, lessThan(1));
    l.run(5);
    expect(l['F2'].s.trip, isFalse, reason: 'rated current must not trip the overload');
    press(l, 'S0');
    expect(until(l, () => motorStopped(l, 'M1')), isTrue);
    press(l, 'S1');
    until(l, () => motorRunning(l, 'M1'));
    l.actuate('F2', 'oltest');
    expect(until(l, () => motorStopped(l, 'M1')), isTrue);
    expect(l['H3'].s.v, greaterThan(200));
    l.run(3);
    l.actuate('F2', 'olreset');
    expect(l['F2'].s.trip, isFalse);
    press(l, 'S1');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
  });

  test('DOL: a missing neutral keeps the coil dead; a short trips a breaker', () {
    final c = circuitById('c_dol')!;
    final l = c.build(wired: false);
    l.wires.addAll(c.wires.where((w) => !(w.a == 'K1.A2' && w.b == 'SUP.N')));
    l.setPower(true);
    press(l, 'S1');
    l.run(2);
    expect(isOn(l, 'K1'), isFalse);
    expect(l.wiringDiff(c.wires).missing.length, 1);

    final s = c.build();
    s.wires.add(const Wire('F1.2', 'SUP.N'));
    s.setPower(true);
    expect(hadEvent(s, 'short'), isTrue);
    expect(s['F1'].s.trip, isTrue);
  });

  test('two places and two starts', () {
    for (final (id, starts, stops) in [('c_2loc', ['S11', 'S12'], ['S02', 'S01']), ('c_2start', ['S1', 'S2'], ['S0', 'S0'])]) {
      final l = powered(id);
      for (var i = 0; i < 2; i++) {
        press(l, starts[i]);
        expect(until(l, () => motorRunning(l, 'M1')), isTrue, reason: '$id ${starts[i]}');
        press(l, stops[i]);
        expect(until(l, () => motorStopped(l, 'M1')), isTrue, reason: '$id ${stops[i]}');
      }
    }
  });

  test('two-hand start needs both buttons', () {
    final l = powered('c_2hand');
    press(l, 'S1');
    l.run(1);
    expect(isOn(l, 'K1'), isFalse);
    l.actuate('S1', 'press', true);
    l.actuate('S2', 'press', true);
    l.run(0.3);
    l.actuate('S1', 'press', false);
    l.actuate('S2', 'press', false);
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
  });

  test('on-delay and off-delay', () {
    final a = powered('c_ondelay');
    press(a, 'S1');
    a.run(2);
    expect(isOn(a, 'K1'), isFalse);
    expect(until(a, () => motorRunning(a, 'M1'), timeout: 6), isTrue);
    press(a, 'S0');
    expect(until(a, () => motorStopped(a, 'M1')), isTrue);

    final b = powered('c_offdelay');
    press(b, 'S1');
    expect(until(b, () => motorRunning(b, 'M1')), isTrue);
    press(b, 'S0');
    b.run(1);
    expect(isOn(b, 'KA1'), isFalse);
    expect(motorRunning(b, 'M1'), isTrue);
    expect(until(b, () => motorStopped(b, 'M1'), timeout: 12), isTrue);
  });

  test('sequence: second only after first', () {
    final l = powered('c_seq_on');
    press(l, 'S3');
    l.run(0.5);
    expect(isOn(l, 'K2'), isFalse);
    press(l, 'S1');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    press(l, 'S3');
    expect(until(l, () => motorRunning(l, 'M2')), isTrue);
    press(l, 'S0');
    expect(until(l, () => motorStopped(l, 'M1') && !isOn(l, 'K2')), isTrue);
  });

  test('sequence: second only while first is off', () {
    final l = powered('c_seq_off');
    press(l, 'S3');
    expect(until(l, () => motorRunning(l, 'M2')), isTrue);
    press(l, 'S1');
    l.run(0.5);
    expect(isOn(l, 'K1') && !isOn(l, 'K2'), isTrue);
  });

  test('timed sequences', () {
    final a = powered('c_seq_time');
    press(a, 'S1');
    expect(until(a, () => motorRunning(a, 'M2'), timeout: 10), isTrue);
    press(a, 'S0');
    expect(until(a, () => motorStopped(a, 'M1') && motorStopped(a, 'M2')), isTrue);

    final b = powered('c_seq_swap');
    press(b, 'S1');
    expect(until(b, () => motorRunning(b, 'M2') && !isOn(b, 'K1'), timeout: 12), isTrue);
    press(b, 'S0');
    expect(until(b, () => motorStopped(b, 'M2')), isTrue);

    final c = powered('c_seq3');
    press(c, 'S1');
    expect(until(c, () => motorRunning(c, 'M3'), timeout: 14), isTrue);
    expect(motorRunning(c, 'M1') && motorRunning(c, 'M2'), isTrue);
  });

  test('reversing with interlock', () {
    final l = powered('c_rev');
    press(l, 'S1');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    expect(l['M1'].s.dir, 1);
    press(l, 'S2');
    expect(isOn(l, 'K1') && !isOn(l, 'K2'), isTrue);
    press(l, 'S0');
    expect(until(l, () => motorStopped(l, 'M1')), isTrue);
    press(l, 'S2');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    expect(l['M1'].s.dir, -1);
    expect(hadEvent(l, 'short'), isFalse);
  });

  test('cart circuits with limit switches', () {
    final a = powered('c_rev_semi');
    press(a, 'S1');
    expect(until(a, () => isOn(a, 'K2'), timeout: 30), isTrue);
    expect(until(a, () => !isOn(a, 'K2') && a.track!.x < 0.1 && motorStopped(a, 'M1'), timeout: 40), isTrue);

    final b = powered('c_rev_auto');
    press(b, 'S1');
    expect(until(b, () => isOn(b, 'K2'), timeout: 30), isTrue);
    expect(until(b, () => isOn(b, 'K1') && b.track!.x < 0.3, timeout: 40), isTrue);
    press(b, 'S0');
    expect(until(b, () => motorStopped(b, 'M1')), isTrue);

    final c = powered('c_rev_timer');
    press(c, 'S1');
    expect(until(c, () => c['KT1'].s.on && !isOn(c, 'K1'), timeout: 30), isTrue);
    expect(until(c, () => isOn(c, 'K2'), timeout: 8), isTrue);
    for (final l in [a, b, c]) {
      expect(hadEvent(l, 'short'), isFalse);
    }
  });

  test('star-delta, one and two directions', () {
    final a = powered('c_sd');
    press(a, 'S1');
    expect(until(a, () => a['M1'].s.mode == 'star'), isTrue);
    expect(isOn(a, 'KM2') && !isOn(a, 'KM3'), isTrue);
    expect(until(a, () => a['M1'].s.mode == 'delta' && a['M1'].s.spd > 0.5, timeout: 10), isTrue);
    expect(isOn(a, 'KM3') && !isOn(a, 'KM2'), isTrue);
    expect(hadEvent(a, 'short'), isFalse);
    expect(a['F2'].s.trip, isFalse);

    final b = powered('c_sd2');
    press(b, 'S1');
    expect(until(b, () => b['M1'].s.mode == 'star' && b['M1'].s.dir == 1), isTrue);
    expect(until(b, () => b['M1'].s.mode == 'delta' && b['M1'].s.dir == 1, timeout: 10), isTrue);
    press(b, 'S0');
    expect(until(b, () => motorStopped(b, 'M1')), isTrue);
    press(b, 'S2');
    expect(until(b, () => b['M1'].s.mode == 'delta' && b['M1'].s.dir == -1, timeout: 10), isTrue);
    expect(hadEvent(b, 'short'), isFalse);
  });
}
