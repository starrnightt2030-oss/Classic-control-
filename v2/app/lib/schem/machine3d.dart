// The machine of the schematic simulator in 3D: a three.js page
// (assets/web/machine.html) showing the Blender models from v2/models/machines.py.
// Flutter sends the machine's state about 20 times a second and the page eases
// every moving part toward it.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../lab/machine_sprites.dart';
import '../services/asset_server.dart';
import '../sim/plant.dart';
import '../ui/perf.dart';

/// what the 3D page needs to draw this machine now (see machine.js)
Map<String, Object?> machineState(Plant p, PlantIo? io) {
  bool on(String t) => io != null && io.has(t) && io.on(t);
  double motor(String t) => io != null && io.has(t) ? io.motor(t) : 0;
  Map<String, bool> lamps(List<String> sensors, {List<String> valves = const [], List<String> motors = const []}) => {
        for (final t in sensors) t: p.sensor(t),
        for (final t in valves) t: on(t),
        for (final t in motors) t: motor(t).abs() > 0.01,
      };
  double r(double v) => (v * 1000).roundToDouble() / 1000;
  if (p is CartPlant) {
    return {
      'x': r(p.x),
      'run': r(motor('M1')),
      'lamps': lamps(['LS1', 'LS2'])
    };
  }
  if (p is HoistPlant) {
    return {
      'z': r(p.z),
      'lamps': lamps(['B1', 'B2'])
    };
  }
  if (p is LiftPlant) {
    return {
      'z': r(p.z),
      'door': r(p.door),
      'lamps': lamps(['B1', 'B2', 'B3'])
    };
  }
  if (p is SortPlant) {
    return {
      'ext': r(p.ext),
      'belt': r(p.belt),
      'items': [
        for (final b in p.boxes) [b.id, r(b.s), b.metal]
      ],
      'lamps': lamps(['B1', 'B2', 'B3', 'B4'], valves: ['Y1'], motors: ['M1']),
    };
  }
  if (p is PressPlant) {
    final part = p.part;
    return {
      'ext': r(p.ext),
      'part': part == null ? 0 : (part.pressed ? 2 : 1),
      'lamps': lamps(['B1', 'B2', 'B3'], valves: ['Y1']),
    };
  }
  if (p is FillPlant) {
    return {
      'belt': r(p.belt),
      'y1': on('Y1') && p.bottles.any((b) => (b.s - FillPlant.nozzle).abs() < 0.03),
      'items': [
        for (final b in p.bottles) [b.id, r(b.s), r(b.fill)]
      ],
      'lamps': lamps(['B1', 'B2'], valves: ['Y1'], motors: ['M1']),
    };
  }
  return {};
}

class Machine3D extends StatefulWidget {
  final Plant plant;
  final PlantIo? io;

  /// changes every simulation frame, so the state is sent again
  final int frame;
  const Machine3D({super.key, required this.plant, this.io, required this.frame});

  @override
  State<Machine3D> createState() => _Machine3DState();
}

class _Machine3DState extends State<Machine3D> {
  InAppWebViewController? _web;
  bool _ready = false;
  String? _kind;
  String _sent = '';
  final _since = Stopwatch()..start();

  /// the web view is made a moment after the panel opens, so opening a machine never
  /// stalls the screen; the drawn machine shows until the 3D one has loaded
  bool _mount = false, _shown = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _mount = true);
    });
  }

  void _load() {
    final k = widget.plant.key;
    if (!_ready || _kind == k) return;
    _kind = k;
    _sent = '';
    _web?.evaluateJavascript(source: "mc.load('/assets/models/machine_$k.glb','$k')");
    _push(force: true);
  }

  void _push({bool force = false}) {
    if (!_ready || _kind == null) return;
    if (!force && _since.elapsedMilliseconds < 50) return;
    final js = jsonEncode(machineState(widget.plant, widget.io));
    if (js == _sent) return;
    _since.reset();
    _sent = js;
    _web?.evaluateJavascript(source: 'mc.update($js)');
  }

  @override
  void didUpdateWidget(Machine3D old) {
    super.didUpdateWidget(old);
    if (widget.plant.key != _kind) {
      _load();
    } else {
      _push(force: !identical(old.plant, widget.plant));
    }
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final flat = IgnorePointer(child: CustomPaint(painter: machineFlatPainter(widget.plant, widget.io, widget.frame), size: Size.infinite));
    if (!_mount) return flat;
    return Stack(fit: StackFit.expand, children: [
      _web3d(),
      if (!_shown) flat, // covers the page while it loads
    ]);
  }

  Widget _web3d() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${AssetServer.instance.origin}/assets/web/machine.html${Perf.lite ? '?q=lite' : ''}')),
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
              _push(force: true);
              if (mounted && !_shown) setState(() => _shown = true);
              return null;
            });
      },
      onLoadStop: (c, _) async {
        final t = await c.evaluateJavascript(source: 'typeof window.mc');
        if (t == 'object') _markReady();
      },
      onConsoleMessage: (c, m) {
        if (kDebugMode) debugPrint('[machine] ${m.message}');
      },
    );
  }
}
