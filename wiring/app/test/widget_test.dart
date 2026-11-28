import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiring_academy/data/circuits.dart';
import 'package:wiring_academy/theme.dart';
import 'package:wiring_academy/ui/circuits_page.dart';
import 'package:wiring_academy/ui/lab/lab_page.dart';
import 'package:wiring_academy/ui/lab/painters.dart';

Widget app(Widget w) => MaterialApp(theme: buildTheme(), home: Directionality(textDirection: TextDirection.rtl, child: w));

void main() {
  for (final m in LabMode.values) {
    testWidgets('lab page opens in ${m.name}', (t) async {
      t.view.physicalSize = const Size(1366, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(LabPage(circuit: m == LabMode.free ? null : circuits[11], mode: m)));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(CustomPaint), findsWidgets);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('schematic skin and circuit page render', (t) async {
    t.view.physicalSize = const Size(412, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(CircuitPage(circuits[20])));
    await t.pump();
    await t.pumpWidget(app(LabPage(circuit: circuits[7], mode: LabMode.demo, skin: Skin.schematic)));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpWidget(const SizedBox());
  });
}
