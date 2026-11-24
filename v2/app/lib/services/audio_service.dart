import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';

/// Narration (one at a time) + short sound effects.
class AudioService {
  AudioService._() {
    _voice.onPlayerComplete.listen((_) => playing.value = null);
  }
  static final AudioService instance = AudioService._();

  final AudioPlayer _voice = AudioPlayer(playerId: 'voice');
  final AudioPlayer _sfx = AudioPlayer(playerId: 'sfx');
  final AudioPlayer _intro = AudioPlayer(playerId: 'intro');

  /// what is currently narrating (content audio ref), null when idle
  final ValueNotifier<String?> playing = ValueNotifier<String?>(null);

  bool sfxOn = true;

  /// Plays a narration clip. Returns false when the recording isn't in the app yet.
  Future<bool> playVoice(String? ref) async {
    final key = Repository.instance.audioAsset(ref);
    if (key == null) return false;
    try {
      await _voice.stop();
      await _voice.play(AssetSource(key.substring('assets/'.length)));
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
    if (!Repository.instance.hasAsset('assets/audio/sfx/intro_theme.mp3')) return;
    try {
      await _intro.play(AssetSource('audio/sfx/intro_theme.mp3'), volume: 0.9);
    } catch (_) {}
  }

  Future<void> stopIntro() async {
    try {
      await _intro.stop();
    } catch (_) {}
  }

  Future<void> sfx(String name) async {
    if (!sfxOn) return;
    final key = 'assets/audio/sfx/$name.mp3';
    if (!Repository.instance.hasAsset(key)) return;
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource(key.substring('assets/'.length)), volume: 0.6);
    } catch (_) {}
  }
}
