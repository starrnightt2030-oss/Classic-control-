// The running simulation screens: they draw without errors while the circuit and a
// machine run, and the screen is redrawn at Perf.simFps, not every frame.
import 'package:classic_control/schem/schem_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('schematic with a machine runs for a few seconds without errors', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(1600, 900));
    await t.pumpWidget(const MaterialApp(home: SchemPage(demo: 1, plant: 'sort')));
    for (var i = 0; i < 180; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(t.takeException(), isNull);
    expect(find.byType(SchemPage), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
