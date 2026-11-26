// The running simulation screens: they draw without errors while the circuit and a
// machine run, and the screen is redrawn at Perf.simFps, not every frame.
import 'package:classic_control/lab/lab_page.dart';
import 'package:classic_control/lab/machine_sprites.dart';
import 'package:classic_control/schem/schem_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // the Blender sprites are decoded for real before any test: a load started inside a
  // test's fake clock (the schematic's flat view asks for one) would never finish
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MachineSprites.loadAll();
  });

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

  testWidgets('panel lab with every machine on the bench runs without errors', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(1600, 1000));
    expect(MachineSprites.of('sort'), isNotNull, reason: 'the Blender sprites load from the assets');
    expect(MachineSprites.of('fill')!.layers.keys, containsAll(['base', 'bottle', 'bottle_full', 'stream']));
    await t.pumpWidget(const MaterialApp(home: LabPage(demo: 7)));
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
