// Performance switches shared by the heavy screens (schematic, panel lab, 3D machine).
//
// Interactive touch screens in classrooms are usually large Windows panels with a
// modest GPU: Flutter draws at the panel's full resolution, so every full-screen
// blur and every repaint of the whole sheet costs a lot there. On desktop the app
// drops the backdrop blur, keeps the running simulation at [simFps] frames a
// second, and asks the 3D page for its light quality.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class Perf {
  Perf._();

  static bool get desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// the cheap look: no backdrop blur, lighter 3D (shadows, pixel ratio, frame rate)
  static bool lite = desktop;

  /// how often a running simulation repaints the screen (the physics still steps every frame)
  static const simFps = 30;
  static const simFrame = 1 / simFps;
}

/// Laid-out text reused between frames: the sheet and the machines draw the same
/// tags and labels again every frame, and laying text out is the slow part of that.
class TextCache {
  TextCache._();
  static final _m = <Object, TextPainter>{};
  static const _max = 3000;

  static TextPainter get(String text, TextStyle style, {TextDirection dir = TextDirection.ltr, double maxWidth = double.infinity, int? maxLines, String? ellipsis}) {
    final k = Object.hash(text, style, dir, maxWidth, maxLines, ellipsis);
    final hit = _m[k];
    if (hit != null) return hit;
    if (_m.length >= _max) {
      for (final t in _m.values) {
        t.dispose();
      }
      _m.clear();
    }
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: dir, maxLines: maxLines, ellipsis: ellipsis)..layout(maxWidth: maxWidth);
    return _m[k] = tp;
  }
}
