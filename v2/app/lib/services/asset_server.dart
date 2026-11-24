import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Tiny loopback HTTP server that serves the Flutter asset bundle to the
/// WebView (3D viewer). Same code path on Android and Windows: ES modules and
/// GLB fetches need http(s) URLs, file:// is blocked for both.
class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  HttpServer? _server;
  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';

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
    'ogg': 'audio/ogg',
  };

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path.startsWith('/')) path = path.substring(1);
      if (!path.startsWith('assets/') || path.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      final data = await rootBundle.load(path);
      final ext = path.split('.').last.toLowerCase();
      res.headers.set(HttpHeaders.contentTypeHeader, _mime[ext] ?? 'application/octet-stream');
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      res.headers.set('Access-Control-Allow-Origin', '*');
      res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }
}
