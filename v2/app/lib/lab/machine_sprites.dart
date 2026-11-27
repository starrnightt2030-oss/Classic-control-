// The machines drawn from their Blender models (v2/models/render_machines.py): a
// still layer plus the moving parts as separate sprites, moved by the machine's state
// with the projection the renderer saved. Used on the panel lab's bench and as the
// flat view of the schematic's machine panel.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../schem/plant_paint.dart';
import '../sim/plant.dart';

class MachineSprite {
  final String kind;
  final double w, h;
  final List<List<double>> a; // 2×4: Blender world (m) → image pixels
  final Map<String, (Rect, ui.Image)> layers;
  final Map<String, Offset> lamps;
  final Map<String, List<double>> points;
  MachineSprite(this.kind, this.w, this.h, this.a, this.layers, this.lamps, this.points);

  /// image pixels of a world point
  Offset px(double x, double y, double z) => Offset(a[0][0] * x + a[0][1] * y + a[0][2] * z + a[0][3], a[1][0] * x + a[1][1] * y + a[1][2] * z + a[1][3]);

  /// image pixels of a world displacement
  Offset dpx(double x, double y, double z) => Offset(a[0][0] * x + a[0][1] * y + a[0][2] * z, a[1][0] * x + a[1][1] * y + a[1][2] * z);

  Offset point(String n, {double dz = 0}) {
    final p = points[n]!;
    return px(p[0], p[1], p[2] + dz);
  }
}

class MachineSprites {
  MachineSprites._();
  static Map<String, dynamic>? _json;
  static final Map<String, MachineSprite> _ready = {};
  static final Map<String, Future<MachineSprite?>> _loading = {};

  /// the sprite if it has loaded (start loading with [load])
  static MachineSprite? of(String kind) => _ready[kind];

  static Future<MachineSprite?> load(String kind) => _loading[kind] ??= _load(kind);

  static Future<void> loadAll() => Future.wait([for (final k in const ['cart', 'hoist', 'lift', 'sort', 'press', 'fill', 'belt', 'fan', 'gate']) load(k)]);

  static Future<MachineSprite?> _load(String kind) async {
    try {
      _json ??= jsonDecode(await rootBundle.loadString('assets/panel/machine_sprites.json')) as Map<String, dynamic>;
      final j = _json![kind] as Map<String, dynamic>?;
      if (j == null) return null;
      final layers = <String, (Rect, ui.Image)>{};
      for (final e in (j['layers'] as Map<String, dynamic>).entries) {
        final b = (e.value as List).map((v) => (v as num).toDouble()).toList();
        final data = await rootBundle.load('assets/panel/mach_${kind}_${e.key}.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final img = (await codec.getNextFrame()).image;
        layers[e.key] = (Rect.fromLTWH(b[0], b[1], b[2], b[3]), img);
      }
      List<double> nums(Object? l) => (l as List).map((v) => (v as num).toDouble()).toList();
      final s = MachineSprite(
        kind,
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
        [for (final r in j['A'] as List) nums(r)],
        layers,
        {for (final e in (j['lamps'] as Map<String, dynamic>).entries) e.key: Offset(nums(e.value)[0], nums(e.value)[1])},
        {for (final e in (j['points'] as Map<String, dynamic>).entries) e.key: nums(e.value)},
      );
      return _ready[kind] = s;
    } catch (_) {
      return null; // no sprites (tests, old content): the lab draws the machine itself
    }
  }
}

/// what a machine shows now, from a Plant or from the panel lab's own machines
class MachineLook {
  final double x, z, door, ext;
  final double angle; // fan blades, degrees
  final int part; // press: 0 none · 1 raw · 2 pressed
  final List<(double, bool)> boxes; // sort: position, metal
  final List<(double, double)> bottles; // fill: position, level
  final bool stream;
  final Map<String, bool> lamps;
  const MachineLook(
      {this.x = 0, this.z = 0, this.door = 1, this.ext = 0, this.angle = 0, this.part = 0, this.boxes = const [], this.bottles = const [], this.stream = false, this.lamps = const {}});

  static MachineLook ofPlant(Plant p, PlantIo? io) {
    bool on(String t) => io != null && io.has(t) && io.on(t);
    bool run(String t) => io != null && io.has(t) && io.motor(t).abs() > 0.01;
    Map<String, bool> lamps(List<String> s, {List<String> v = const [], List<String> m = const []}) => {
          for (final t in s) t: p.sensor(t),
          for (final t in v) t: on(t),
          for (final t in m) t: run(t),
        };
    return switch (p) {
      CartPlant c => MachineLook(x: c.x, lamps: {...lamps(['LS1', 'LS2']), 'RUN': run('M1')}),
      HoistPlant h => MachineLook(z: h.z, lamps: lamps(['B1', 'B2'])),
      LiftPlant l => MachineLook(z: l.z, door: l.door, lamps: {...lamps(['B1', 'B2', 'B3']), 'CAR': true}),
      SortPlant s => MachineLook(ext: s.ext, boxes: [for (final b in s.boxes) (b.s, b.metal)], lamps: lamps(['B1', 'B2', 'B3', 'B4'], v: ['Y1'], m: ['M1'])),
      PressPlant s => MachineLook(ext: s.ext, part: s.part == null ? 0 : (s.part!.pressed ? 2 : 1), lamps: lamps(['B1', 'B2', 'B3'], v: ['Y1'])),
      FillPlant f => MachineLook(
          bottles: [for (final b in f.bottles) (b.s, b.fill)],
          stream: on('Y1') && f.bottles.any((b) => (b.s - FillPlant.nozzle).abs() < 0.03),
          lamps: lamps(['B1', 'B2'], v: ['Y1'], m: ['M1'])),
      BeltPlant b => MachineLook(boxes: [for (final x in b.boxes) (x.s, false)], lamps: {...lamps(['B1']), 'M1': run('M1')}),
      FanPlant f => MachineLook(angle: f.angle, lamps: {'RUN': run('M1')}),
      _ => const MachineLook(),
    };
  }
}

/// draws [s] fitted (contain) into the canvas
class MachineSpritePainter extends CustomPainter {
  final MachineSprite s;
  final MachineLook look;
  final int frame; // repaint key
  final bool background;
  MachineSpritePainter(this.s, this.look, this.frame, {this.background = false});

  static final _img = Paint()..filterQuality = FilterQuality.medium;

  void _layer(Canvas c, String name, Offset by, {double opacity = 1}) {
    final l = s.layers[name];
    if (l == null) return;
    final (r, img) = l;
    final dst = r.shift(by);
    if (opacity < 1) {
      c.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), dst, Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    } else {
      c.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), dst, _img);
    }
  }

  void _rope(Canvas c, Offset a, Offset b, double width) {
    c.drawLine(a, b, Paint()
      ..color = const Color(0xFF2A2F36)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round);
  }

  @override
  void paint(Canvas c, Size size) {
    if (background) {
      final bg = Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF16233F), Color(0xFF0A1122)])
            .createShader(Offset.zero & size);
      c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), bg);
    }
    final k = (size.width / s.w) < (size.height / s.h) ? size.width / s.w : size.height / s.h;
    c.save();
    c.translate((size.width - s.w * k) / 2, (size.height - s.h * k) / 2);
    c.scale(k);
    _layer(c, 'base', Offset.zero);
    final l = look;
    switch (s.kind) {
      case 'cart':
        _layer(c, 'cart', s.dpx(l.x * 2.8, 0, 0));
      case 'hoist':
        final dz = l.z * 0.95;
        final hook = s.points['hook'];
        if (s.points['rope'] != null && hook != null) {
          _rope(c, s.point('rope'), s.px(hook[0], hook[1], hook[2] + dz + 0.12), 5);
        }
        _layer(c, 'hook', s.dpx(0, 0, dz));
      case 'lift':
        final cz = l.z * 5.2;
        _layer(c, 'cw', s.dpx(0, 0, (1 - l.z) * 5.4 + 0.1));
        final rc = s.points['rope_car'];
        if (rc != null) _rope(c, s.px(rc[0], rc[1], rc[2]), s.px(rc[0], rc[1], cz + 2.6), 4);
        final at = s.dpx(0, 0, cz);
        _layer(c, 'car', at);
        if (l.door > 0.02) _layer(c, 'car_open', at, opacity: l.door);
      case 'sort':
        _layer(c, 'rod', s.dpx(0, l.ext * 0.55, 0));
        for (final (pos, metal) in l.boxes) {
          final p0 = s.points[metal ? 'proto_metal' : 'proto_plastic'];
          if (p0 == null) continue;
          _layer(c, metal ? 'metal' : 'plastic', s.dpx(0.11 + pos * (3.2 - 0.22) - p0[0], 0, 0));
        }
      case 'gate':
        _layer(c, 'leaf', s.dpx(-l.x * 2.2, 0, 0));
      case 'belt':
        final p0 = s.points['proto_box'];
        if (p0 != null) {
          // far boxes first, so the nearer ones overlap them
          for (final pos in [for (final b in l.boxes) b.$1]..sort()) {
            _layer(c, 'box', s.dpx(0.25 + pos * 3.85 - p0[0], 0, 0));
          }
        }
      case 'fan':
        // four blades repeat every 90°: the nearest of the six rendered steps of 15°
        final i = ((l.angle % 90) / 15).round() % 6;
        _layer(c, 'blades$i', Offset.zero);
      case 'press':
        if (l.part == 1) _layer(c, 'part_raw', Offset.zero);
        if (l.part == 2) _layer(c, 'part_pressed', Offset.zero);
        _layer(c, 'ram', s.dpx(0, 0, -l.ext * (l.part == 1 ? 0.3 : 0.33)));
      case 'fill':
        final p0 = s.points['proto_bottle'];
        final lo = s.points['liquid_lo'], hi = s.points['liquid_hi'];
        if (p0 != null) {
          for (final (pos, level) in l.bottles) {
            final by = s.dpx(pos * 3.2 - p0[0], 0, 0);
            _layer(c, 'bottle', by);
            final full = s.layers['bottle_full'];
            if (full != null && level > 0.01 && lo != null && hi != null) {
              // the liquid rises from the bottom of its own height
              final zTop = lo[2] + (hi[2] - lo[2]) * level.clamp(0.0, 1.0);
              final y = s.px(lo[0], lo[1], zTop).dy + by.dy;
              final r = full.$1.shift(by);
              c.save();
              c.clipRect(Rect.fromLTRB(r.left - 4, y - 6, r.right + 4, r.bottom + 4));
              _layer(c, 'bottle_full', by);
              c.restore();
            }
          }
        }
        if (l.stream) _layer(c, 'stream', Offset.zero);
    }
    // indicator lamps of the sensors and valves
    for (final e in l.lamps.entries) {
      if (!e.value) continue;
      final at = s.lamps[e.key];
      if (at == null) continue;
      var p = at;
      if (s.kind == 'lift' && e.key == 'CAR') p = at + s.dpx(0, 0, l.z * 5.2);
      final col = e.key.startsWith('Y') || e.key == 'RUN' || e.key == 'M1' ? const Color(0xFFFFB13D) : const Color(0xFF3DFF8A);
      c.drawCircle(p, 22, Paint()
        ..color = col.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      c.drawCircle(p, 7, Paint()..color = col);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant MachineSpritePainter old) => old.frame != frame || old.s != s || old.look != look;
}

/// the flat view of a machine: its Blender sprites when they have loaded, otherwise
/// the drawn isometric scene
CustomPainter machineFlatPainter(Plant p, PlantIo? io, int frame) {
  final s = MachineSprites.of(p.key);
  if (s == null) {
    MachineSprites.load(p.key);
    return PlantPainter(p, io, frame);
  }
  return MachineSpritePainter(s, MachineLook.ofPlant(p, io), frame, background: true);
}
