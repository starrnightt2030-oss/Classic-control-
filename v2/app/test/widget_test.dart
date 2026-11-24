import 'package:classic_control/data/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every catalog component appears once', () {
    final ids = [for (final c in categories) ...c.components];
    expect(ids.toSet().length, ids.length);
    expect(ids.length, 32);
  });

  test('variant labels', () {
    expect(variantLabel('mcb_3p.glb'), '3P');
    expect(variantLabel('unknown.glb'), 'unknown');
  });
}
