import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Tiny loopback HTTP server between the app and its WebViews.
///  * GET  /assets/...       → the Flutter asset bundle (ES modules and GLB need http URLs)
///  * POST /upload/<name>    → binary results from the WebView (snapshots, recorded video)
class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  HttpServer? _server;
  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';

  final Map<String, Completer<File>> _uploads = {};
  late Directory _uploadDir;

  static const _mime = <String, String>{
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'svg': 'image/svg+xml',
    'glb': 'model/gltf-binary',
    'png': 'image/png',
    'webp': 'image/webp',
    'jpg': 'image/jpeg',
    'ttf': 'font/ttf',
    'woff2': 'font/woff2',
    'mp3': 'audio/mpeg',
    'mp4': 'video/mp4',
    'ogg': 'audio/ogg',
  };

  Future<void> start() async {
    if (_server != null) return;
    _uploadDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}cc_exports');
    if (!_uploadDir.existsSync()) _uploadDir.createSync(recursive: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  /// Completes when the WebView has POSTed /upload/[name].
  Future<File> waitUpload(String name, {Duration timeout = const Duration(minutes: 2)}) {
    final c = _uploads.putIfAbsent(name, () => Completer<File>());
    return c.future.timeout(timeout);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path.startsWith('/')) path = path.substring(1);
      if (path.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
      } else if (req.method == 'POST' && path.startsWith('upload/')) {
        final name = path.substring('upload/'.length).replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
        final file = File('${_uploadDir.path}${Platform.pathSeparator}$name');
        final sink = file.openWrite();
        await req.cast<List<int>>().pipe(sink);
        _uploads.putIfAbsent(name, () => Completer<File>()).complete(file);
        res.statusCode = HttpStatus.ok;
      } else if (path.startsWith('assets/')) {
        final data = await rootBundle.load(path);
        final ext = path.split('.').last.toLowerCase();
        res.headers.set(HttpHeaders.contentTypeHeader, _mime[ext] ?? 'application/octet-stream');
        res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } else {
        res.statusCode = HttpStatus.forbidden;
      }
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }
}
