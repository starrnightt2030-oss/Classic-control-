import 'package:flutter_test/flutter_test.dart';
import 'package:wiring_academy/data/circuits.dart';
import 'package:wiring_academy/sim/diagnose.dart';
import 'package:wiring_academy/ui/lab/wires.dart';

void main() {
  test('parts fit on the 1000x620 board', () {
    for (final c in allCircuits) {
      for (final p in c.parts()) {
        final r = p.rect;
        expect(r.right <= 1000 && r.bottom <= 620 && r.left >= 0 && r.top >= 0, isTrue, reason: '${c.id} ${p.id} $r');
      }
    }
  });

  test('parts do not overlap (room for wires between them)', () {
    final bad = <String>[];
    for (final c in allCircuits) {
      final ps = c.parts();
      for (var i = 0; i < ps.length; i++) {
        for (var j = i + 1; j < ps.length; j++) {
          if (ps[i].rect.inflate(4).overlaps(ps[j].rect.inflate(4))) bad.add('${c.id} ${ps[i].id}/${ps[j].id}');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('reference wiring passes the live wiring check', () {
    final bad = <String>[];
    for (final c in allCircuits) {
      final s = c.buildDone();
      for (final i in diagnose(s)) {
        bad.add('${c.id}: ${i.title}');
      }
    }
    expect(bad, isEmpty);
  });

  test('tidy routes every reference wire', () {
    for (final c in allCircuits) {
      final s = c.buildDone();
      final n = tidyWires(s);
      expect(n, s.wires.length, reason: c.id);
    }
  });
}
