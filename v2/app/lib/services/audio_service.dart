import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import 'packs.dart';

/// Narration (one at a time) + short sound effects.
class AudioService {
  AudioService._() {
    _voice.onPlayerComplete.listen((_) => playing.value = null);
    // effects, loops and narration mix together instead of stealing audio focus
    try {
      AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (_) {}
    for (var i = 0; i < 6; i++) {
      final p = AudioPlayer(playerId: 'sfx$i');
      p.setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
    }
  }

  final List<AudioPlayer> _pool = [];
  int _next = 0;
  final Map<String, AudioPlayer> _loops = {};
  static final AudioService instance = AudioService._();

  final AudioPlayer _voice = AudioPlayer(playerId: 'voice');
  final AudioPlayer _intro = AudioPlayer(playerId: 'intro');

  /// what is currently narrating (content audio ref), null when idle
  final ValueNotifier<String?> playing = ValueNotifier<String?>(null);

  bool sfxOn = true;

  /// an asset key, played from a content pack when a newer copy arrived
  static Source source(String key) {
    final f = PackStore.instance.file(key);
    return f != null ? DeviceFileSource(f.path) : AssetSource(key.substring('assets/'.length));
  }

  /// Plays a narration clip. Returns false when the recording isn't in the app yet.
  Future<bool> playVoice(String? ref) async {
    final key = Repository.instance.audioAsset(ref);
    if (key == null) return false;
    try {
      await _voice.stop();
      await _voice.play(source(key));
      playing.value = ref;
      return true;
    } catch (_) {
      playing.value = null;
      return false;
    }
  }

  Future<void> stopVoice() async {
    await _voice.stop();
    playing.value = null;
  }

  Future<void> playIntro() async {
    try {
      await _intro.play(source('assets/audio/sfx/intro_theme.mp3'), volume: 1.0);
    } catch (_) {}
  }

  Future<void> stopIntro() async {
    try {
      await _intro.stop();
    } catch (_) {}
  }

  /// A short effect. Several can overlap (a pool of players), so a contactor click is not
  /// cut off by the button click that caused it.
  Future<void> sfx(String name, {double volume = 0.85}) async {
    if (!sfxOn) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    try {
      await p.play(source('assets/audio/sfx/$name.mp3'), volume: volume);
    } catch (_) {}
  }

  /// Start or stop a looping sound (motor running, siren, buzzer, coil hum).
  Future<void> loop(String name, bool on, {double volume = 0.7}) async {
    final cur = _loops[name];
    if (!on || !sfxOn) {
      if (cur != null) {
        _loops.remove(name);
        try {
          await cur.stop();
          await cur.dispose();
        } catch (_) {}
      }
      return;
    }
    if (cur != null) {
      try {
        await cur.setVolume(volume);
      } catch (_) {}
      return;
    }
    final p = AudioPlayer(playerId: 'loop_$name');
    _loops[name] = p;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(source('assets/audio/sfx/$name.mp3'), volume: volume);
    } catch (_) {}
  }

  Future<void> stopLoops() async {
    for (final n in _loops.keys.toList()) {
      await loop(n, false);
    }
  }
}
