import 'package:classic_control/lab/faults.dart';
import 'package:classic_control/lab/model.dart';
import 'package:classic_control/lab/templates.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void press(Lab l, String id, {double hold = 0.3}) {
  l.actuate(id, 'press', true);
  l.run(hold);
  l.actuate(id, 'press', false);
}

bool until(Lab l, bool Function() cond, {double timeout = 15}) {
  var t = 0.0;
  while (t < timeout) {
    if (cond()) return true;
    l.run(0.1);
    t += 0.1;
  }
  return cond();
}

Lab dol() => dolTemplate().toLab()..setPower(true);

void main() {
  test('DOL panel template: start, lamps, stop', () {
    final l = dol();
    expect(l.events.any((e) => e.t == 'short'), isFalse);
    expect(l['H2'].s.v, greaterThan(200), reason: 'stop lamp through the aux NC 61-62');
    expect(l['H1'].s.v, lessThan(1));
    press(l, 'S1');
    expect(until(l, () => motorRunning(l, 'M1')), isTrue);
    expect(l['H1'].s.v, greaterThan(200));
    expect(l['H2'].s.v, lessThan(1));
    l.run(5);
    expect(l['F2'].s.trip, isFalse);
    press(l, 'S0');
    expect(until(l, () => motorStopped(l, 'M1')), isTrue);
    press(l, 'S1');
    until(l, () => motorRunning(l, 'M1'));
    l.actuate('S00', 'estop');
    expect(until(l, () => motorStopped(l, 'M1')), isTrue);
  });

  test('document JSON round trip keeps parts, attachments and wires', () {
    final d = dolTemplate();
    final e = LabDoc.fromJsonString(d.toJsonString());
    expect(e.parts.length, d.parts.length);
    expect(e.wires.length, d.wires.length);
    expect(e.byId('F2')!.attach, 'K1');
    expect(e.netNumbers().isNotEmpty, isTrue);
  });

  test('injected faults change the behaviour', () {
    // coil open: contactor never pulls in
    var l = dolTemplate().toLab();
    FaultSession('coil_open', partId: 'K1').applyTo(l);
    l.setPower(true);
    press(l, 'S1');
    l.run(2);
    expect(isOn(l, 'K1'), isFalse);

    // welded contacts: motor keeps running after stop
    l = dolTemplate().toLab();
    FaultSession('weld', partId: 'K1').applyTo(l);
    l.setPower(true);
    l.run(3);
    expect(motorRunning(l, 'M1'), isTrue);

    // phase loss at the source: single phasing
    l = dolTemplate().toLab();
    FaultSession('phase_loss', partId: 'X0').applyTo(l);
    l.setPower(true);
    press(l, 'S1');
    l.run(1);
    expect(l['M1'].s.mode, 'single');

    // broken control wire K1.14 → A1: no start
    final d = dolTemplate();
    final i = d.wires.indexWhere((w) => w.a == 'K1.14' && w.b == 'K1.A1');
    l = d.toLab();
    FaultSession('wire', wireIndex: i, wireKey: 'K1.14|K1.A1').applyTo(l);
    l.setPower(true);
    press(l, 'S1');
    l.run(1);
    expect(isOn(l, 'K1'), isFalse);

    // overload set far below the motor current: trips while running
    l = dolTemplate().toLab();
    FaultSession('ol_set', partId: 'F2').applyTo(l);
    l.setPower(true);
    press(l, 'S1');
    expect(until(l, () => l['F2'].s.trip, timeout: 40), isTrue);
  });

  test('fault generator picks something present on the panel', () {
    for (var i = 0; i < 30; i++) {
      final f = FaultSession.create(dolTemplate());
      expect(f, isNotNull);
      final l = dolTemplate().toLab();
      f!.applyTo(l);
      l.setPower(true);
      l.run(0.5);
    }
  });

  test('lab devices: 24 V supply, star-delta timer, MPCB, phase relay', () {
    final l = Lab();
    l.comps.addAll([
      Comp('X0', 'sup'),
      Comp('G1', 'psu'),
      Comp('K1', 'kc', p: {'coilV': 24.0}),
      Comp('KF', 'phr'),
      Comp('KT', 'tsd', p: {'T': 2.0}),
      Comp('Q1', 'mpcb', p: {'set': 2.0}),
      Comp('M1', 'motor'),
    ]);
    l.wires.addAll([
      const Wire('X0.L1', 'G1.L'), const Wire('X0.N', 'G1.N'),
      const Wire('G1.P', 'K1.A1'), const Wire('G1.M', 'K1.A2'),
      const Wire('X0.L1', 'KF.L1'), const Wire('X0.L2', 'KF.L2'), const Wire('X0.L3', 'KF.L3'),
      const Wire('X0.L1', 'KT.A1'), const Wire('X0.N', 'KT.A2'),
      const Wire('X0.L1', 'Q1.1'), const Wire('X0.L2', 'Q1.3'), const Wire('X0.L3', 'Q1.5'),
      const Wire('Q1.2', 'M1.U1'), const Wire('Q1.4', 'M1.V1'), const Wire('Q1.6', 'M1.W1'),
    ]);
    l.solve();
    l.setPower(true);
    expect(isOn(l, 'K1'), isTrue, reason: '24 V coil fed from the power supply');
    expect(l['KF'].s.on, isTrue, reason: 'all three phases in the right order');
    final nets = l.nets!;
    expect(nets.same('KT.17', 'KT.18'), isTrue, reason: 'star output first');
    l.run(2.2);
    expect(l.nets!.same('KT.17', 'KT.28'), isTrue, reason: 'then delta after the pause');
    expect(until(l, () => l['Q1'].s.trip, timeout: 40), isTrue, reason: 'MPCB set at 2 A trips a 8.5 A motor');
    expect(isOn(l, 'Q1'), isFalse);
  });

  test('current paths follow the energised loads', () {
    final d = dolTemplate();
    final l = d.toLab()..setPower(true);
    // stopped: only the stop lamp H2 draws current
    var f = l.flowPaths();
    int idx(String a, String b) => d.wires.indexWhere((w) => (w.a == a && w.b == b) || (w.a == b && w.b == a));
    expect(f.containsKey(idx('K1A.62', 'H2.X1')), isTrue);
    expect(f.containsKey(idx('X0.L1', 'Q1.1')), isTrue);
    expect(f.containsKey(idx('F2.2', 'M1.U1')), isFalse, reason: 'motor not running yet');
    // line side flows towards the lamp, neutral side back to the supply
    expect(f[idx('K1A.62', 'H2.X1')], 1);
    expect(f[idx('X0.N', 'K1.A2')], -1);
    press(l, 'S1');
    until(l, () => motorRunning(l, 'M1'));
    f = l.flowPaths();
    expect(f[idx('F2.2', 'M1.U1')], 1, reason: 'motor feed carries current to the motor');
    expect(f.containsKey(idx('K1A.62', 'H2.X1')), isFalse);
    expect(f.containsKey(idx('K1.14', 'K1.A1')), isTrue, reason: 'hold-in path through 13-14');
  });

  test('a short records its net and trips the breaker; overvoltage burns a lamp', () {
    final s = shortDemo().toLab()..setPower(true);
    expect(s.short, isNotNull);
    expect(s.short!.breaker, 'Q1');
    expect(s.short!.terms, containsAll(['Q1.2', 'Q1.4']));
    expect(s['Q1'].s.trip, isTrue);

    final b = burnDemo().toLab()..setPower(true);
    expect(b['H1'].s.dead, isTrue);
    expect(b.drain().any((e) => e.t == 'pop' && e.id == 'H1'), isTrue);
    // a burnt part stays dead in the next run until replaced
    final d = burnDemo();
    d.byId('H1')!.p['burnt'] = true;
    final again = d.toLab()..setPower(true);
    expect(again['H1'].s.v, 0);
    expect(again.drain().any((e) => e.t == 'pop'), isFalse);
  });

  test('empty worksheet has only rails', () {
    final d = emptyPanel();
    expect(d.parts.every((p) => p.def == 'din_rail'), isTrue);
    expect(d.wires, isEmpty);
  });

  test('machines follow their motor and switch at the ends', () {
    final l = benchDemo().toLab()..setPower(true);
    expect(l['M1'].s.mode, 'delta');
    l.run(8);
    final w = l['W1'];
    expect(w.s.mx == 1.0 || w.s.mx == 0.0, isTrue, reason: 'cart reached an end');
    expect(w.s.ms.take(2).where((x) => x).length, 1);
    expect(l['H1'].s.v, greaterThan(200));
  });

  test('six-terminal motor wired by hand: star and delta bridges', () {
    LabDoc mk(List<(String, String)> bridges) {
      final d = emptyPanel();
      d.parts.add(Placed('X0', 'supply', 40, 60));
      d.parts.add(Placed('M1', 'motor', 470, 20));
      d.wires
        ..add(LabWire('X0.L1', 'M1.U1', 'br'))
        ..add(LabWire('X0.L2', 'M1.V1', 'bk'))
        ..add(LabWire('X0.L3', 'M1.W1', 'gy'));
      for (final (a, b) in bridges) {
        d.wires.add(LabWire('M1.$a', 'M1.$b', 'rd'));
      }
      return d;
    }

    final none = mk([]).toLab()..setPower(true);
    expect(none['M1'].s.mode, 'off');
    final star = mk([('U2', 'V2'), ('V2', 'W2')]).toLab()..setPower(true);
    expect(star['M1'].s.mode, 'star');
    final delta = mk([('U1', 'W2'), ('V1', 'U2'), ('W1', 'V2')]).toLab()..setPower(true);
    expect(delta['M1'].s.mode, 'delta');
  });

  test('single-phase motor needs its capacitor winding; swapping Z1/Z2 reverses', () {
    Lab mk(bool aux, bool swap) {
      final d = emptyPanel();
      d.parts.add(Placed('X0', 'supply', 40, 60));
      d.parts.add(Placed('M1', 'motor1', 470, 20));
      d.wires
        ..add(LabWire('X0.L1', 'M1.U1', 'br'))
        ..add(LabWire('X0.N', 'M1.U2', 'bu'));
      if (aux) {
        d.wires
          ..add(LabWire(swap ? 'M1.U2' : 'M1.U1', 'M1.Z1', 'rd'))
          ..add(LabWire(swap ? 'M1.U1' : 'M1.U2', 'M1.Z2', 'rd'));
      }
      return d.toLab()..setPower(true);
    }

    expect(mk(false, false)['M1'].s.mode, 'single');
    final f = mk(true, false), r = mk(true, true);
    expect(f['M1'].s.mode, 'run');
    expect(f['M1'].s.dir, -r['M1'].s.dir);
  });
}
