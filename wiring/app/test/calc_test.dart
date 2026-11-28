import 'package:flutter_test/flutter_test.dart';
import 'package:wiring_academy/ui/calc_page.dart';

void main() {
  test('load calc picks circuits, main breaker and feeder by the rules', () {
    final items = [
      LoadItem('led', 12, LoadCat.light, 20),
      LoadItem('socket', 200, LoadCat.socket, 10),
      LoadItem('heater', 3000, LoadCat.fixed, 1),
      LoadItem('ac', 1500, LoadCat.ac, 2, motor: true),
    ];
    final r = computeLoad(items, cosPhi: .9, feederLen: 15);
    expect(r.installed, 240 + 2000 + 3000 + 3000);
    expect(r.demand, closeTo(240 * .9 + 2000 * .5 + 3000 * .75 + 3000, 1e-6));
    expect(r.ib, closeTo(r.demand / (220 * .9), 1e-6));
    expect(r.mainBreaker >= r.ib * 1.25, isTrue);
    // one lighting, one socket, heater, two ACs
    expect(r.circuits.length, 5);
    for (final c in r.circuits) {
      expect(c.inA >= c.ib, isTrue, reason: c.name);
      expect(cableFor(c.inA.toDouble()) <= c.cable, isTrue);
    }
    expect(r.feederDrop <= 1, isTrue);
    expect(r.rccb >= r.mainBreaker, isTrue);
  });

  test('breaker and cable tables', () {
    expect(breakerFor(13.6), 16);
    expect(cableFor(16), 1.5);
    expect(cableFor(20), 2.5);
    expect(cableFor(32), 6);
  });
}
