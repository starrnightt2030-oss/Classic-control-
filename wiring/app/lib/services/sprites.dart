import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/board_geom.dart';

/// Front renders of the real devices (Blender, assets/board/*.webp), decoded once.
class Sprites {
  Sprites._();
  static final i = Sprites._();

  final Map<String, ui.Image> _img = {};
  /// bumps every time more pictures are ready, so painters repaint
  final ready = ValueNotifier<int>(0);
  Future<void>? _loading;

  ui.Image? operator [](String name) => _img[name];

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    Future<void> one(String n) async {
      try {
        final data = await rootBundle.load('assets/board/$n.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final f = await codec.getNextFrame();
        _img[n] = f.image;
        ready.value++;
      } catch (e) {
        debugPrint('sprite $n: $e');
      }
    }

    await Future.wait([for (final n in spriteGeom.keys) one(n)]);
  }
}
