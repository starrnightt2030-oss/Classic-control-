import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Content packs: lesson files, narration, sound effects and 3D models that
/// arrived after the app was installed. They live in the app's support folder
/// under the same keys as the bundled assets (`assets/content/contactor.json`…)
/// and win over the bundled copy, so new recordings and corrected lessons reach
/// the app without installing it again.
class PackStore {
  PackStore._();
  static final PackStore instance = PackStore._();

  Directory? _dir;

  /// key → sha256 of what the app has now (bundled, then overridden by packs)
  final Map<String, String> have = {};

  /// keys that are served from the pack folder
  final Set<String> local = {};

  /// build of the content the packs came from (0: only what was bundled)
  int build = 0;

  File get _manifest => File('${_dir!.path}${Platform.pathSeparator}manifest.json');

  Future<void> init() async {
    // what was bundled (written by tool/pack_manifest.py in CI; missing in dev builds)
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/pack/manifest.json')) as Map<String, dynamic>;
      for (final e in (j['files'] as Map<String, dynamic>).entries) {
        have[e.key] = e.value as String;
      }
    } catch (_) {}
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}${Platform.pathSeparator}packs');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
      if (_manifest.existsSync()) {
        final j = jsonDecode(_manifest.readAsStringSync()) as Map<String, dynamic>;
        build = (j['build'] as num?)?.toInt() ?? 0;
        for (final e in (j['files'] as Map<String, dynamic>).entries) {
          if (fileFor(e.key, check: false).existsSync()) {
            have[e.key] = e.value as String;
            local.add(e.key);
          }
        }
      }
    } catch (_) {
      _dir = null;
    }
  }

  bool get ready => _dir != null;

  File fileFor(String key, {bool check = true}) {
    final rel = key.split('/').join(Platform.pathSeparator);
    return File('${_dir!.path}${Platform.pathSeparator}$rel');
  }

  /// the pack copy of an asset key, or null when the bundled one is current
  File? file(String key) {
    if (_dir == null || !local.contains(key)) return null;
    final f = fileFor(key);
    return f.existsSync() ? f : null;
  }

  /// store a downloaded asset (already checked against its sha256)
  Future<void> put(String key, String sha, List<int> bytes) async {
    final f = fileFor(key);
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    if (f.existsSync()) f.deleteSync();
    await tmp.rename(f.path);
    have[key] = sha;
    local.add(key);
  }

  Future<void> save(int fromBuild) async {
    build = fromBuild;
    await _manifest.writeAsString(jsonEncode({
      'build': build,
      'files': {for (final k in local) k: have[k]},
    }));
  }
}
