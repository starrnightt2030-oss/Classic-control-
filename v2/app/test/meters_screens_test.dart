// The «أجهزة القياس» screens lay out without errors on a phone and on a wide Windows screen,
// and the live bench reacts to taps from the 3D page (the web view itself is not in tests).
import 'package:classic_control/meters/instruments.dart';
import 'package:classic_control/meters/meters_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(420, 900), Size(1600, 950)]) {
    testWidgets('instrument list and every page at ${size.width.toInt()} wide', (t) async {
      await t.binding.setSurfaceSize(size);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: MetersPage())));
      await t.pump();
      expect(find.text(avo.nameAr), findsOneWidget);
      for (final inst in instruments) {
        for (var tab = 0; tab < 3; tab++) {
          await t.pumpWidget(MaterialApp(home: InstrumentPage(inst: inst, tab: tab)));
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(t.takeException(), isNull, reason: '${inst.key} tab $tab');
        }
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('a guided task can be started on the live bench', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 950));
    await t.pumpWidget(const MaterialApp(home: InstrumentPage(inst: avo, tab: 2)));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('قياس جهد الفاز مع النيوترال'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('حوّل المفتاح على ACV 250'), findsOneWidget);
    // pick the range from the panel
    await t.ensureVisible(find.text('ACV 250'));
    await t.pump();
    await t.tap(find.text('ACV 250'));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
