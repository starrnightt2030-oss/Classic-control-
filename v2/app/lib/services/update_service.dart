import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import 'packs.dart';

/// One build published by CI (`update.json` attached to every
/// `v2-app-build-N` release).
class UpdateInfo {
  final int build;
  final String version, sha, notes, tag, repo;
  final ReleaseFile? android, windows, windowsPatch;
  final int patchFrom;

  /// asset key → (sha256, size, path in the repository)
  final Map<String, (String, int, String)> files;

  const UpdateInfo({
    required this.build,
    required this.version,
    required this.sha,
    required this.notes,
    required this.tag,
    required this.repo,
    this.android,
    this.windows,
    this.windowsPatch,
    this.patchFrom = 0,
    this.files = const {},
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j, {required String tag}) {
    ReleaseFile? rf(Object? o) => o is Map<String, dynamic> && o['name'] is String ? ReleaseFile.fromJson(o) : null;
    final win = j['windows'] as Map<String, dynamic>?;
    final patch = win?['patch'] as Map<String, dynamic>?;
    final files = <String, (String, int, String)>{};
    final fj = j['files'];
    if (fj is Map<String, dynamic>) {
      for (final e in fj.entries) {
        final v = e.value as Map<String, dynamic>;
        files[e.key] = (v['sha'] as String, (v['size'] as num).toInt(), v['src'] as String);
      }
    }
    return UpdateInfo(
      build: (j['build'] as num).toInt(),
      version: j['version'] as String? ?? '',
      sha: j['sha'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      tag: tag,
      repo: j['repo'] as String? ?? UpdateService.repo,
      android: rf(j['android']),
      windows: rf(win),
      windowsPatch: rf(patch),
      patchFrom: (patch?['from'] as num?)?.toInt() ?? 0,
      files: files,
    );
  }

  Uri asset(String name) => Uri.parse('https://github.com/$repo/releases/download/$tag/$name');
  Uri raw(String src) => Uri.parse('https://raw.githubusercontent.com/$repo/$sha/$src');

  /// the Windows download for a PC on [build]: only the changed files when it is
  /// the build the patch was made from, the whole folder otherwise
  ReleaseFile? windowsFor(int build) => windowsPatch != null && patchFrom > 0 && patchFrom == build ? windowsPatch : windows;

  /// content files that differ from what the app has
  List<String> changedFiles(Map<String, String> have) => [
        for (final e in files.entries)
          if (have[e.key] != e.value.$1) e.key
      ];

  int sizeOf(Iterable<String> keys) => keys.fold(0, (s, k) => s + (files[k]?.$2 ?? 0));
}

class ReleaseFile {
  final String name, sha;
  final int size;
  const ReleaseFile(this.name, this.size, this.sha);
  factory ReleaseFile.fromJson(Map<String, dynamic> j) => ReleaseFile(j['name'] as String, (j['size'] as num?)?.toInt() ?? 0, j['sha'] as String? ?? '');
}

enum UpdatePhase { idle, checking, upToDate, available, downloading, installing, failed }

class UpdateStatus {
  final UpdatePhase phase;
  final UpdateInfo? info;
  final double progress; // 0…1 while downloading
  final String? message;
  const UpdateStatus(this.phase, {this.info, this.progress = 0, this.message});
}

/// Looks for new builds, keeps content packs in step, and installs new app builds:
/// * content (lessons, narration, sounds, 3D models): only the changed files are
///   downloaded, straight from the repository at the release commit, and used at once;
/// * Windows: only the changed program files when coming from the previous build,
///   swapped in by a small script after the app closes, then the app opens again;
/// * Android: the new APK is downloaded and Android's installer opens (Android
///   always needs the whole APK and one tap on «تثبيت» for apps not from a store).
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const repo = 'starrnightt2030-oss/Classic-control-';
  static const tagPrefix = 'v2-app-build-';

  /// content packs up to this size are fetched without asking
  static const autoContentBytes = 25 * 1024 * 1024;

  final ValueNotifier<UpdateStatus> status = ValueNotifier(const UpdateStatus(UpdatePhase.idle));

  /// a content pack arrived: number of files (the UI tells the user)
  final ValueNotifier<int> contentArrived = ValueNotifier(0);

  Timer? _timer;
  bool _busy = false;

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  /// check now and then every hour while the app is open
  void start() {
    if (!supported) return;
    unawaited(check());
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) => check());
  }

  /// pick the newest `v2-app-build-N` release that carries an update.json
  static (String tag, int build, String url)? pickLatest(List<dynamic> releases) {
    (String, int, String)? best;
    for (final r in releases.whereType<Map<String, dynamic>>()) {
      final tag = r['tag_name'] as String? ?? '';
      if (!tag.startsWith(tagPrefix) || r['draft'] == true) continue;
      final n = int.tryParse(tag.substring(tagPrefix.length));
      if (n == null) continue;
      final assets = (r['assets'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
      final uj = assets.where((a) => a['name'] == 'update.json').firstOrNull;
      if (uj == null) continue;
      if (best == null || n > best.$2) best = (tag, n, uj['browser_download_url'] as String);
    }
    return best;
  }

  Future<UpdateInfo?> check({bool manual = false}) async {
    if (_busy || !supported) return null;
    _busy = true;
    if (manual) status.value = const UpdateStatus(UpdatePhase.checking);
    try {
      final list = jsonDecode(utf8.decode(await _get(Uri.parse('https://api.github.com/repos/$repo/releases?per_page=15')))) as List<dynamic>;
      final latest = pickLatest(list);
      if (latest == null) {
        status.value = const UpdateStatus(UpdatePhase.upToDate);
        return null;
      }
      final info = UpdateInfo.fromJson(jsonDecode(utf8.decode(await _get(Uri.parse(latest.$3)))) as Map<String, dynamic>, tag: latest.$1);
      await _syncContent(info, manual: manual);
      final mine = AppInfo.buildNumber;
      if (mine > 0 && info.build > mine && _fileFor(info) != null) {
        status.value = UpdateStatus(UpdatePhase.available, info: info);
        return info;
      }
      status.value = UpdateStatus(UpdatePhase.upToDate, info: info);
      return null;
    } catch (e) {
      status.value = UpdateStatus(manual ? UpdatePhase.failed : UpdatePhase.idle, message: 'مفيش اتصال بالإنترنت أو GitHub مش بيرد. جرّب تاني بعد شوية.');
      return null;
    } finally {
      _busy = false;
    }
  }

  ReleaseFile? _fileFor(UpdateInfo i) => Platform.isAndroid ? i.android : (Platform.isWindows ? i.windowsFor(AppInfo.buildNumber) : null);

  /// the size the user will download for [i] on this device
  int downloadSize(UpdateInfo i) => _fileFor(i)?.size ?? 0;
  bool isPatch(UpdateInfo i) => Platform.isWindows && identical(_fileFor(i), i.windowsPatch);

  /// a later reminder for this build: not before a day has passed
  Future<bool> snoozed(int build) async {
    final p = await SharedPreferences.getInstance();
    final at = p.getInt('update_snooze_$build') ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at < const Duration(hours: 20).inMilliseconds;
  }

  Future<void> snooze(int build) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('update_snooze_$build', DateTime.now().millisecondsSinceEpoch);
  }

  // ------------------------------------------------------------- content packs
  Future<void> _syncContent(UpdateInfo info, {bool manual = false}) async {
    final store = PackStore.instance;
    // a build without the bundled manifest (development) cannot tell what changed
    if (!store.ready || store.have.isEmpty || info.files.isEmpty || info.sha.isEmpty) return;
    final todo = info.changedFiles(store.have);
    if (todo.isEmpty) return;
    if (!manual && info.sizeOf(todo) > autoContentBytes) return;
    var n = 0;
    for (final k in todo) {
      final (sha, _, src) = info.files[k]!;
      try {
        final bytes = await _get(info.raw(src));
        if (sha256.convert(bytes).toString() != sha) continue;
        await store.put(k, sha, bytes);
        n++;
      } catch (_) {
        // the next check picks it up again
      }
    }
    if (n > 0) {
      await store.save(info.build);
      contentArrived.value = contentArrived.value + n;
    }
  }

  // --------------------------------------------------------------- app update
  /// download the new build for this device and install it
  Future<void> install(UpdateInfo info) async {
    final f = _fileFor(info);
    if (f == null) return;
    try {
      status.value = UpdateStatus(UpdatePhase.downloading, info: info);
      final tmp = await getTemporaryDirectory();
      final out = File('${tmp.path}${Platform.pathSeparator}${f.name}');
      await _download(info.asset(f.name), out, f.size, (p) => status.value = UpdateStatus(UpdatePhase.downloading, info: info, progress: p));
      if (f.sha.isNotEmpty && (await sha256.bind(out.openRead()).first).toString() != f.sha) {
        throw const FileSystemException('الملف نزل ناقص');
      }
      status.value = UpdateStatus(UpdatePhase.installing, info: info);
      if (Platform.isAndroid) {
        final r = await OpenFilex.open(out.path, type: 'application/vnd.android.package-archive');
        if (r.type != ResultType.done) {
          status.value = UpdateStatus(UpdatePhase.failed, info: info, message: 'أندرويد ما فتحش شاشة التثبيت. اسمح للتطبيق بتثبيت التطبيقات من الإعدادات وجرّب تاني.');
        } else {
          status.value = UpdateStatus(UpdatePhase.available, info: info, message: 'كمّل التثبيت من شاشة أندرويد.');
        }
      } else if (Platform.isWindows) {
        await _windowsSwap(out);
      }
    } catch (e) {
      status.value = UpdateStatus(UpdatePhase.failed, info: info, message: 'التحديث ما كملش. اتأكد من النت وجرّب تاني.');
    }
  }

  /// script that waits for the app to close, unpacks the new files over it and opens it again
  static String windowsScript() => r'''
param([int]$ProcId, [string]$Zip, [string]$Dest, [string]$Exe)
try { Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 500
try {
  Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
  Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("التحديث ما اتركبش: $($_.Exception.Message)", "Control Academy") | Out-Null
}
Start-Process -FilePath $Exe -WorkingDirectory $Dest
''';

  Future<void> _windowsSwap(File zip) async {
    final exe = Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    // the folder must be writable (not Program Files)
    final probe = File('$dir${Platform.pathSeparator}.cc_write_test');
    try {
      probe.writeAsStringSync('ok');
      probe.deleteSync();
    } catch (_) {
      status.value = const UpdateStatus(UpdatePhase.failed, message: 'فولدر البرنامج مقفول للكتابة. انقل فولدر البرنامج لمكان زي المستندات وجرّب تاني.');
      return;
    }
    final script = File('${zip.parent.path}${Platform.pathSeparator}cc_update.ps1');
    // UTF-8 with BOM so Windows PowerShell reads the Arabic message right
    await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(windowsScript())]);
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path, '-ProcId', '$pid', '-Zip', zip.path, '-Dest', dir, '-Exe', exe],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  // ------------------------------------------------------------------- http
  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'ControlAcademy-App';

  Future<List<int>> _get(Uri u) async {
    final c = _client();
    try {
      final req = await c.getUrl(u);
      req.headers.set(HttpHeaders.acceptHeader, u.host == 'api.github.com' ? 'application/vnd.github+json' : '*/*');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: u);
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      c.close();
    }
  }

  Future<void> _download(Uri u, File out, int size, void Function(double) onProgress) async {
    final c = _client();
    try {
      final req = await c.getUrl(u);
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: u);
      final total = res.contentLength > 0 ? res.contentLength : size;
      final sink = out.openWrite();
      var got = 0, last = 0.0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          final p = total > 0 ? got / total : 0.0;
          if (p - last > 0.01) {
            last = p;
            onProgress(p);
          }
        }
      } finally {
        await sink.close();
      }
      if (size > 0 && got != size) throw const FileSystemException('الملف نزل ناقص');
    } finally {
      c.close();
    }
  }
}
