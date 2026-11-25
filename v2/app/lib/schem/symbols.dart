// Schematic simulator: IEC 60617 style symbols drawn on a grid.
// Every symbol is defined in grid units (one unit = [kG] px on the sheet).
// Current flows top → bottom: pins on row 0 leave upward, the others downward.
import 'dart:math' as math;

import 'package:flutter/material.dart';

const double kG = 20; // px per grid unit

class SymPin {
  final String id; // pin name on the sheet (engine terminal for most symbols)
  final double x, y; // grid units
  final String label; // printed number
  const SymPin(this.id, this.x, this.y, [this.label = '']);
  bool get up => y == 0;
}

/// how a symbol becomes part of the simulation
enum SymRole {
  source, // L1 L2 L3 N PE → the hidden mains supply
  device, // a stand-alone engine device (breaker, button, lamp, motor…)
  host, // a coil or overload heater: the engine device is named by the tag
  hostPart, // main contacts of a contactor: terminals of the tag's device
  contact, // an auxiliary contact following the tag's device
}

class SymDef {
  final String key, nameAr, category, prefix;
  final double w, h;
  final List<SymPin> pins;
  final SymRole role;
  final String engine; // engine type (device / host)
  /// contact kind for [SymRole.contact]: NO · NC · TNO · TNC · OLNO · OLNC
  final String kind;
  final Map<String, Object?> params;
  const SymDef({
    required this.key,
    required this.nameAr,
    required this.category,
    required this.prefix,
    required this.w,
    required this.h,
    required this.pins,
    required this.role,
    this.engine = '',
    this.kind = '',
    this.params = const {},
  });
}

const _two = [SymPin('1', 1, 0), SymPin('2', 1, 4)];

const kSymCategories = <(String, int, List<String>)>[
  ('التغذية', 0xFF35E08A, ['L1', 'L2', 'L3', 'N', 'PE']),
  ('الحماية', 0xFFFF5A64, ['mcb1', 'mcb3', 'fuse', 'ol3', 'olnc', 'olno']),
  ('الكونتاكتور والمرحل', 0xFF4FD8FF, ['coil_kc', 'kc3', 'no', 'nc', 'coil_ka']),
  ('المؤقتات', 0xFF3D8BFF, ['coil_kt', 'tno', 'tnc']),
  ('أوامر التشغيل', 0xFFB07CFF, ['pb_no', 'pb_nc', 'estop', 'sel']),
  ('الأحمال', 0xFFC9A27E, ['lamp', 'motor3', 'motor6']),
];

/// phase sources feed downwards; N and PE close the circuit from below
SymDef _src(String k) => SymDef(
    key: k,
    nameAr: k == 'N' ? 'خط التعادل N' : (k == 'PE' ? 'خط الأرضي PE' : 'خط الطور $k'),
    category: 'التغذية',
    prefix: k,
    w: 2,
    h: 2,
    pins: [k == 'N' || k == 'PE' ? const SymPin('o', 1, 0) : const SymPin('o', 1, 2)],
    role: SymRole.source,
    engine: 'sup');

final Map<String, SymDef> kSyms = {
  for (final d in <SymDef>[
    _src('L1'),
    _src('L2'),
    _src('L3'),
    _src('N'),
    _src('PE'),
    const SymDef(key: 'mcb1', nameAr: 'قاطع آلي قطب واحد', category: 'الحماية', prefix: 'F', w: 2, h: 4, pins: [SymPin('1', 1, 0, '1'), SymPin('2', 1, 4, '2')], role: SymRole.device, engine: 'mcb1'),
    const SymDef(
        key: 'mcb3', nameAr: 'قاطع آلي ثلاثي الأقطاب', category: 'الحماية', prefix: 'Q', w: 6, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6')],
        role: SymRole.device, engine: 'mcb3'),
    const SymDef(key: 'fuse', nameAr: 'مصهر', category: 'الحماية', prefix: 'F', w: 2, h: 4, pins: [SymPin('1', 1, 0, '1'), SymPin('2', 1, 4, '2')], role: SymRole.device, engine: 'fuse'),
    const SymDef(
        key: 'ol3', nameAr: 'عناصر الأوفرلود الحراري', category: 'الحماية', prefix: 'F', w: 6, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6')],
        role: SymRole.host, engine: 'ol', params: {'set': 8.5}),
    const SymDef(key: 'olnc', nameAr: 'تلامس الأوفرلود المغلق 95-96', category: 'الحماية', prefix: 'F', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'OLNC'),
    const SymDef(key: 'olno', nameAr: 'تلامس الأوفرلود المفتوح 97-98', category: 'الحماية', prefix: 'F', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'OLNO'),
    const SymDef(
        key: 'coil_kc', nameAr: 'ملف كونتاكتور', category: 'الكونتاكتور والمرحل', prefix: 'K', w: 4, h: 4,
        pins: [SymPin('A1', 2, 0, 'A1'), SymPin('A2', 2, 4, 'A2')], role: SymRole.host, engine: 'kc', params: {'coilV': 220.0}),
    const SymDef(
        key: 'kc3', nameAr: 'تلامسات القوى للكونتاكتور', category: 'الكونتاكتور والمرحل', prefix: 'K', w: 6, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6')],
        role: SymRole.hostPart, engine: 'kc'),
    const SymDef(key: 'no', nameAr: 'تلامس مساعد مفتوح NO', category: 'الكونتاكتور والمرحل', prefix: 'K', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'NO'),
    const SymDef(key: 'nc', nameAr: 'تلامس مساعد مغلق NC', category: 'الكونتاكتور والمرحل', prefix: 'K', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'NC'),
    const SymDef(
        key: 'coil_ka', nameAr: 'ملف مرحّل مساعد', category: 'الكونتاكتور والمرحل', prefix: 'KA', w: 4, h: 4,
        pins: [SymPin('A1', 2, 0, 'A1'), SymPin('A2', 2, 4, 'A2')], role: SymRole.host, engine: 'relay', params: {'coilV': 220.0}),
    const SymDef(
        key: 'coil_kt', nameAr: 'ملف مؤقت زمني', category: 'المؤقتات', prefix: 'KT', w: 4, h: 4,
        pins: [SymPin('A1', 2, 0, 'A1'), SymPin('A2', 2, 4, 'A2')], role: SymRole.host, engine: 'timer', params: {'mode': 'on', 'T': 5.0}),
    const SymDef(key: 'tno', nameAr: 'تلامس زمني مفتوح', category: 'المؤقتات', prefix: 'KT', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'TNO'),
    const SymDef(key: 'tnc', nameAr: 'تلامس زمني مغلق', category: 'المؤقتات', prefix: 'KT', w: 2, h: 4, pins: _two, role: SymRole.contact, kind: 'TNC'),
    const SymDef(key: 'pb_no', nameAr: 'ضاغط تشغيل NO', category: 'أوامر التشغيل', prefix: 'S', w: 2, h: 4, pins: [SymPin('13', 1, 0, '13'), SymPin('14', 1, 4, '14')], role: SymRole.device, engine: 'pb_no'),
    const SymDef(key: 'pb_nc', nameAr: 'ضاغط إيقاف NC', category: 'أوامر التشغيل', prefix: 'S', w: 2, h: 4, pins: [SymPin('11', 1, 0, '11'), SymPin('12', 1, 4, '12')], role: SymRole.device, engine: 'pb_nc'),
    const SymDef(key: 'estop', nameAr: 'مفتاح طوارئ', category: 'أوامر التشغيل', prefix: 'S', w: 2, h: 4, pins: [SymPin('11', 1, 0, '11'), SymPin('12', 1, 4, '12')], role: SymRole.device, engine: 'estop'),
    const SymDef(key: 'sel', nameAr: 'مفتاح اختيار', category: 'أوامر التشغيل', prefix: 'S', w: 2, h: 4, pins: [SymPin('13', 1, 0, '13'), SymPin('14', 1, 4, '14')], role: SymRole.device, engine: 'sel'),
    const SymDef(
        key: 'lamp', nameAr: 'لمبة بيان', category: 'الأحمال', prefix: 'H', w: 2, h: 4, pins: [SymPin('X1', 1, 0, 'X1'), SymPin('X2', 1, 4, 'X2')], role: SymRole.device, engine: 'lamp',
        params: {'col': 'g', 'V': 220.0}),
    const SymDef(
        key: 'motor3', nameAr: 'محرك ثلاثي الأطوار (دلتا داخلية)', category: 'الأحمال', prefix: 'M', w: 6, h: 6,
        pins: [SymPin('U1', 1, 0, 'U1'), SymPin('V1', 3, 0, 'V1'), SymPin('W1', 5, 0, 'W1')], role: SymRole.device, engine: 'motor', params: {'links': 'delta', 'In': 8.5}),
    const SymDef(
        key: 'motor6', nameAr: 'محرك بستة أطراف (ستار دلتا)', category: 'الأحمال', prefix: 'M', w: 6, h: 6,
        pins: [SymPin('U1', 1, 0, 'U1'), SymPin('V1', 3, 0, 'V1'), SymPin('W1', 5, 0, 'W1'), SymPin('W2', 1, 6, 'W2'), SymPin('U2', 3, 6, 'U2'), SymPin('V2', 5, 6, 'V2')],
        role: SymRole.device, engine: 'motor', params: {'links': 'none', 'In': 8.5}),
  ])
    d.key: d
};

/// live look of a symbol while simulating
class SymLook {
  final bool closed; // contact / breaker position
  final bool energised; // coil pulled in · lamp lit · motor running
  final bool fault; // tripped · burnt · humming
  final double angle; // motor rotor angle (deg)
  final String? note; // short text under the symbol (time, current…)
  const SymLook({this.closed = false, this.energised = false, this.fault = false, this.angle = 0, this.note});
}

const kInk = Color(0xFF1B2330);
const kOn = Color(0xFF0E9F5A);
const kBad = Color(0xFFD7263D);

Color lampColor(Object? c) => switch (c) { 'r' => const Color(0xFFFF3B30), 'y' => const Color(0xFFFFB300), 'b' => const Color(0xFF2F7FE0), 'w' => const Color(0xFFE8E8E8), _ => const Color(0xFF22C55E) };

/// Draws [d] with its top-left at the canvas origin.
/// [look] is null in edit mode (normal position).
void paintSymbol(Canvas c, SymDef d, {SymLook? look, String tag = '', Map<String, Object?> p = const {}, Color ink = kInk, bool labels = true, String contactNo = ''}) {
  const g = kG;
  final pen = Paint()
    ..color = ink
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final live = look != null;
  final on = look?.energised ?? false;
  final bad = look?.fault ?? false;
  final act = Paint()
    ..color = bad ? kBad : (on ? kOn : ink)
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  void l(double x1, double y1, double x2, double y2, [Paint? pt]) => c.drawLine(Offset(x1 * g, y1 * g), Offset(x2 * g, y2 * g), pt ?? pen);
  void dashed(double x1, double y1, double x2, double y2) {
    final a = Offset(x1 * g, y1 * g), b = Offset(x2 * g, y2 * g);
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (var t = 0.0; t < len; t += 7) {
      c.drawLine(a + dir * t, a + dir * math.min(t + 4, len), pen..strokeWidth = 1.4);
    }
    pen.strokeWidth = 2;
  }

  void text(String s, Offset at, {double size = 10, Color? col, bool bold = false, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: col ?? ink, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontFamily: 'JetBrainsMono', height: 1)),
        textDirection: TextDirection.ltr)
      ..layout();
    final dx = align == TextAlign.right ? -tp.width : (align == TextAlign.center ? -tp.width / 2 : 0.0);
    tp.paint(c, at + Offset(dx, -tp.height / 2));
  }

  /// one switching contact on column [x] (grid), terminals at rows 0 and [h]
  /// no: normally open · closed: drawn closed
  void contact(double x, bool no, bool closed, {bool arcTop = false, bool delay = false, bool breaker = false}) {
    const top = 1.3, bot = 2.7;
    l(x, 0, x, top);
    l(x, bot, x, 4);
    if (!no) l(x, top, x + 0.55, top); // NC stop
    if (arcTop) c.drawArc(Rect.fromCircle(center: Offset((x - 0.0) * g, (top - 0.18) * g), radius: 0.22 * g), 0, math.pi, false, pen);
    if (breaker) {
      l(x - 0.25, top - 0.25, x + 0.25, top + 0.25);
      l(x - 0.25, top + 0.25, x + 0.25, top - 0.25);
    }
    // moving blade, pivoting at the lower terminal
    final Offset end;
    if (no) {
      end = closed ? Offset(x, top) : Offset(x - 0.7, top + 0.15);
    } else {
      end = closed ? Offset(x + 0.6, top - 0.15) : Offset(x - 0.7, top + 0.15);
    }
    final bp = live ? (Paint()
      ..color = closed ? kOn : ink
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round) : pen;
    l(x, bot, end.dx, end.dy, bp);
    if (delay) {
      // on-delay "parachute" on the blade
      final m = Offset((x + end.dx) / 2, (bot + end.dy) / 2);
      l(m.dx, m.dy, m.dx - 0.75, m.dy);
      c.drawArc(Rect.fromCircle(center: Offset((m.dx - 0.95) * g, m.dy * g), radius: 0.28 * g), -math.pi / 2, math.pi, false, pen);
    }
  }

  Offset bladeMid(double x, bool no, bool closed) {
    const top = 1.3, bot = 2.7;
    final end = no ? (closed ? Offset(x, top) : Offset(x - 0.7, top + 0.15)) : (closed ? Offset(x + 0.6, top - 0.15) : Offset(x - 0.7, top + 0.15));
    return Offset((x + end.dx) / 2, (bot + end.dy) / 2);
  }

  void tagText({double y = 2, double x = -0.25}) {
    if (!labels || tag.isEmpty) return;
    text('-$tag', Offset(x * g, y * g), size: 11.5, bold: true, align: TextAlign.right, col: ink);
  }

  void pinLabels() {
    if (!labels) return;
    for (final pn in d.pins) {
      if (pn.label.isEmpty) continue;
      text(pn.label, Offset((pn.x + 0.18) * g, (pn.up ? 0.55 : pn.y - 0.55) * g), size: 8.5, col: const Color(0xFF5A6578));
    }
  }

  switch (d.key) {
    case 'L1':
    case 'L2':
    case 'L3':
    case 'N':
    case 'PE':
      final col = switch (d.key) { 'L1' => const Color(0xFF8D5A3B), 'L2' => const Color(0xFF262A30), 'L3' => const Color(0xFF7D858C), 'N' => const Color(0xFF2F7FE0), _ => const Color(0xFF2EAA4A) };
      final low = d.key == 'N' || d.key == 'PE';
      final cy = low ? 1.25 : 0.75;
      c.drawCircle(Offset(1 * g, cy * g), 0.28 * g, Paint()..color = live ? col : Colors.white);
      c.drawCircle(Offset(1 * g, cy * g), 0.28 * g, pen);
      if (low) {
        l(1, 0, 1, 0.97);
      } else {
        l(1, 1.03, 1, 2);
      }
      if (labels) text(d.key, Offset(1.45 * g, cy * g), size: 11, bold: true, col: col);
    case 'mcb1':
    case 'fuse':
      if (d.key == 'fuse') {
        l(1, 0, 1, 4, look != null && !look.closed ? (Paint()
          ..color = kBad
          ..strokeWidth = 2) : pen);
        c.drawRect(Rect.fromLTRB(0.62 * g, 1.0 * g, 1.38 * g, 3.0 * g), Paint()..color = Colors.white);
        c.drawRect(Rect.fromLTRB(0.62 * g, 1.0 * g, 1.38 * g, 3.0 * g), pen);
        l(1, 1.0, 1, 3.0, look != null && !look.closed ? (Paint()
          ..color = kBad
          ..strokeWidth = 2) : pen);
      } else {
        contact(1, true, look?.closed ?? false, breaker: true);
        final m = bladeMid(1, true, look?.closed ?? false);
        dashed(m.dx, m.dy, -0.05, m.dy);
        c.drawRect(Rect.fromCenter(center: Offset(-0.15 * g, m.dy * g), width: 0.36 * g, height: 0.5 * g), pen);
      }
      tagText();
      pinLabels();
    case 'mcb3':
    case 'kc3':
      final closed = look?.closed ?? false;
      for (final x in [1.0, 3.0, 5.0]) {
        contact(x, true, closed, arcTop: d.key == 'kc3', breaker: d.key == 'mcb3');
      }
      final m1 = bladeMid(1, true, closed), m5 = bladeMid(5, true, closed);
      dashed(m1.dx - 0.2, m1.dy, m5.dx, m5.dy);
      tagText();
      pinLabels();
    case 'ol3':
      for (final x in [1.0, 3.0, 5.0]) {
        l(x, 0, x, 1.25);
        l(x, 2.75, x, 4);
        c.drawRect(Rect.fromLTRB((x - 0.42) * g, 1.25 * g, (x + 0.42) * g, 2.75 * g), pen);
        final pth = Path()
          ..moveTo(x * g, 1.25 * g)
          ..lineTo(x * g, 1.7 * g)
          ..lineTo((x + 0.22) * g, 1.7 * g)
          ..lineTo((x + 0.22) * g, 2.3 * g)
          ..lineTo(x * g, 2.3 * g)
          ..lineTo(x * g, 2.75 * g);
        c.drawPath(pth, bad ? (Paint()
          ..color = kBad
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke) : pen);
      }
      dashed(0.2, 2, 5.4, 2);
      tagText();
      pinLabels();
      if (look?.note != null) text(look!.note!, Offset(3 * g, 4.55 * g), size: 9, col: bad ? kBad : const Color(0xFF5A6578), align: TextAlign.center);
    case 'no':
    case 'nc':
    case 'tno':
    case 'tnc':
    case 'olno':
    case 'olnc':
      final no = d.kind.endsWith('NO');
      final closed = look?.closed ?? !no;
      contact(1, no, closed, delay: d.kind.startsWith('T'));
      if (d.kind.startsWith('OL')) {
        // thermal actuator mark
        final m = bladeMid(1, no, closed);
        dashed(m.dx, m.dy, 0.0, m.dy);
        final pth = Path()
          ..moveTo(-0.55 * g, (m.dy + 0.25) * g)
          ..lineTo(-0.55 * g, (m.dy - 0.15) * g)
          ..lineTo(-0.25 * g, (m.dy - 0.15) * g)
          ..lineTo(-0.25 * g, (m.dy + 0.25) * g);
        c.drawPath(pth, pen);
      }
      tagText(x: d.kind.startsWith('OL') ? -0.75 : -0.25);
      if (labels && contactNo.contains('-')) {
        final pr = contactNo.split('-');
        text(pr[0], Offset(1.18 * g, 0.55 * g), size: 8.5, col: const Color(0xFF5A6578));
        text(pr[1], Offset(1.18 * g, 3.45 * g), size: 8.5, col: const Color(0xFF5A6578));
      }
    case 'pb_no':
    case 'pb_nc':
    case 'estop':
    case 'sel':
      final no = d.key == 'pb_no' || d.key == 'sel';
      final closed = look?.closed ?? !no;
      contact(1, no, closed);
      final m = bladeMid(1, no, closed);
      dashed(m.dx, m.dy, -0.1, m.dy);
      if (d.key == 'estop') {
        c.drawArc(Rect.fromCircle(center: Offset(-0.35 * g, m.dy * g), radius: 0.4 * g), math.pi / 2, math.pi, true, Paint()..color = look != null && !closed ? kBad : const Color(0xFFE53935));
        c.drawArc(Rect.fromCircle(center: Offset(-0.35 * g, m.dy * g), radius: 0.4 * g), math.pi / 2, math.pi, true, pen);
      } else if (d.key == 'sel') {
        final pth = Path()
          ..moveTo(-0.1 * g, (m.dy - 0.35) * g)
          ..lineTo(-0.35 * g, (m.dy - 0.35) * g)
          ..lineTo(-0.1 * g, (m.dy + 0.35) * g)
          ..lineTo(-0.35 * g, (m.dy + 0.35) * g);
        c.drawPath(pth, pen);
      } else {
        final pth = Path()
          ..moveTo(-0.3 * g, (m.dy - 0.4) * g)
          ..lineTo(-0.1 * g, (m.dy - 0.4) * g)
          ..lineTo(-0.1 * g, (m.dy + 0.4) * g)
          ..lineTo(-0.3 * g, (m.dy + 0.4) * g);
        c.drawPath(pth, pen);
      }
      tagText(x: -0.7);
      pinLabels();
    case 'coil_kc':
    case 'coil_ka':
    case 'coil_kt':
      l(2, 0, 2, 1.25);
      l(2, 2.75, 2, 4);
      final r = Rect.fromLTRB(0.7 * g, 1.25 * g, 3.3 * g, 2.75 * g);
      c.drawRect(r, Paint()..color = on ? const Color(0xFFBDF2D3) : (bad ? const Color(0xFFFFD6DB) : Colors.white));
      c.drawRect(r, live ? act : pen);
      if (d.key == 'coil_kt') {
        final sub = Rect.fromLTRB(0.7 * g, 1.25 * g, 1.35 * g, 2.75 * g);
        c.drawRect(sub, pen);
        if ((p['mode'] ?? 'on') == 'on') {
          c.drawRect(sub.deflate(3), Paint()..color = ink);
        } else {
          for (var y = sub.top + 3; y < sub.bottom; y += 5) {
            c.drawLine(Offset(sub.left + 2, y), Offset(sub.right - 2, y + 3), pen..strokeWidth = 1);
          }
          pen.strokeWidth = 2;
        }
      }
      tagText(y: 2, x: 0.5);
      pinLabels();
      if (look?.note != null) text(look!.note!, Offset(2.0 * g, 2.0 * g), size: 9, bold: true, col: on ? kOn : (bad ? kBad : const Color(0xFF5A6578)), align: TextAlign.center);
    case 'lamp':
      final col = lampColor(p['col']);
      l(1, 0, 1, 1.25);
      l(1, 2.75, 1, 4);
      if (on) {
        c.drawCircle(const Offset(1 * g, 2 * g), 1.3 * g, Paint()
          ..color = col.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }
      c.drawCircle(const Offset(1 * g, 2 * g), 0.75 * g, Paint()..color = on ? col : (bad ? const Color(0xFF3A2A2A) : Colors.white));
      c.drawCircle(const Offset(1 * g, 2 * g), 0.75 * g, pen);
      const k = 0.53;
      l(1 - k, 2 - k, 1 + k, 2 + k);
      l(1 - k, 2 + k, 1 + k, 2 - k);
      if (labels && !live) c.drawCircle(const Offset(1.95 * g, 2 * g), 0.16 * g, Paint()..color = col);
      tagText();
      pinLabels();
    case 'motor3':
    case 'motor6':
      const cx = 3.0, cy = 3.0, r = 2.1;
      for (final pn in d.pins) {
        final dx = (pn.x - cx).abs();
        final dy = math.sqrt(math.max(0.0, r * r - dx * dx));
        if (pn.up) {
          l(pn.x, 0, pn.x, cy - dy);
        } else {
          l(pn.x, cy + dy, pn.x, pn.y);
        }
      }
      c.drawCircle(const Offset(cx * g, cy * g), r * g, Paint()..color = on ? const Color(0xFFDDF6E8) : (bad ? const Color(0xFFFFE1E4) : Colors.white));
      c.drawCircle(const Offset(cx * g, cy * g), r * g, live ? act : pen);
      text('M', const Offset(cx * g, (cy - 0.45) * g), size: 18, bold: true, align: TextAlign.center, col: live ? (bad ? kBad : (on ? kOn : ink)) : ink);
      text('3~', const Offset(cx * g, (cy + 0.6) * g), size: 12, align: TextAlign.center, col: live ? (bad ? kBad : (on ? kOn : ink)) : ink);
      if (on) {
        final a = (look?.angle ?? 0) * math.pi / 180;
        for (var i = 0; i < 3; i++) {
          final t = a + i * math.pi * 2 / 3;
          c.drawCircle(Offset(cx * g + math.cos(t) * (r - 0.35) * g, cy * g + math.sin(t) * (r - 0.35) * g), 2.6, Paint()..color = kOn);
        }
      }
      tagText(y: 3, x: 0.6);
      pinLabels();
      if (look?.note != null) text(look!.note!, Offset(cx * g, (d.key == 'motor6' ? 6.7 : 5.6) * g), size: 9, col: bad ? kBad : const Color(0xFF5A6578), align: TextAlign.center);
  }
}
