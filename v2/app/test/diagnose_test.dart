import 'dart:math' as math;

import 'package:classic_control/schem/diagnose.dart';
import 'package:classic_control/schem/ladder.dart';
import 'package:classic_control/schem/model.dart';
import 'package:classic_control/sim/measure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DOL: faults are picked, change the behaviour, and are found by pointing at them', () {
    final d = readyById('c_dol')!.build();
    expect(readyForFaults(d), isNull);
    final sw = Stopwatch()..start();
    final fs = pickFaults(d, 3, rnd: math.Random(7));
    expect(fs.length, 3);
    expect(sw.elapsedMilliseconds, lessThan(20000));
    final healthy = behaviour(d.toSim());
    expect(behaviour(buildFaulted(d, fs)), isNot(healthy));
    for (final f in fs) {
      if (f.kind == 'wire') {
        expect(f.hit(d, wire: f.wireIndex(d)), isTrue);
      } else if (f.kind != 'phase_loss') {
        expect(f.hit(d, s: d.byId(f.sym!)), isTrue);
      }
      expect(f.where(d), isNotEmpty);
    }
    // fixing all brings the healthy circuit back
    for (final f in fs) {
      f.fixed = true;
    }
    expect(behaviour(buildFaulted(d, fs)), healthy);
  });

  test('every candidate kind applies to the engine', () {
    final d = readyById('c_dol')!.build();
    final kinds = faultCandidates(d).map((f) => f.kind).toSet();
    expect(kinds, containsAll(['wire', 'coil_open', 'stuck_open', 'stuck_closed', 'no_close', 'nc_open', 'lamp_dead', 'open_pole', 'phase_loss', 'ol_set']));
    final healthy = behaviour(d.toSim());
    for (final k in kinds.where((k) => k != 'ol_set' && k != 'wire')) {
      final shows = faultCandidates(d).where((f) => f.kind == k).any((f) => behaviour(buildFaulted(d, [f])) != healthy);
      expect(shows, isTrue, reason: k);
    }
  });

  test('a broken wire reads OL on the ohmmeter, the coil reads open', () {
    final d = readyById('c_dol')!.build();
    final coil = d.syms.firstWhere((s) => s.sym == 'coil_kc');
    final f = SFault('coil_open', sym: coil.id);
    final s = buildFaulted(d, [f]);
    expect(s.lab.ohms('${coil.tag}.A1', '${coil.tag}.A2'), isNull);
    expect(d.toSim().lab.ohms('${coil.tag}.A1', '${coil.tag}.A2'), isNotNull);
  });

  test('an unfinished drawing is refused', () {
    expect(readyForFaults(SchemDoc()), isNotNull);
  });

  test('score', () {
    expect(faultScore(faults: 2, wrong: 0, hints: 0, seconds: 100, gaveUp: false), (100, 3));
    expect(faultScore(faults: 2, wrong: 3, hints: 1, seconds: 100, gaveUp: false).$2, 2);
    expect(faultScore(faults: 1, wrong: 0, hints: 0, seconds: 10, gaveUp: true).$1, 30);
  });
}
