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
  /// which way the wire leaves the pin, before the symbol is rotated:
  /// u · d · l · r. Empty: up on row 0, down otherwise.
  final String side;
  const SymPin(this.id, this.x, this.y, [this.label = '', this.side = '']);
  bool get up => side.isEmpty ? y == 0 : side == 'u';

  /// unit vector the wire leaves along (unrotated symbol)
  Offset get dir => switch (side) {
        'l' => const Offset(-1, 0),
        'r' => const Offset(1, 0),
        'u' => const Offset(0, -1),
        'd' => const Offset(0, 1),
        _ => y == 0 ? const Offset(0, -1) : const Offset(0, 1),
      };
}

/// rotate (quarter turns clockwise) and mirror a direction vector the same way
/// [SPlaced] maps its pins: mirror first, then rotate
Offset turnDir(Offset v, int rot, bool flip) {
  var x = flip ? -v.dx : v.dx, y = v.dy;
  for (var i = 0; i < rot % 4; i++) {
    final t = x;
    x = -y;
    y = t;
  }
  return Offset(x, y);
}

/// canvas transform that draws an unrotated symbol of [w]×[h] grid units
/// mirrored ([flip]) and turned [rot] quarter turns clockwise, top-left at the origin
void symTransform(Canvas c, double w, double h, int rot, bool flip) {
  const g = kG;
  switch (rot % 4) {
    case 1:
      c.translate(h * g, 0);
      c.rotate(math.pi / 2);
    case 2:
      c.translate(w * g, h * g);
      c.rotate(math.pi);
    case 3:
      c.translate(0, w * g);
      c.rotate(-math.pi / 2);
  }
  if (flip) {
    c.translate(w * g, 0);
    c.scale(-1, 1);
  }
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
  /// several symbols with the same tag are one device (limit switch NO + NC)
  final bool shared;
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
    this.shared = false,
  });
}

const _two = [SymPin('1', 1, 0), SymPin('2', 1, 4)];

const kSymCategories = <(String, int, List<String>)>[
  ('التغذية', 0xFF35E08A, ['sup3', 'sup1', 'L1', 'L2', 'L3', 'N', 'PE', 'trafo', 'psu']),
  ('الحماية والفصل', 0xFFFF5A64, ['mcb1', 'mcb2', 'mcb3', 'mcb4', 'fuse', 'rccb', 'mpcb', 'isol3', 'ol3', 'olnc', 'olno', 'phr']),
  ('الكونتاكتور والمرحل', 0xFF4FD8FF, ['coil_kc', 'kc3', 'no', 'nc', 'coil_ka']),
  ('المؤقتات', 0xFF3D8BFF, ['coil_kt', 'tno', 'tnc']),
  ('أوامر التشغيل', 0xFFB07CFF, ['pb_no', 'pb_nc', 'estop', 'sel', 'ls_no', 'ls_nc']),
  ('الحساسات', 0xFFFFC14D, ['prox_ind', 'prox_cap', 'photo', 'float_no', 'float_nc', 'press_no', 'thermo_nc', 'reed_no']),
  ('الأحمال', 0xFFC9A27E, ['lamp', 'bz', 'horn', 'yv', 'heat', 'motor1', 'motor3', 'motor6']),
  ('التوصيل', 0xFF9AA6B8, ['tb']),
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
        key: 'ls_no', nameAr: 'مفتاح نهاية شوط: النقطة المفتوحة 23-24', category: 'أوامر التشغيل', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('23', 1, 0, '23'), SymPin('24', 1, 4, '24')], role: SymRole.device, engine: 'ls', kind: 'NO', shared: true),
    const SymDef(
        key: 'ls_nc', nameAr: 'مفتاح نهاية شوط: النقطة المغلقة 11-12', category: 'أوامر التشغيل', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('11', 1, 0, '11'), SymPin('12', 1, 4, '12')], role: SymRole.device, engine: 'ls', kind: 'NC', shared: true),
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
    // ---- supply blocks: every phase of the mains on one symbol
    const SymDef(
        key: 'sup3', nameAr: 'مصدر تغذية ثلاثي الأوجه 400 فولت', category: 'التغذية', prefix: 'X0', w: 10, h: 3,
        pins: [SymPin('L1', 1, 3, 'L1'), SymPin('L2', 3, 3, 'L2'), SymPin('L3', 5, 3, 'L3'), SymPin('N', 7, 3, 'N'), SymPin('PE', 9, 3, 'PE')],
        role: SymRole.source, engine: 'sup'),
    const SymDef(
        key: 'sup1', nameAr: 'مصدر تغذية وجه واحد 230 فولت', category: 'التغذية', prefix: 'X0', w: 6, h: 3,
        pins: [SymPin('L1', 1, 3, 'L'), SymPin('N', 3, 3, 'N'), SymPin('PE', 5, 3, 'PE')], role: SymRole.source, engine: 'sup'),
    const SymDef(
        key: 'trafo', nameAr: 'محوّل تحكم 400/230 إلى 24 فولت', category: 'التغذية', prefix: 'T', w: 6, h: 6,
        pins: [SymPin('P0', 1, 0, '0'), SymPin('P220', 3, 0, '230'), SymPin('P380', 5, 0, '400'), SymPin('S0', 1, 6, '0'), SymPin('S24', 3, 6, '24'), SymPin('S48', 5, 6, '48')],
        role: SymRole.device, engine: 'trafo'),
    const SymDef(
        key: 'psu', nameAr: 'مزوّد قدرة 24 فولت DC', category: 'التغذية', prefix: 'G', w: 5, h: 5,
        pins: [SymPin('L', 1, 0, 'L'), SymPin('N', 3, 0, 'N'), SymPin('P', 1, 5, '+'), SymPin('M', 3, 5, '−')], role: SymRole.device, engine: 'psu'),
    // ---- protection and switching
    const SymDef(
        key: 'mcb2', nameAr: 'قاطع آلي قطبين', category: 'الحماية', prefix: 'F', w: 4, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4')], role: SymRole.device, engine: 'mcb2'),
    const SymDef(
        key: 'mcb4', nameAr: 'قاطع آلي رباعي الأقطاب', category: 'الحماية', prefix: 'Q', w: 8, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('7', 7, 0, '7'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6'), SymPin('8', 7, 4, '8')],
        role: SymRole.device, engine: 'mcb4'),
    const SymDef(
        key: 'rccb', nameAr: 'قاطع التسرب الأرضي RCCB', category: 'الحماية', prefix: 'F', w: 4, h: 5,
        pins: [SymPin('1', 1, 0, '1'), SymPin('N', 3, 0, 'N'), SymPin('2', 1, 5, '2'), SymPin('N2', 3, 5, 'N')], role: SymRole.device, engine: 'rccb'),
    const SymDef(
        key: 'mpcb', nameAr: 'قاطع حماية محرك MPCB', category: 'الحماية', prefix: 'Q', w: 6, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6')],
        role: SymRole.device, engine: 'mpcb'),
    const SymDef(
        key: 'isol3', nameAr: 'مفتاح فاصل رئيسي ثلاثي', category: 'الحماية', prefix: 'Q', w: 6, h: 4,
        pins: [SymPin('1', 1, 0, '1'), SymPin('3', 3, 0, '3'), SymPin('5', 5, 0, '5'), SymPin('2', 1, 4, '2'), SymPin('4', 3, 4, '4'), SymPin('6', 5, 4, '6')],
        role: SymRole.device, engine: 'isol3'),
    const SymDef(
        key: 'phr', nameAr: 'مرحّل مراقبة الأطوار', category: 'الحماية', prefix: 'KF', w: 9, h: 4,
        pins: [SymPin('L1', 1, 0, 'L1'), SymPin('L2', 3, 0, 'L2'), SymPin('L3', 5, 0, 'L3'), SymPin('11', 7, 0, '11'), SymPin('12', 6, 4, '12'), SymPin('14', 8, 4, '14')],
        role: SymRole.device, engine: 'phr'),
    // ---- sensors: 3-wire PNP (BN +24 V · BU 0 V · BK output) and switch contacts
    const SymDef(
        key: 'prox_ind', nameAr: 'حساس تقارب حثي PNP (معادن)', category: 'الحساسات', prefix: 'B', w: 4, h: 4,
        pins: [SymPin('BN', 1, 0, 'BN'), SymPin('BU', 1, 4, 'BU'), SymPin('BK', 3, 4, 'BK')], role: SymRole.device, engine: 'prox'),
    const SymDef(
        key: 'prox_cap', nameAr: 'حساس تقارب سعوي PNP', category: 'الحساسات', prefix: 'B', w: 4, h: 4,
        pins: [SymPin('BN', 1, 0, 'BN'), SymPin('BU', 1, 4, 'BU'), SymPin('BK', 3, 4, 'BK')], role: SymRole.device, engine: 'prox'),
    const SymDef(
        key: 'photo', nameAr: 'حساس ضوئي (فوتوسل) PNP', category: 'الحساسات', prefix: 'B', w: 4, h: 4,
        pins: [SymPin('BN', 1, 0, 'BN'), SymPin('BU', 1, 4, 'BU'), SymPin('BK', 3, 4, 'BK')], role: SymRole.device, engine: 'prox'),
    const SymDef(
        key: 'float_no', nameAr: 'عوامة: نقطة مفتوحة', category: 'الحساسات', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('23', 1, 0, '23'), SymPin('24', 1, 4, '24')], role: SymRole.device, engine: 'ls', kind: 'NO', shared: true, params: {'latch': true}),
    const SymDef(
        key: 'float_nc', nameAr: 'عوامة: نقطة مغلقة', category: 'الحساسات', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('11', 1, 0, '11'), SymPin('12', 1, 4, '12')], role: SymRole.device, engine: 'ls', kind: 'NC', shared: true, params: {'latch': true}),
    const SymDef(
        key: 'press_no', nameAr: 'مفتاح ضغط (بريشر سويتش)', category: 'الحساسات', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('23', 1, 0, '23'), SymPin('24', 1, 4, '24')], role: SymRole.device, engine: 'ls', kind: 'NO', shared: true, params: {'latch': true}),
    const SymDef(
        key: 'thermo_nc', nameAr: 'ثرموستات: يفصل عند السخونة', category: 'الحساسات', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('11', 1, 0, '11'), SymPin('12', 1, 4, '12')], role: SymRole.device, engine: 'ls', kind: 'NC', shared: true, params: {'latch': true}),
    const SymDef(
        key: 'reed_no', nameAr: 'حساس مغناطيسي (ريد) لبستم', category: 'الحساسات', prefix: 'B', w: 2, h: 4,
        pins: [SymPin('23', 1, 0, '23'), SymPin('24', 1, 4, '24')], role: SymRole.device, engine: 'ls', kind: 'NO', shared: true),
    // ---- loads
    const SymDef(
        key: 'bz', nameAr: 'جرس (بازر)', category: 'الأحمال', prefix: 'P', w: 2, h: 4, pins: [SymPin('X1', 1, 0, 'X1'), SymPin('X2', 1, 4, 'X2')], role: SymRole.device, engine: 'lamp',
        params: {'V': 220.0}),
    const SymDef(
        key: 'horn', nameAr: 'سارينة إنذار', category: 'الأحمال', prefix: 'P', w: 2, h: 4, pins: [SymPin('X1', 1, 0, 'X1'), SymPin('X2', 1, 4, 'X2')], role: SymRole.device, engine: 'lamp',
        params: {'V': 220.0}),
    const SymDef(
        key: 'yv', nameAr: 'ملف صمام هوائي (سولونويد)', category: 'الأحمال', prefix: 'Y', w: 4, h: 4, pins: [SymPin('X1', 2, 0, 'A1'), SymPin('X2', 2, 4, 'A2')], role: SymRole.device, engine: 'lamp',
        params: {'V': 24.0}),
    const SymDef(
        key: 'heat', nameAr: 'سخان كهربائي', category: 'الأحمال', prefix: 'E', w: 2, h: 4, pins: [SymPin('X1', 1, 0, '1'), SymPin('X2', 1, 4, '2')], role: SymRole.device, engine: 'lamp',
        params: {'V': 220.0}),
    const SymDef(
        key: 'motor1', nameAr: 'محرك وجه واحد بمكثف', category: 'الأحمال', prefix: 'M', w: 8, h: 6,
        pins: [SymPin('U1', 1, 0, 'U1'), SymPin('U2', 3, 0, 'U2'), SymPin('Z1', 5, 0, 'Z1'), SymPin('Z2', 7, 0, 'Z2')], role: SymRole.device, engine: 'motor1', params: {'In': 4.0}),
    const SymDef(
        key: 'tb', nameAr: 'ريشة توصيل (ترمينال)', category: 'التوصيل', prefix: 'X', w: 2, h: 2, pins: [SymPin('1', 1, 0, '1'), SymPin('2', 1, 2, '2')], role: SymRole.device, engine: 'tb'),
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

/// IEC 60446 conductor colours: L1 brown · L2 black · L3 grey · N blue · PE green-yellow
Color phaseColor(String k) => switch (k) {
      'L1' => const Color(0xFF8D5A3B),
      'L2' => const Color(0xFF262A30),
      'L3' => const Color(0xFF7D858C),
      'N' => const Color(0xFF2F7FE0),
      _ => const Color(0xFF2EAA4A),
    };

Color lampColor(Object? c) => switch (c) { 'r' => const Color(0xFFFF3B30), 'y' => const Color(0xFFFFB300), 'b' => const Color(0xFF2F7FE0), 'w' => const Color(0xFFE8E8E8), _ => const Color(0xFF22C55E) };

/// Draws [d] with its top-left at the canvas origin.
/// [look] is null in edit mode (normal position).
/// [rot] / [flip]: how the canvas was turned (see [symTransform]); text is kept upright.
void paintSymbol(Canvas c, SymDef d,
    {SymLook? look, String tag = '', Map<String, Object?> p = const {}, Color ink = kInk, bool labels = true, String contactNo = '', int rot = 0, bool flip = false}) {
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
    if (rot % 4 == 0 && !flip) {
      final dx = align == TextAlign.right ? -tp.width : (align == TextAlign.center ? -tp.width / 2 : 0.0);
      tp.paint(c, at + Offset(dx, -tp.height / 2));
      return;
    }
    // keep the text upright: undo the symbol's turn around the anchor, and push the
    // text out on the side it was aligned to
    final side = turnDir(Offset(align == TextAlign.right ? -1 : (align == TextAlign.left ? 1 : 0), 0), rot, flip);
    c.save();
    c.translate(at.dx, at.dy);
    if (flip) c.scale(-1, 1);
    c.rotate(-(rot % 4) * math.pi / 2);
    // the canvas now has the sheet's axes
    tp.paint(c, Offset(side.dx * tp.width / 2 - tp.width / 2, side.dy * (tp.height / 2 + 1) - tp.height / 2));
    c.restore();
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
      final col = phaseColor(d.key);
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
    case 'mcb2':
    case 'mcb4':
    case 'mpcb':
    case 'isol3':
      final closed = look?.closed ?? false;
      final xs = [for (final pn in d.pins) if (pn.up) pn.x];
      final trips = d.key != 'kc3' && d.key != 'isol3';
      for (final x in xs) {
        contact(x, true, closed, arcTop: d.key == 'kc3', breaker: trips);
        if (d.key == 'isol3') l(x - 0.3, 1.3, x + 0.3, 1.3); // disconnector: bar on the fixed contact
      }
      final m1 = bladeMid(xs.first, true, closed), m5 = bladeMid(xs.last, true, closed);
      dashed(m1.dx - 0.2, m1.dy, m5.dx, m5.dy);
      if (d.key == 'isol3') {
        l(m1.dx - 0.2, m1.dy - 0.4, m1.dx - 0.2, m1.dy + 0.4); // handle
      } else if (d.key == 'mpcb') {
        // thermal and magnetic releases
        final r = Rect.fromLTRB(-1.15 * g, (m1.dy - 0.45) * g, (m1.dx - 0.2) * g, (m1.dy + 0.45) * g);
        c.drawRect(r, Paint()..color = Colors.white);
        c.drawRect(r, pen);
        text('I>', r.center, size: 8, bold: true, align: TextAlign.center);
      }
      tagText(x: d.key == 'mpcb' ? -1.35 : -0.25);
      pinLabels();
      if (bad) text('TRIP', Offset((xs.first + xs.last) / 2 * g, 4.55 * g), size: 9, bold: true, col: kBad, align: TextAlign.center);
    case 'rccb':
      final closed = look?.closed ?? false;
      for (final x in [1.0, 3.0]) {
        contact(x, true, closed, breaker: true);
        l(x, 4, x, 5);
      }
      c.drawOval(Rect.fromLTRB(0.35 * g, 3.5 * g, 3.65 * g, 4.2 * g), pen);
      final m1 = bladeMid(1, true, closed), m3 = bladeMid(3, true, closed);
      dashed(m1.dx - 0.2, m1.dy, m3.dx, m3.dy);
      dashed(2, 3.5, 2, m1.dy);
      final r = Rect.fromLTRB(-1.25 * g, (m1.dy - 0.45) * g, (m1.dx - 0.2) * g, (m1.dy + 0.45) * g);
      c.drawRect(r, Paint()..color = Colors.white);
      c.drawRect(r, pen);
      text('30mA', r.center, size: 6.5, bold: true, align: TextAlign.center);
      tagText(x: -1.45);
      pinLabels();
    case 'sup3':
    case 'sup1':
      final box = RRect.fromRectAndRadius(Rect.fromLTRB(0.2 * g, 0.2 * g, (d.w - 0.2) * g, 2.0 * g), const Radius.circular(5));
      c.drawRRect(box, Paint()..color = live && on ? const Color(0xFFE6F8EE) : Colors.white);
      c.drawRRect(box, live && on ? act : pen);
      for (final pn in d.pins) {
        final col = phaseColor(pn.id);
        l(pn.x, 2.0, pn.x, 3);
        c.drawCircle(Offset(pn.x * g, 2.0 * g), 0.22 * g, Paint()..color = live ? col : Colors.white);
        c.drawCircle(Offset(pn.x * g, 2.0 * g), 0.22 * g, pen);
        if (labels) text(pn.label, Offset(pn.x * g, 1.35 * g), size: 9.5, bold: true, col: col, align: TextAlign.center);
      }
      if (labels) text(d.key == 'sup3' ? '3~ 400V 50Hz' : '1~ 230V 50Hz', Offset(d.w / 2 * g, 0.62 * g), size: 8, col: const Color(0xFF5A6578), align: TextAlign.center);
    case 'trafo':
      final tp = live && on ? act : pen;
      for (final x in [1.0, 3.0, 5.0]) {
        l(x, 0, x, 1.6);
        l(x, 4.4, x, 6);
      }
      for (var i = 0; i < 4; i++) {
        c.drawArc(Rect.fromCircle(center: Offset((1.5 + i) * g, 1.6 * g), radius: 0.5 * g), 0, math.pi, false, tp);
        c.drawArc(Rect.fromCircle(center: Offset((1.5 + i) * g, 4.4 * g), radius: 0.5 * g), math.pi, math.pi, false, tp);
      }
      l(0.8, 2.85, 5.2, 2.85);
      l(0.8, 3.15, 5.2, 3.15);
      tagText(y: 3, x: 0.5);
      pinLabels();
    case 'psu':
      for (final x in [1.0, 3.0]) {
        l(x, 0, x, 1);
        l(x, 4, x, 5);
      }
      final r = Rect.fromLTRB(0.3 * g, 1 * g, 4.7 * g, 4 * g);
      c.drawRect(r, Paint()..color = live && on ? const Color(0xFFE6F8EE) : Colors.white);
      c.drawRect(r, live && on ? act : pen);
      l(0.3, 4, 4.7, 1);
      text('~', Offset(1.3 * g, 1.75 * g), size: 14, bold: true, align: TextAlign.center);
      text('24V', Offset(3.5 * g, 3.25 * g), size: 8.5, bold: true, align: TextAlign.center);
      tagText(y: 2.5);
      pinLabels();
    case 'phr':
      for (final x in [1.0, 3.0, 5.0]) {
        l(x, 0, x, 1);
      }
      final r = Rect.fromLTRB(0.3 * g, 1 * g, 5.7 * g, 3 * g);
      c.drawRect(r, Paint()..color = Colors.white);
      c.drawRect(r, pen);
      text('3~ L1-L2-L3', Offset(3 * g, 2 * g), size: 8.5, bold: true, align: TextAlign.center);
      final okp = look?.closed ?? false;
      l(7, 0, 7, 1.4);
      l(6, 2.75, 6, 4);
      l(8, 2.75, 8, 4);
      final tip = okp ? const Offset(7.9, 2.65) : const Offset(6.1, 2.65);
      l(7, 1.4, tip.dx, tip.dy, live ? (Paint()
        ..color = okp ? kOn : ink
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round) : pen);
      dashed(5.7, 2, (7 + tip.dx) / 2, 2);
      tagText(y: 2);
      pinLabels();
    case 'prox_ind':
    case 'prox_cap':
    case 'photo':
      final closed = look?.closed ?? false;
      Paint lead(int col) => Paint()
        ..color = Color(col)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      l(1, 0, 1, 1, lead(0xFF8D5A3B));
      l(1, 3, 1, 4, lead(0xFF2F7FE0));
      l(3, 3, 3, 4, lead(0xFF262A30));
      final r = Rect.fromLTRB(0.2 * g, 1 * g, 3.8 * g, 3 * g);
      c.drawRect(r, Paint()..color = live && closed ? const Color(0xFFFFF1C9) : Colors.white);
      c.drawRect(r, pen);
      // sensing face
      final dm = Path()
        ..moveTo(1.3 * g, 1.45 * g)
        ..lineTo(1.85 * g, 2 * g)
        ..lineTo(1.3 * g, 2.55 * g)
        ..lineTo(0.75 * g, 2 * g)
        ..close();
      c.drawPath(dm, pen);
      switch (d.key) {
        case 'prox_ind':
          text('Fe', Offset(1.3 * g, 2 * g), size: 6.5, bold: true, align: TextAlign.center);
        case 'prox_cap':
          l(1.15, 1.8, 1.15, 2.2);
          l(1.45, 1.8, 1.45, 2.2);
        default:
          for (final dy in [-0.2, 0.2]) {
            l(0.95, 2 + dy - 0.12, 1.55, 2 + dy + 0.12);
            l(1.55, 2 + dy + 0.12, 1.4, 2 + dy + 0.14);
          }
      }
      // PNP output: BN switched to BK
      l(1, 1, 1, 1.25);
      l(1, 1.25, 3, 1.25);
      l(3, 1.25, 3, 1.45);
      l(3, 2.6, 3, 3);
      final bp = live ? (Paint()
        ..color = closed ? kOn : ink
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round) : pen;
      l(3, 2.6, closed ? 3.0 : 2.55, closed ? 1.45 : 1.6, bp);
      tagText(x: -0.15);
      pinLabels();
    case 'bz':
      l(1, 0, 1, 1.65);
      l(1, 2.4, 1, 4);
      final dome = Rect.fromCircle(center: const Offset(1 * g, 2.4 * g), radius: 0.75 * g);
      c.drawArc(dome, math.pi, math.pi, true, Paint()..color = on ? const Color(0xFFFFD166) : (bad ? const Color(0xFF3A2A2A) : Colors.white));
      c.drawArc(dome, math.pi, math.pi, true, live ? act : pen);
      if (on) {
        for (final rr in [1.05, 1.35]) {
          c.drawArc(Rect.fromCircle(center: const Offset(1 * g, 2.1 * g), radius: rr * g), -math.pi / 2 + 0.5, 0.9, false, act);
        }
      }
      tagText();
      pinLabels();
    case 'horn':
      l(1, 0, 1, 1.4);
      l(1, 2.7, 1, 4);
      final fill = Paint()..color = on ? const Color(0xFFFFB3B3) : (bad ? const Color(0xFF3A2A2A) : Colors.white);
      final body = Rect.fromLTRB(0.65 * g, 1.4 * g, 1.35 * g, 2.0 * g);
      final flare = Path()
        ..moveTo(0.65 * g, 2.0 * g)
        ..lineTo(1.35 * g, 2.0 * g)
        ..lineTo(1.85 * g, 2.7 * g)
        ..lineTo(0.15 * g, 2.7 * g)
        ..close();
      c.drawRect(body, fill);
      c.drawPath(flare, fill);
      c.drawRect(body, live ? act : pen);
      c.drawPath(flare, live ? act : pen);
      tagText(x: -0.05);
      pinLabels();
    case 'yv':
      l(2, 0, 2, 1.25);
      l(2, 2.75, 2, 4);
      final r = Rect.fromLTRB(0.7 * g, 1.25 * g, 3.3 * g, 2.75 * g);
      c.drawRect(r, Paint()..color = on ? const Color(0xFFBDF2D3) : (bad ? const Color(0xFFFFD6DB) : Colors.white));
      c.drawRect(r, live ? act : pen);
      l(0.7, 2.75, 3.3, 1.25, live ? act : pen);
      tagText(y: 2, x: 0.5);
      pinLabels();
    case 'heat':
      l(1, 0, 1, 1);
      l(1, 3, 1, 4);
      final r = Rect.fromLTRB(0.5 * g, 1 * g, 1.5 * g, 3 * g);
      c.drawRect(r, Paint()..color = on ? const Color(0xFFFFC9A3) : (bad ? const Color(0xFF3A2A2A) : Colors.white));
      c.drawRect(r, live ? act : pen);
      for (final y in [1.5, 2.0, 2.5]) {
        l(0.5, y, 1.5, y, live ? act : pen);
      }
      tagText();
      pinLabels();
    case 'motor1':
      const cx = 4.0, cy = 3.6, r = 2.3;
      for (final pn in d.pins) {
        final dx = (pn.x - cx).abs();
        if (dx < r - 0.1) {
          l(pn.x, 0, pn.x, cy - math.sqrt(r * r - dx * dx));
        } else {
          l(pn.x, 0, pn.x, cy);
          l(pn.x, cy, pn.x < cx ? cx - r : cx + r, cy);
        }
      }
      c.drawCircle(const Offset(cx * g, cy * g), r * g, Paint()..color = on ? const Color(0xFFDDF6E8) : (bad ? const Color(0xFFFFE1E4) : Colors.white));
      c.drawCircle(const Offset(cx * g, cy * g), r * g, live ? act : pen);
      final mc = live ? (bad ? kBad : (on ? kOn : ink)) : ink;
      text('M', const Offset(cx * g, (cy - 0.45) * g), size: 18, bold: true, align: TextAlign.center, col: mc);
      text('1~', const Offset(cx * g, (cy + 0.6) * g), size: 12, align: TextAlign.center, col: mc);
      if (on) {
        final a = (look?.angle ?? 0) * math.pi / 180;
        for (var i = 0; i < 3; i++) {
          final t = a + i * math.pi * 2 / 3;
          c.drawCircle(Offset(cx * g + math.cos(t) * (r - 0.35) * g, cy * g + math.sin(t) * (r - 0.35) * g), 2.6, Paint()..color = kOn);
        }
      }
      tagText(y: 3.6, x: 0.2);
      pinLabels();
      if (look?.note != null) text(look!.note!, Offset(cx * g, 6.5 * g), size: 9, col: bad ? kBad : const Color(0xFF5A6578), align: TextAlign.center);
    case 'tb':
      l(1, 0, 1, 0.68);
      l(1, 1.32, 1, 2);
      c.drawCircle(const Offset(1 * g, 1 * g), 0.32 * g, Paint()..color = Colors.white);
      c.drawCircle(const Offset(1 * g, 1 * g), 0.32 * g, pen);
      l(0.78, 1.22, 1.22, 0.78);
      if (labels && tag.isNotEmpty) text('-$tag', const Offset(1.5 * g, 1 * g), size: 10, bold: true);
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
    case 'ls_no':
    case 'ls_nc':
    case 'float_no':
    case 'float_nc':
    case 'press_no':
    case 'thermo_nc':
    case 'reed_no':
      final no = d.key == 'pb_no' || d.key == 'sel' || d.kind == 'NO';
      final closed = look?.closed ?? !no;
      contact(1, no, closed);
      final m = bladeMid(1, no, closed);
      dashed(m.dx, m.dy, -0.1, m.dy);
      if (d.key.startsWith('float')) {
        // float on a lever
        l(-0.1, m.dy, -0.45, m.dy + 0.45);
        c.drawCircle(Offset(-0.6 * g, (m.dy + 0.68) * g), 0.26 * g, Paint()..color = const Color(0xFFDDEBFF));
        c.drawCircle(Offset(-0.6 * g, (m.dy + 0.68) * g), 0.26 * g, pen);
      } else if (d.key == 'press_no') {
        c.drawArc(Rect.fromCircle(center: Offset(-0.1 * g, m.dy * g), radius: 0.42 * g), math.pi / 2, math.pi, true, Paint()..color = Colors.white);
        c.drawArc(Rect.fromCircle(center: Offset(-0.1 * g, m.dy * g), radius: 0.42 * g), math.pi / 2, math.pi, true, pen);
        text('P', Offset(-0.33 * g, m.dy * g), size: 7.5, bold: true, align: TextAlign.center);
      } else if (d.key == 'thermo_nc') {
        final r = Rect.fromLTRB(-0.85 * g, (m.dy - 0.38) * g, -0.1 * g, (m.dy + 0.38) * g);
        c.drawRect(r, Paint()..color = Colors.white);
        c.drawRect(r, pen);
        text('t°', r.center, size: 8.5, bold: true, align: TextAlign.center);
      } else if (d.key == 'reed_no') {
        final r = Rect.fromLTRB(-0.9 * g, (m.dy - 0.24) * g, -0.1 * g, (m.dy + 0.24) * g);
        c.drawRect(r, Paint()..color = const Color(0xFFFFE0E0));
        c.drawRect(r, pen);
        l(-0.5, m.dy - 0.24, -0.5, m.dy + 0.24);
        text('N', Offset(-0.7 * g, m.dy * g), size: 6.5, bold: true, align: TextAlign.center);
        text('S', Offset(-0.3 * g, m.dy * g), size: 6.5, bold: true, align: TextAlign.center);
      } else if (d.key.startsWith('ls')) {
        // roller lever
        c.drawLine(Offset(-0.1 * g, m.dy * g), Offset(-0.45 * g, (m.dy - 0.45) * g), pen);
        c.drawCircle(Offset(-0.55 * g, (m.dy - 0.55) * g), 0.2 * g, pen);
      } else if (d.key == 'estop') {
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
      tagText(x: d.key.startsWith('float') || d.key == 'thermo_nc' || d.key == 'reed_no' ? -1.05 : -0.7);
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
