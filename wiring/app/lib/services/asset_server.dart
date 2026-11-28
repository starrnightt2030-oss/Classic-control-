import 'dart:io';

import 'package:flutter/services.dart';

/// Tiny loopback HTTP server that hands the Flutter asset bundle to the 3D WebView
/// (ES modules and GLB files need http URLs).
class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  HttpServer? _server;
  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';
  bool get running => _server != null;

  static const _mime = <String, String>{
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'glb': 'model/gltf-binary',
    'png': 'image/png',
    'webp': 'image/webp',
    'jpg': 'image/jpeg',
    'ttf': 'font/ttf',
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
      if (path.contains('..') || !path.startsWith('assets/')) {
        res.statusCode = HttpStatus.forbidden;
      } else {
        final ext = path.split('.').last.toLowerCase();
        res.headers.set(HttpHeaders.contentTypeHeader, _mime[ext] ?? 'application/octet-stream');
        final data = await rootBundle.load(path);
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }
}
