import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'models.dart';

/// Loads all content once and answers lookups. Also knows which audio
/// recordings exist yet (recordings arrive gradually).
class Repository {
  Repository._();
  static final Repository instance = Repository._();

  final Map<String, Component> _byId = {};
  final Set<String> _assets = {};
  SharedPreferences? _prefs;

  List<Component> get all {
    final order = [for (final c in categories) ...c.components];
    final list = _byId.values.toList();
    list.sort((a, b) {
      final ia = order.indexOf(a.id), ib = order.indexOf(b.id);
      return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
    });
    return list;
  }

  Component? byId(String id) => _byId[id];

  Future<void> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    _assets.addAll(manifest.listAssets());
    for (final key in _assets) {
      if (!key.startsWith('assets/content/') || !key.endsWith('.json')) continue;
      if (key.endsWith('audio_cues.json')) continue;
      try {
        final j = jsonDecode(await rootBundle.loadString(key));
        if (j is Map && j['component'] != null) {
          final c = Component.fromJson(j);
          _byId[c.id] = c;
        }
      } catch (_) {
        // a broken content file must not take the whole library down
      }
    }
    _prefs = await SharedPreferences.getInstance();
  }

  /// assets path for a content audio reference like "contactor/coil.mp3"
  String? audioAsset(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final key = 'assets/audio/$ref';
    return _assets.contains(key) ? key : null;
  }

  bool hasAsset(String key) => _assets.contains(key);

  String thumbFor(String componentId) {
    final key = 'assets/images/thumbs/$componentId.webp';
    return _assets.contains(key) ? key : 'assets/images/thumbs/_placeholder.webp';
  }

  int get recordedClips => _assets.where((a) => a.startsWith('assets/audio/') && !a.startsWith('assets/audio/sfx/')).length;

  // ---- progress (local) ----
  String? get lastComponent => _prefs?.getString('last_component');
  Future<void> setLastComponent(String id) async {
    await _prefs?.setString('last_component', id);
  }

  Set<String> seenParts(String componentId) => (_prefs?.getStringList('seen_$componentId') ?? const <String>[]).toSet();

  Future<void> markSeen(String componentId, String partId) async {
    final s = seenParts(componentId)..add(partId);
    await _prefs?.setStringList('seen_$componentId', s.toList());
  }
}
