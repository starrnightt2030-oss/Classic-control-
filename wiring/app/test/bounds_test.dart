import 'package:flutter_test/flutter_test.dart';
import 'package:wiring_academy/data/circuits.dart';

void main() {
  test('parts fit on the 1000x620 board', () {
    for (final c in circuits) {
      for (final p in c.parts()) {
        final r = p.pos & p.type.size;
        expect(r.right <= 1000 && r.bottom <= 620 && r.left >= 0 && r.top >= 0, isTrue, reason: '${c.id} ${p.id} $r');
      }
    }
  });
}
