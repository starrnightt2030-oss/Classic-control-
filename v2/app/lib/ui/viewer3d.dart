import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/asset_server.dart';

/// Commands to the three.js viewer (assets/web/viewer.js). Calls made before
/// the page is ready are queued.
class Viewer3DController {
  InAppWebViewController? _web;
  bool _ready = false;
  final List<String> _queue = [];
  final Map<String, Completer<String?>> _pending = {};
  final ValueNotifier<int?> progress = ValueNotifier<int?>(null);
  int _seq = 0;

  void _attach(InAppWebViewController c) => _web = c;

  void _markReady() {
    if (_ready) return;
    _ready = true;
    final pending = List<String>.from(_queue);
    _queue.clear();
    for (final js in pending) {
      _web?.evaluateJavascript(source: js);
    }
  }

  void _run(String js) {
    final web = _web;
    if (_ready && web != null) {
      web.evaluateJavascript(source: js);
    } else {
      _queue.add(js);
    }
  }

  void _resolve(String token, Object? value) {
    final c = _pending.remove(token);
    if (c != null && !c.isCompleted) c.complete(value is String && value.isNotEmpty ? value : null);
  }

  void load(String modelFile, {String nameAr = '', String nameEn = ''}) =>
      _run('cc.load(${jsonEncode('/assets/models/$modelFile')}, ${jsonEncode(nameAr)}, ${jsonEncode(nameEn)})');
  void setExplode(double t) => _run('cc.setExplode($t)');
  void scrub(double t) => _run('cc.scrub(${t.toStringAsFixed(3)})');
  void setLabels(bool on) => _run('cc.setLabels($on)');
  void select(String? id) => _run('cc.select(${jsonEncode(id)})');
  void focus(String id) => _run('cc.focus(${jsonEncode(id)})');
  void reset() => _run('cc.reset()');

  String _token(String kind) => '${kind}_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  /// Labelled snapshots (assembled, exploded) as JPEG files.
  Future<List<File>> captureSheet() async {
    final token = _token('sheet');
    final c = Completer<String?>();
    _pending[token] = c;
    _run('cc.captureSheet(${jsonEncode(token)})');
    final names = await c.future.timeout(const Duration(seconds: 60), onTimeout: () => null);
    if (names == null) return const [];
    final files = <File>[];
    for (final n in names.split(',')) {
      files.add(await AssetServer.instance.waitUpload(n, timeout: const Duration(seconds: 30)));
    }
    return files;
  }

  /// Records the presentation video; returns the file, or null when unsupported/failed.
  Future<File?> recordVideo() async {
    final token = _token('video');
    final c = Completer<String?>();
    _pending[token] = c;
    progress.value = 0;
    _run('cc.recordVideo(${jsonEncode(token)})');
    final name = await c.future.timeout(const Duration(seconds: 90), onTimeout: () => null);
    progress.value = null;
    if (name == null || name == 'unsupported') return null;
    return AssetServer.instance.waitUpload(name, timeout: const Duration(seconds: 60));
  }
}

class Viewer3D extends StatefulWidget {
  final Viewer3DController controller;
  final ValueChanged<String?> onPart;
  final VoidCallback? onLoaded;
  const Viewer3D({super.key, required this.controller, required this.onPart, this.onLoaded});

  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  @override
  Widget build(BuildContext context) {
    final url = '${AssetServer.instance.origin}/assets/web/viewer.html';
    final ctl = widget.controller;
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: false,
        supportZoom: false,
        disableContextMenu: true,
        mediaPlaybackRequiresUserGesture: false,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        useHybridComposition: true,
        isInspectable: kDebugMode,
      ),
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onWebViewCreated: (c) {
        ctl._attach(c);
        c.addJavaScriptHandler(handlerName: 'ready', callback: (args) {
          ctl._markReady();
          return null;
        });
        c.addJavaScriptHandler(handlerName: 'part', callback: (args) {
          final id = args.isEmpty ? null : args.first;
          widget.onPart(id is String && id.isNotEmpty ? id : null);
          return null;
        });
        c.addJavaScriptHandler(handlerName: 'loaded', callback: (args) {
          widget.onLoaded?.call();
          return null;
        });
        c.addJavaScriptHandler(handlerName: 'captured', callback: (args) {
          if (args.isNotEmpty) ctl._resolve('${args[0]}', args.length > 1 ? args[1] : null);
          return null;
        });
        c.addJavaScriptHandler(handlerName: 'recorded', callback: (args) {
          if (args.isNotEmpty) ctl._resolve('${args[0]}', args.length > 1 ? args[1] : null);
          return null;
        });
        c.addJavaScriptHandler(handlerName: 'progress', callback: (args) {
          if (args.length > 1 && args[1] is num) ctl.progress.value = (args[1] as num).round();
          return null;
        });
      },
      onLoadStop: (c, _) async {
        final t = await c.evaluateJavascript(source: 'typeof window.cc');
        if (t == 'object') ctl._markReady();
      },
      onConsoleMessage: (c, m) {
        if (kDebugMode) debugPrint('[viewer] ${m.message}');
      },
    );
  }
}
