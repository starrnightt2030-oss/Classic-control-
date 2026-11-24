import 'dart:convert';

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

  void load(String modelFile) => _run('cc.load(${jsonEncode('/assets/models/$modelFile')})');
  void setExplode(double t) => _run('cc.setExplode($t)');
  void setLabels(bool on) => _run('cc.setLabels($on)');
  void select(String? id) => _run('cc.select(${jsonEncode(id)})');
  void reset() => _run('cc.reset()');
}

class Viewer3D extends StatefulWidget {
  final Viewer3DController controller;
  final ValueChanged<String?> onPart;
  const Viewer3D({super.key, required this.controller, required this.onPart});

  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  @override
  Widget build(BuildContext context) {
    final url = '${AssetServer.instance.origin}/assets/web/viewer.html';
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
        widget.controller._attach(c);
        c.addJavaScriptHandler(
          handlerName: 'ready',
          callback: (args) {
            widget.controller._markReady();
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'part',
          callback: (args) {
            final id = args.isEmpty ? null : args.first;
            widget.onPart(id is String && id.isNotEmpty ? id : null);
            return null;
          },
        );
      },
      onLoadStop: (c, _) async {
        // fallback when the platform-ready event isn't delivered
        final t = await c.evaluateJavascript(source: 'typeof window.cc');
        if (t == 'object') widget.controller._markReady();
      },
      onConsoleMessage: (c, m) {
        if (kDebugMode) debugPrint('[viewer] ${m.message}');
      },
    );
  }
}
