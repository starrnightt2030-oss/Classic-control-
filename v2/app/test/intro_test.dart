import 'package:classic_control/ui/intro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the intro plays through and opens the app', (t) async {
    // no audio plugin in tests
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception is MissingPluginException) return;
      orig?.call(d);
    };
    addTearDown(() => FlutterError.onError = orig);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: IntroPage(next: Scaffold(body: Text('app')))));
    await t.pump();
    for (var s = 0.0; s < IntroTimes.end + 0.2; s += 0.1) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('skip leaves at once', (t) async {
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception is MissingPluginException) return;
      orig?.call(d);
    };
    addTearDown(() => FlutterError.onError = orig);
    await t.pumpWidget(const MaterialApp(home: IntroPage(next: Scaffold(body: Text('app')))));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('تخطي'));
    // the page's double-tap-to-skip holds the tap for its timeout
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('app'), findsOneWidget);
  });
}
