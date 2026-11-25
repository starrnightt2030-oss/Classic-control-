// Pseudo-3D (isometric) scenes of the machines in lib/sim/plant.dart. Every part
// is a shaded box or cylinder seen from the front-left, so the scene reads as a
// small model on a work bench: rails, a hoist gantry, a lift shaft, belts with
// moving slats, a pneumatic cylinder and a filling nozzle.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sim/plant.dart';

class PlantPainter extends CustomPainter {
  final Plant p;

  /// the running circuit (null when the simulation is off)
  final PlantIo? io;
  final int frame; // repaint key
  PlantPainter(this.p, this.io, this.frame);

  @override
  void paint(Canvas c, Size size) {
    final bg = Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF16233F), Color(0xFF0A1122)]).createShader(Offset.zero & size);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), bg);
    switch (p) {
      case final CartPlant x:
        _cart(c, size, x);
      case final HoistPlant x:
        _hoist(c, size, x);
      case final LiftPlant x:
        _lift(c, size, x);
      case final SortPlant x:
        _sort(c, size, x);
      case final PressPlant x:
        _press(c, size, x);
      case final FillPlant x:
        _fill(c, size, x);
    }
  }

  double _m(String tag) => io?.motor(tag) ?? 0;
  bool _on(String tag) => io?.on(tag) ?? false;

  // ------------------------------------------------------------------ scenes
  void _cart(Canvas c, Size size, CartPlant pl) {
    final v = _Iso.fit(c, size, 12, 4, 3.2);
    v.floor(12, 4);
    // sleepers and rails
    for (var i = 0.0; i <= 11.5; i += 0.9) {
      v.box(i + 0.2, 1.0, 0, 0.35, 2.0, 0.12, const Color(0xFF6B4B2E));
    }
    for (final y in [1.25, 2.55]) {
      v.box(0.2, y, 0.12, 11.6, 0.18, 0.14, const Color(0xFF9AA6B8));
    }
    // limit switches with their levers
    _limitPost(v, 0.25, 0.25, p.sensor('LS1'), 'LS1');
    _limitPost(v, 11.2, 0.25, p.sensor('LS2'), 'LS2');
    // the cart
    final x = 0.6 + pl.x * 8.4;
    final run = _m('M1');
    v.shadow(x, 1.0, 2.6, 2.0);
    for (final wx in [x + 0.45, x + 2.1]) {
      for (final wy in [1.2, 2.5]) {
        v.wheel(wx, wy, 0.42, 0.28, pl.x * 40);
      }
    }
    v.box(x, 1.0, 0.45, 2.6, 2.0, 0.55, const Color(0xFFF5B83D));
    v.box(x + 0.25, 1.25, 1.0, 2.1, 1.5, 0.9, const Color(0xFF4FA3FF));
    v.box(x + 0.25, 1.25, 1.9, 2.1, 1.5, 0.08, const Color(0xFF2E6FD0));
    v.beacon(x + 1.3, 2.0, 1.98, run.abs() > 0.05 ? const Color(0xFFFFB020) : const Color(0xFF3A4660), blink: run.abs() > 0.05 && (pl.t * 3).floor().isEven);
    v.label(x + 1.3, 2.0, 2.6, run > 0.05 ? 'M1 يمين' : (run < -0.05 ? 'M1 شمال' : 'M1'));
  }

  void _hoist(Canvas c, Size size, HoistPlant pl) {
    final v = _Iso.fit(c, size, 7, 4, 8.5);
    v.floor(7, 4);
    const steel = Color(0xFFF5B83D);
    v.box(0.6, 1.2, 0, 0.45, 0.45, 7.6, steel);
    v.box(5.9, 1.2, 0, 0.45, 0.45, 7.6, steel);
    v.box(0.6, 1.2, 7.6, 5.75, 0.45, 0.5, steel);
    // drum and motor on the beam
    final run = _m('M1');
    v.box(2.4, 0.9, 8.1, 1.8, 1.0, 0.7, const Color(0xFF3D4B66));
    v.box(4.3, 1.0, 8.15, 0.9, 0.8, 0.6, run.abs() > 0.05 ? const Color(0xFF35E08A) : const Color(0xFF5A6A88));
    final z = 0.6 + pl.z * 5.6;
    final hook = v.p(3.3, 1.42, z + 1.25), top = v.p(3.3, 1.42, 8.1);
    c.drawLine(
        top,
        hook,
        Paint()
          ..color = const Color(0xFFD8DEE8)
          ..strokeWidth = 1.6);
    v.shadow(2.6, 0.9, 1.5, 1.1);
    v.box(2.6, 0.9, z, 1.4, 1.1, 1.1, const Color(0xFF8E6A3E));
    v.box(3.15, 1.3, z + 1.1, 0.3, 0.3, 0.15, const Color(0xFFB0B8C8));
    // limit switches on the right post
    _limitPost(v, 6.45, 1.2, p.sensor('B1'), 'B1', z: 0.5);
    _limitPost(v, 6.45, 1.2, p.sensor('B2'), 'B2', z: 6.6);
    v.label(4.7, 1.3, 9.2, run > 0.05 ? 'M1 رفع' : (run < -0.05 ? 'M1 تنزيل' : 'M1'));
  }

  void _lift(Canvas c, Size size, LiftPlant pl) {
    final v = _Iso.fit(c, size, 7, 4, 10);
    v.floor(7, 4);
    const frame = Color(0xFF8798BF);
    for (final (x, y) in [(0.8, 0.6), (5.2, 0.6)]) {
      v.box(x, y, 0, 0.18, 0.18, 9.6, frame);
    }
    final z = pl.z * 8.4;
    v.box(1.1, 0.9, z, 4.0, 2.4, 0.2, const Color(0xFF3D4B66));
    v.box(1.1, 0.9, z + 0.2, 0.15, 2.4, 2.6, const Color(0xFFC9D3E6));
    v.box(1.1, 0.9, z + 0.2, 4.0, 0.15, 2.6, const Color(0xFFC9D3E6));
    v.box(1.1, 0.9, z + 2.8, 4.0, 2.4, 0.25, const Color(0xFF3D4B66));
    // two door leaves slide apart when the car stands at a floor
    final open = pl.door * 0.95;
    v.box(1.25 + 0.0 - open, 3.15, z + 0.2, 1.9, 0.12, 2.6, const Color(0xFFB8C2D6));
    v.box(3.15 + open, 3.15, z + 0.2, 1.9, 0.12, 2.6, const Color(0xFFA9B4CA));
    c.drawLine(
        v.p(3.1, 2.1, z + 3.05),
        v.p(3.1, 2.1, 10),
        Paint()
          ..color = const Color(0xFFD8DEE8)
          ..strokeWidth = 1.2);
    for (final (x, y) in [(0.8, 3.2), (5.2, 3.2)]) {
      v.box(x, y, 0, 0.18, 0.18, 9.6, frame);
    }
    for (var f = 0; f < 3; f++) {
      final fz = f * 4.2;
      v.box(0.2, 3.4, fz, 6.4, 0.5, 0.25, const Color(0xFF55627E));
      final s = p.sensor('B${f + 1}');
      v.beacon(5.9, 3.65, fz + 0.25, s ? const Color(0xFF35E08A) : const Color(0xFF34405A));
      v.label(6.4, 3.65, fz + 0.9, 'B${f + 1}');
    }
    final run = _m('M1');
    v.box(2.4, 1.4, 9.6, 1.4, 1.2, 0.6, run.abs() > 0.05 ? const Color(0xFF35E08A) : const Color(0xFF5A6A88));
    v.label(3.1, 2.0, 10.9, ['الأرضي', 'الأول', 'التاني'][pl.floor] + (run > 0.05 ? ' · طالع' : (run < -0.05 ? ' · نازل' : '')));
  }

  void _sort(Canvas c, Size size, SortPlant pl) {
    final v = _Iso.fit(c, size, 13, 5.5, 3.4);
    v.floor(13, 5.5);
    const len = 11.0, x0 = 0.6, y0 = 2.0, h = 1.2;
    // bin for metal on the far side of the pusher
    final px = x0 + SortPlant.sensorAt * len;
    v.box(px - 0.9, 0.2, 0, 1.8, 1.5, 0.9, const Color(0xFF3A6EA5));
    _belt(v, x0, y0, len, 1.6, h, pl.belt, _m('M1'));
    // boxes on the belt
    for (final b in pl.boxes) {
      final bx = x0 + b.s * len - 0.45;
      v.box(bx, y0 + 0.35, h, 0.9, 0.9, 0.8, b.metal ? const Color(0xFFB7C0CE) : const Color(0xFFE2873B));
    }
    // inductive sensor and the photo cell at the end
    final b2 = p.sensor('B2');
    v.box(px - 0.15, y0 - 0.45, h, 0.3, 0.3, 0.55, const Color(0xFF3D4B66));
    v.beacon(px, y0 - 0.3, h + 0.55, b2 ? const Color(0xFFFFB020) : const Color(0xFF34405A));
    final b1 = p.sensor('B1');
    v.box(x0 + len - 0.35, y0 + 1.7, h, 0.3, 0.3, 1.1, const Color(0xFF3D4B66));
    if (b1) {
      c.drawLine(
          v.p(x0 + len - 0.2, y0 + 1.7, h + 0.7),
          v.p(x0 + len - 0.2, y0 - 0.1, h + 0.7),
          Paint()
            ..color = const Color(0xAAFF5A64)
            ..strokeWidth = 2);
    }
    // the pneumatic pusher on the near side
    final ext = pl.ext;
    v.box(px - 0.45, y0 + 2.4, h - 0.1, 0.9, 1.8, 0.7, const Color(0xFFC9D3E6));
    v.box(px - 0.12, y0 + 1.6 - ext * 1.4, h + 0.15, 0.24, 0.8 + ext * 1.4, 0.24, const Color(0xFFE8ECF4));
    v.box(px - 0.5, y0 + 1.5 - ext * 1.4, h + 0.05, 1.0, 0.12, 0.5, const Color(0xFF5A6A88));
    v.beacon(px + 0.6, y0 + 3.3, h + 0.6, _on('Y1') ? const Color(0xFF35E08A) : const Color(0xFF34405A));
    v.label(px + 0.6, y0 + 3.3, h + 1.2, 'Y1');
  }

  void _press(Canvas c, Size size, PressPlant pl) {
    final v = _Iso.fit(c, size, 7, 5, 8);
    v.floor(7, 5);
    const body = Color(0xFF3A6EA5);
    v.box(1.0, 1.0, 0, 5.0, 3.0, 1.0, body);
    v.box(1.2, 1.2, 1.0, 0.6, 0.6, 5.6, body);
    v.box(5.2, 1.2, 1.0, 0.6, 0.6, 5.6, body);
    v.box(1.0, 1.0, 6.6, 5.0, 1.0, 0.8, body);
    v.box(2.5, 2.0, 1.0, 2.0, 1.6, 0.35, const Color(0xFF5A6A88)); // die
    final part = pl.part;
    if (part != null) {
      final th = part.pressed ? 0.18 : 0.55;
      v.box(2.9, 2.35, 1.35, 1.2, 0.9, th, part.pressed ? const Color(0xFFC0C8D6) : const Color(0xFFE2873B));
    }
    // cylinder and ram
    v.box(2.85, 1.25, 7.4, 1.3, 1.3, 0.25, const Color(0xFF8798BF));
    v.cylinder(3.5, 1.9, 7.6, 0.6, 1.6, const Color(0xFFDDE3EE));
    final drop = pl.ext * (part != null ? 3.6 : 3.9);
    v.box(3.32, 1.72, 5.6 - drop, 0.36, 0.36, 1.8 + drop, const Color(0xFFE8ECF4));
    v.box(2.6, 1.55, 5.2 - drop, 1.8, 1.6, 0.4, const Color(0xFF8E9AB2));
    // reed switches on the cylinder, photo cell at the die
    v.beacon(4.3, 1.4, 8.6, p.sensor('B1') ? const Color(0xFF35E08A) : const Color(0xFF34405A));
    v.label(4.9, 1.4, 8.8, 'B1');
    v.beacon(4.3, 1.4, 7.7, p.sensor('B2') ? const Color(0xFF35E08A) : const Color(0xFF34405A));
    v.label(4.9, 1.4, 7.9, 'B2');
    v.box(5.0, 3.6, 1.0, 0.3, 0.3, 0.8, const Color(0xFF3D4B66));
    v.beacon(5.15, 3.75, 1.8, p.sensor('B3') ? const Color(0xFFFFB020) : const Color(0xFF34405A));
    v.label(5.6, 3.8, 2.3, 'B3');
    v.beacon(1.6, 3.9, 1.0, _on('Y1') ? const Color(0xFF35E08A) : const Color(0xFF34405A));
    v.label(1.6, 3.9, 1.6, 'Y1');
  }

  void _fill(Canvas c, Size size, FillPlant pl) {
    final v = _Iso.fit(c, size, 13, 5, 5.5);
    v.floor(13, 5);
    const len = 11.0, x0 = 0.6, y0 = 1.8, h = 1.2;
    _belt(v, x0, y0, len, 1.4, h, pl.belt, _m('M1'));
    final nx = x0 + FillPlant.nozzle * len;
    // tank and nozzle
    v.box(nx - 0.8, y0 - 1.4, 3.4, 1.6, 1.2, 1.6, const Color(0xFF3A6EA5));
    v.box(nx - 0.15, y0 + 0.55, 3.55, 0.3, 0.3, 0.35, const Color(0xFFB0B8C8));
    v.box(nx - 0.1, y0 - 0.3, 3.75, 0.2, 1.0, 0.18, const Color(0xFFB0B8C8));
    final flowing = _on('Y1');
    if (flowing) {
      final a = v.p(nx, y0 + 0.7, 3.55), b = v.p(nx, y0 + 0.7, h + 0.4);
      c.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xCC4FD8FF)
            ..strokeWidth = 3);
    }
    for (final b in pl.bottles) {
      final bx = x0 + b.s * len;
      v.bottle(bx, y0 + 0.7, h, 0.35, 1.5, b.fill);
    }
    // photo cell and level probe
    v.box(nx - 0.15, y0 + 1.6, h, 0.3, 0.3, 0.9, const Color(0xFF3D4B66));
    v.beacon(nx, y0 + 1.75, h + 0.9, p.sensor('B1') ? const Color(0xFFFFB020) : const Color(0xFF34405A));
    v.label(nx + 0.6, y0 + 1.75, h + 1.5, 'B1');
    v.beacon(nx + 0.6, y0 + 0.4, 3.55, p.sensor('B2') ? const Color(0xFF35E08A) : const Color(0xFF34405A));
    v.label(nx + 1.2, y0 + 0.4, 4.1, 'B2');
    v.label(nx - 0.4, y0 - 0.8, 5.4, flowing ? 'Y1 مفتوح' : 'Y1');
  }

  // ----------------------------------------------------------------- pieces
  void _belt(_Iso v, double x0, double y0, double len, double w, double h, double travel, double run) {
    for (final lx in [x0 + 0.4, x0 + len - 0.7]) {
      v.box(lx, y0 + 0.1, 0, 0.3, 0.25, h - 0.2, const Color(0xFF55627E));
      v.box(lx, y0 + w - 0.35, 0, 0.3, 0.25, h - 0.2, const Color(0xFF55627E));
    }
    v.box(x0, y0, h - 0.25, len, w, 0.2, const Color(0xFF8798BF));
    v.box(x0, y0, h - 0.05, len, w, 0.05, const Color(0xFF1E2636));
    // slats move with the belt
    final off = (travel * len) % 0.8;
    final slat = Paint()
      ..color = const Color(0xFF39445C)
      ..strokeWidth = 1.2;
    for (var x = x0 + off; x < x0 + len; x += 0.8) {
      v.c.drawLine(v.p(x, y0, h), v.p(x, y0 + w, h), slat);
    }
    // drive motor
    v.box(x0 + len - 0.6, y0 + w, h - 0.75, 0.8, 0.7, 0.7, run.abs() > 0.05 ? const Color(0xFF35E08A) : const Color(0xFF5A6A88));
    v.label(x0 + len - 0.2, y0 + w + 0.35, h + 0.4, 'M1');
  }

  void _limitPost(_Iso v, double x, double y, bool on, String tag, {double z = 0}) {
    v.box(x, y, z, 0.35, 0.35, 0.7, const Color(0xFF3D4B66));
    v.box(x + 0.05, y + 0.05, z + 0.7, 0.25, 0.25, 0.2, on ? const Color(0xFFFF5A64) : const Color(0xFFE8ECF4));
    v.label(x + 0.2, y + 0.2, z + 1.4, tag);
  }

  @override
  bool shouldRepaint(covariant PlantPainter old) => old.frame != frame || old.p != p;
}

/// isometric view: world x to the right-down, y to the left-down, z up
class _Iso {
  final Canvas c;
  final Offset o;
  final double k;
  _Iso(this.c, this.o, this.k);

  /// scale and centre a world of wx × wy × wz in the canvas
  factory _Iso.fit(Canvas c, Size size, double wx, double wy, double wz) {
    const cs = 0.866, sn = 0.5;
    final k = math.min((size.width - 20) / ((wx + wy) * cs), (size.height - 26) / ((wx + wy) * sn + wz));
    final w = (wx + wy) * cs * k, h = ((wx + wy) * sn + wz) * k;
    final left = (size.width - w) / 2, top = (size.height - h) / 2 + 6;
    return _Iso(c, Offset(left + wy * cs * k, top + wz * k), k);
  }

  Offset p(double x, double y, double z) => o + Offset((x - y) * 0.866 * k, (x + y) * 0.5 * k - z * k);

  void _poly(List<Offset> pts, Color col) {
    final path = Path()..addPolygon(pts, true);
    c.drawPath(path, Paint()..color = col);
    c.drawPath(
        path,
        Paint()
          ..color = const Color(0x33000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6);
  }

  void floor(double wx, double wy) {
    _poly([p(0, 0, 0), p(wx, 0, 0), p(wx, wy, 0), p(0, wy, 0)], const Color(0xFF1C2944));
    final g = Paint()
      ..color = const Color(0x22A9C8FF)
      ..strokeWidth = 0.6;
    for (var x = 1.0; x < wx; x++) {
      c.drawLine(p(x, 0, 0), p(x, wy, 0), g);
    }
    for (var y = 1.0; y < wy; y++) {
      c.drawLine(p(0, y, 0), p(wx, y, 0), g);
    }
  }

  void shadow(double x, double y, double w, double d) =>
      _poly([p(x - 0.1, y - 0.1, 0), p(x + w + 0.3, y - 0.1, 0), p(x + w + 0.3, y + d + 0.3, 0), p(x - 0.1, y + d + 0.3, 0)], const Color(0x55000000));

  void box(double x, double y, double z, double w, double d, double h, Color col) {
    _poly([p(x + w, y, z), p(x + w, y + d, z), p(x + w, y + d, z + h), p(x + w, y, z + h)], Color.lerp(col, Colors.black, 0.32)!);
    _poly([p(x, y + d, z), p(x + w, y + d, z), p(x + w, y + d, z + h), p(x, y + d, z + h)], Color.lerp(col, Colors.black, 0.12)!);
    _poly([p(x, y, z + h), p(x + w, y, z + h), p(x + w, y + d, z + h), p(x, y + d, z + h)], Color.lerp(col, Colors.white, 0.18)!);
  }

  /// upright cylinder standing on z (radius r, height h)
  void cylinder(double x, double y, double z, double r, double h, Color col) {
    final b = p(x, y, z), t = p(x, y, z + h);
    final rx = r * k * 1.22, ry = r * k * 0.7;
    final body = Rect.fromLTRB(b.dx - rx, t.dy, b.dx + rx, b.dy);
    c.drawOval(Rect.fromCenter(center: b, width: rx * 2, height: ry * 2), Paint()..color = Color.lerp(col, Colors.black, 0.3)!);
    c.drawRect(
        body,
        Paint()
          ..shader =
              LinearGradient(colors: [Color.lerp(col, Colors.black, 0.35)!, Color.lerp(col, Colors.white, 0.25)!, Color.lerp(col, Colors.black, 0.2)!], stops: const [0, 0.35, 1]).createShader(body));
    c.drawOval(Rect.fromCenter(center: t, width: rx * 2, height: ry * 2), Paint()..color = Color.lerp(col, Colors.white, 0.2)!);
  }

  void bottle(double x, double y, double z, double r, double h, double fill) {
    final b = p(x, y, z), t = p(x, y, z + h);
    final rx = r * k * 1.22, ry = r * k * 0.7;
    final glass = Rect.fromLTRB(b.dx - rx, t.dy, b.dx + rx, b.dy);
    final lvl = b.dy - (b.dy - t.dy) * fill.clamp(0.0, 1.0);
    c.drawRRect(RRect.fromRectAndRadius(glass, Radius.circular(rx * 0.6)), Paint()..color = const Color(0x66C9E8FF));
    if (fill > 0.01) {
      c.drawRRect(RRect.fromLTRBAndCorners(glass.left + 1, lvl, glass.right - 1, b.dy, bottomLeft: Radius.circular(rx * 0.6), bottomRight: Radius.circular(rx * 0.6)),
          Paint()..color = const Color(0xDD2E9BFF));
    }
    c.drawRect(Rect.fromLTRB(t.dx - rx * 0.4, t.dy - ry * 1.6, t.dx + rx * 0.4, t.dy + 1), Paint()..color = const Color(0x88C9E8FF));
    c.drawRect(Rect.fromLTRB(t.dx - rx * 0.45, t.dy - ry * 2.0, t.dx + rx * 0.45, t.dy - ry * 1.4), Paint()..color = const Color(0xFFFF5A64));
    c.drawOval(
        Rect.fromCenter(center: b, width: rx * 2, height: ry * 2),
        Paint()
          ..color = const Color(0x44FFFFFF)
          ..style = PaintingStyle.stroke);
  }

  /// a wheel seen from the side, its spokes turned by [ang] radians
  void wheel(double x, double y, double z, double r, double ang) {
    final cpos = p(x, y + 0.1, z);
    final rr = r * k;
    c.drawOval(Rect.fromCenter(center: cpos, width: rr * 1.7, height: rr * 2), Paint()..color = const Color(0xFF20262F));
    final sp = Paint()
      ..color = const Color(0xFF8A94A6)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final a = ang + i * math.pi / 3;
      c.drawLine(cpos + Offset(math.cos(a) * rr * 0.8, math.sin(a) * rr * 0.95), cpos - Offset(math.cos(a) * rr * 0.8, math.sin(a) * rr * 0.95), sp);
    }
  }

  void beacon(double x, double y, double z, Color col, {bool blink = true}) {
    final q = p(x, y, z);
    final lit = col.computeLuminance() > 0.1 && blink;
    if (lit) c.drawCircle(q, k * 0.45, Paint()..color = col.withValues(alpha: 0.28));
    c.drawCircle(q, k * 0.2, Paint()..color = lit ? col : Color.lerp(col, Colors.black, 0.3)!);
  }

  void label(double x, double y, double z, String t) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: const TextStyle(color: Color(0xFFEAF1FF), fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3)])),
      textDirection: TextDirection.rtl,
    )..layout();
    final q = p(x, y, z);
    tp.paint(c, q - Offset(tp.width / 2, tp.height / 2));
  }
}
