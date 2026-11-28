import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum Sfx { click, trip, zap, sizzle, hum, bell, buzzer, success, fail, tap, wire, beep }

/// Small pool of players so quick effects can overlap.
class Sound {
  static bool enabled = true;
  static final _pool = List.generate(4, (_) => AudioPlayer());
  static int _next = 0;
  static final AudioPlayer _loop = AudioPlayer();
  static String? _looping;

  static Future<void> init() async {
    try {
      for (final p in _pool) {
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
      }
      await _loop.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('sound init: $e');
    }
  }

  static Future<void> play(Sfx s, {double volume = 1}) async {
    if (!enabled) return;
    try {
      final p = _pool[_next];
      _next = (_next + 1) % _pool.length;
      await p.stop();
      await p.play(AssetSource('sfx/${s.name}.wav'), volume: volume);
    } catch (e) {
      debugPrint('sound: $e');
    }
  }

  static Future<void> intro() async {
    if (!enabled) return;
    try {
      await _pool[0].play(AssetSource('sfx/intro.mp3'), volume: .9);
    } catch (e) {
      debugPrint('intro: $e');
    }
  }

  /// continuous sound (bell ringing, ballast hum); null stops it
  static Future<void> loop(Sfx? s, {double volume = .5}) async {
    final name = s?.name;
    if (name == _looping) return;
    _looping = name;
    try {
      await _loop.stop();
      if (s != null && enabled) await _loop.play(AssetSource('sfx/$name.wav'), volume: volume);
    } catch (e) {
      debugPrint('loop: $e');
    }
  }
}
