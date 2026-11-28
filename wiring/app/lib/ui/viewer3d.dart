import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/asset_server.dart';

/// Commands to the three.js viewer (assets/web/viewer.js); calls made before the
/// page is ready are queued.
class Viewer3DController {
  InAppWebViewController? _web;
  bool _ready = false;
  final List<String> _queue = [];

  void _markReady() {
    if (_ready) return;
    _ready = true;
    for (final js in List<String>.from(_queue)) {
      _web?.evaluateJavascript(source: js);
    }
    _queue.clear();
  }

  void _run(String js) {
    final web = _web;
    if (_ready && web != null) {
      web.evaluateJavascript(source: js);
    } else {
      _queue.add(js);
    }
  }

  void load(String model, {String nameAr = '', String nameEn = ''}) =>
      _run('cc.load(${jsonEncode('/assets/models/$model.glb')}, ${jsonEncode(nameAr)}, ${jsonEncode(nameEn)})');
  void setExplode(double t) => _run('cc.setExplode($t)');
  void setLabels(bool on) => _run('cc.setLabels($on)');
  void select(String? id) => _run('cc.select(${jsonEncode(id)})');
  void reset() => _run('cc.reset()');
}

/// The 3D model of a device or a tool: turn it with a finger, pinch to zoom, and
/// pull it apart to see its parts. Falls back to the studio render where there is
/// no WebView (the web preview).
class Viewer3D extends StatefulWidget {
  final String model;
  final String nameAr;
  final String nameEn;
  final Viewer3DController? controller;
  const Viewer3D({super.key, required this.model, this.nameAr = '', this.nameEn = '', this.controller});

  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  late final Viewer3DController ctl = widget.controller ?? Viewer3DController();
  bool _server = AssetServer.instance.running;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && !_server) {
      AssetServer.instance.start().then((_) {
        if (mounted) setState(() => _server = true);
      });
    }
    ctl.load(widget.model, nameAr: widget.nameAr, nameEn: widget.nameEn);
  }

  @override
  void didUpdateWidget(Viewer3D old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) ctl.load(widget.model, nameAr: widget.nameAr, nameEn: widget.nameEn);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return ModelPicture(widget.model);
    if (!_server) return const Center(child: CircularProgressIndicator());
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${AssetServer.instance.origin}/assets/web/viewer.html')),
      initialSettings: InAppWebViewSettings(
        transparentBackground: false,
        supportZoom: false,
        disableContextMenu: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        useHybridComposition: true,
        isInspectable: kDebugMode,
      ),
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onWebViewCreated: (c) {
        ctl._web = c;
        c.addJavaScriptHandler(handlerName: 'ready', callback: (args) {
          ctl._markReady();
          return null;
        });
      },
      onLoadStop: (c, _) async {
        final t = await c.evaluateJavascript(source: 'typeof window.cc');
        if (t == 'object') ctl._markReady();
      },
    );
  }
}

/// The studio render of a model (assets/renders/<model>.webp), or its board sprite.
class ModelPicture extends StatelessWidget {
  final String model;
  const ModelPicture(this.model, {super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/renders/$model.webp',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.asset('assets/board/$model.webp', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.view_in_ar, size: 64, color: Colors.white24)),
      );
}

/// A 3D viewer with its controls (explode, labels, reset) under it.
class ModelStage extends StatefulWidget {
  final String model;
  final String nameAr;
  final String nameEn;
  const ModelStage({super.key, required this.model, this.nameAr = '', this.nameEn = ''});
  @override
  State<ModelStage> createState() => _ModelStageState();
}

class _ModelStageState extends State<ModelStage> {
  final ctl = Viewer3DController();
  double explode = 0;
  bool labels = true;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Viewer3D(key: ValueKey(widget.model), model: widget.model, nameAr: widget.nameAr, nameEn: widget.nameEn, controller: ctl),
        ),
      ),
      if (!kIsWeb)
        Row(children: [
          const Icon(Icons.open_with, size: 18, color: Colors.white54),
          const SizedBox(width: 6),
          const Text('فك', style: TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: explode,
              onChanged: (v) {
                setState(() => explode = v);
                ctl.setExplode(v);
              },
            ),
          ),
          IconButton(
            tooltip: 'أسماء الأجزاء',
            onPressed: () {
              setState(() => labels = !labels);
              ctl.setLabels(labels);
            },
            icon: Icon(labels ? Icons.label : Icons.label_off_outlined),
          ),
          IconButton(tooltip: 'رجّع الوضع', onPressed: ctl.reset, icon: const Icon(Icons.center_focus_strong_outlined)),
        ]),
    ]);
  }
}
