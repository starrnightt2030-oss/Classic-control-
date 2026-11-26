// The instrument (and its bench) in 3D: a three.js page (assets/web/instruments.html) showing
// the Blender models from v2/models/instruments.py. Flutter sends the whole state whenever it
// changes; the page animates toward it and sends taps back.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/asset_server.dart';
import '../ui/perf.dart';
import '../ui/theme.dart';

class Inst3DController {
  _Inst3DState? _s;
  void focus(String name) => _s?._focus(name);

  /// 'near': put the instrument down on a free surface next to the points being measured;
  /// 'home': back where it started. (A drag on the instrument in the 3D view moves it too.)
  void place(String where) => _s?._place(where);
}

class Inst3D extends StatefulWidget {
  final String instrument;
  final String? bench;
  final String mount;

  /// the state for the page (see instruments.js: inst.update)
  final Map<String, Object?> state;
  final ValueChanged<String> onTap;
  final Inst3DController? controller;
  final String? image;
  const Inst3D({super.key, required this.instrument, this.bench, this.mount = 'mount_meter', required this.state, required this.onTap, this.controller, this.image});

  /// widget tests have no web view
  static bool get available => !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<Inst3D> createState() => _Inst3DState();
}

class _Inst3DState extends State<Inst3D> {
  InAppWebViewController? _web;
  bool _ready = false, _shown = false, _mount = false;
  String _loaded = '', _sent = '';

  @override
  void initState() {
    super.initState();
    widget.controller?._s = this;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _mount = true);
    });
  }

  @override
  void dispose() {
    if (widget.controller?._s == this) widget.controller?._s = null;
    super.dispose();
  }

  String get _spec => jsonEncode({'instrument': widget.instrument, 'bench': widget.bench ?? '', 'mount': widget.mount});

  void _load() {
    if (!_ready || _loaded == _spec) return;
    _loaded = _spec;
    _sent = '';
    if (mounted && _shown) setState(() => _shown = false);
    _web?.evaluateJavascript(source: 'inst.load($_spec)');
  }

  void _push() {
    if (!_ready || !_shown) return;
    final js = jsonEncode(widget.state);
    if (js == _sent) return;
    _sent = js;
    _web?.evaluateJavascript(source: 'inst.update($js)');
  }

  void _focus(String name) => _web?.evaluateJavascript(source: 'inst.focus(${jsonEncode(name)})');
  void _place(String where) => _web?.evaluateJavascript(source: 'inst.place(${jsonEncode(where)})');

  @override
  void didUpdateWidget(Inst3D old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      widget.controller?._s = this;
    }
    if (_spec != _loaded) {
      _load();
    } else {
      _push();
    }
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cover = Container(
      color: CC.stage,
      alignment: Alignment.center,
      child: widget.image == null
          ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Stack(alignment: Alignment.center, children: [
              Padding(padding: const EdgeInsets.all(24), child: Image.asset(widget.image!, fit: BoxFit.contain)),
              if (Inst3D.available) const Positioned(bottom: 18, child: Text('جاري تحميل المجسم ثلاثي الأبعاد…', style: TextStyle(color: CC.muted, fontSize: 12))),
            ]),
    );
    if (!Inst3D.available || !_mount) return cover;
    return Stack(fit: StackFit.expand, children: [
      _webView(),
      if (!_shown) IgnorePointer(child: cover),
    ]);
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${AssetServer.instance.origin}/assets/web/instruments.html${Perf.lite ? '?q=lite' : ''}')),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
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
        _web = c;
        c.addJavaScriptHandler(
            handlerName: 'ready',
            callback: (_) {
              _markReady();
              return null;
            });
        c.addJavaScriptHandler(
            handlerName: 'loaded',
            callback: (_) {
              if (mounted) setState(() => _shown = true);
              _sent = '';
              WidgetsBinding.instance.addPostFrameCallback((_) => _push());
              return null;
            });
        c.addJavaScriptHandler(
            handlerName: 'tap',
            callback: (args) {
              if (args.isNotEmpty && args.first is String) widget.onTap(args.first as String);
              return null;
            });
      },
      onLoadStop: (c, _) async {
        final t = await c.evaluateJavascript(source: 'typeof window.inst');
        if (t == 'object') _markReady();
      },
      onConsoleMessage: (c, m) {
        if (kDebugMode) debugPrint('[instruments] ${m.message}');
      },
    );
  }
}
