// Panel Lab parts: which sprite, which engine device, how its printed terminals map to
// engine terminals, and how it mounts.
import 'dart:convert';

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/services.dart';

import '../sim/engine.dart' show machSwitches, machValve;

class SpriteInfo {
  final String name;
  final double wMm, hMm; // physical size
  final double ppm;
  final Map<String, (double, double)> terms; // sprite terminal → mm from top-left
  const SpriteInfo(this.name, this.wMm, this.hMm, this.ppm, this.terms);
  String get asset => 'assets/panel/$name.webp';
}

class Sprites {
  static final Map<String, SpriteInfo> _m = {};
  static bool loaded = false;

  static Future<void> load() async {
    if (loaded) return;
    final raw = jsonDecode(await rootBundle.loadString('assets/panel/panel_sprites.json')) as Map<String, dynamic>;
    final ppm = (raw['_ppm'] as num).toDouble();
    raw.forEach((k, v) {
      if (k.startsWith('_')) return;
      final m = v as Map<String, dynamic>;
      final t = <String, (double, double)>{};
      (m['terms'] as Map<String, dynamic>).forEach((n, p) {
        final l = p as List;
        t[n] = ((l[0] as num) / ppm, (l[1] as num) / ppm);
      });
      _m[k] = SpriteInfo(k, (m['w'] as num) / ppm, (m['h'] as num) / ppm, ppm, t);
    });
    loaded = true;
  }

  static SpriteInfo? of(String name) => _m[name];
}

enum Mount { din, free }

class LabPartDef {
  final String key, nameAr, category, sprite, engine, prefix;
  final Map<String, String> terms; // sprite terminal → engine terminal (others are hidden)
  final Map<String, Object?> params;
  final Mount mount;
  final String? attachTo; // engine type it clips onto (aux block / overload on a contactor)
  /// extra terminals not in the sprite: engine terminal → mm (motor plate)
  final Map<String, (double, double)> extraTerms;

  /// door device seen face-on: [left terminal, right terminal] on lugs beside it
  final List<String> side;
  const LabPartDef({
    required this.key,
    required this.nameAr,
    required this.category,
    required this.sprite,
    required this.engine,
    required this.prefix,
    this.terms = const {},
    this.params = const {},
    this.mount = Mount.din,
    this.attachTo,
    this.extraTerms = const {},
    this.side = const [],
  });

  String? get machine => engine == 'mach' ? params['kind'] as String? : null;

  /// part frame in mm
  Size get frame {
    final m = machine;
    if (m != null) return MachineGeo.size(m);
    final i = info;
    if (i == null) return const Size(40, 60);
    if (side.isNotEmpty) return Size(i.wMm + 2 * kLug, math.max(i.hMm, 24));
    return Size(i.wMm, i.hMm);
  }

  SpriteInfo? get info => Sprites.of(sprite);

  /// engine terminal → position in mm relative to the part's top-left
  Map<String, (double, double)> termPos() {
    final i = info;
    final out = <String, (double, double)>{};
    final m = machine;
    if (m != null) return MachineGeo.terms(m);
    if (side.isNotEmpty) {
      final f = frame;
      return {side[0]: (kLug * 0.48, f.height / 2), side[1]: (f.width - kLug * 0.48, f.height / 2)};
    }
    if (i != null) {
      terms.forEach((s, e) {
        final p = i.terms[s];
        if (p != null) out[e] = p;
      });
    }
    out.addAll(extraTerms);
    return out;
  }

  /// the label printed next to a terminal (the sprite name, without model suffixes)
  String printed(String engineTerm) {
    for (final e in terms.entries) {
      if (e.value == engineTerm) return e.key.split('_').first.replaceAll('NO', '').replaceAll('NC', '');
    }
    return engineTerm;
  }
}

class LabCategory {
  final String nameAr;
  final int color;
  final List<String> parts;
  const LabCategory(this.nameAr, this.color, this.parts);
}

const kLabCategories = [
  LabCategory('التغذية', 0xFF35E08A, ['supply', 'supply_iso', 'supply1', 'trafo', 'psu']),
  LabCategory('الحماية', 0xFFFF5A64, ['mcb1', 'mcb2', 'mcb3', 'mcb4', 'mpcb', 'rccb', 'fuse']),
  LabCategory('الكونتاكتورات', 0xFF4FD8FF, ['kc', 'kc_rev', 'aux', 'ol', 'ol_free']),
  LabCategory('المرحلات والمؤقتات', 0xFF3D8BFF, ['relay', 'timer', 'tsd', 'phr']),
  LabCategory('الضواغط والإشارة', 0xFFB07CFF, ['pb_green', 'pb_red', 'pb_black', 'estop', 'selector', 'lamp_green', 'lamp_red', 'lamp_amber', 'siren']),
  LabCategory('المحركات', 0xFFC9A27E, ['motor', 'motor_d', 'motor_s', 'motor1']),
  LabCategory('الآلات والحساسات', 0xFF4FD8FF, ['mach_cart', 'mach_hoist', 'mach_lift', 'mach_tank', 'mach_sort', 'mach_press', 'mach_fill', 'limit']),
  LabCategory('التمديدات', 0xFFF5B83D, ['tb', 'din_rail']),
];

const _contactorTerms = {
  '1_L1': '1', '2_T1': '2', '3_L2': '3', '4_T2': '4', '5_L3': '5', '6_T3': '6', '13NO': '13', '14NO': '14', 'A1': 'A1', 'A2': 'A2'
};

final Map<String, LabPartDef> kLabParts = {
  for (final d in <LabPartDef>[
    const LabPartDef(
        key: 'supply', nameAr: 'تغذية الشبكة 400/230 فولت', category: 'التغذية', sprite: 'terminal_strip', engine: 'sup', prefix: 'X0',
        terms: {'L1_2': 'L1', 'L2_2': 'L2', 'L3_2': 'L3', 'N_2': 'N', 'PE_2': 'PE'}),
    const LabPartDef(
        key: 'supply_iso', nameAr: 'تغذية بمفتاح عزل رئيسي (يُدار باليد)', category: 'التغذية', sprite: 'main_isolator', engine: 'sup', prefix: 'X0',
        params: {'sw': true}, mount: Mount.free,
        extraTerms: {'L1': (8.0, 63.0), 'L2': (21.0, 63.0), 'L3': (34.0, 63.0), 'N': (48.0, 63.0), 'PE': (61.0, 63.0)}),
    const LabPartDef(
        key: 'supply1', nameAr: 'تغذية أحادية الطور 230 فولت (L N PE)', category: 'التغذية', sprite: 'terminal_strip', engine: 'sup', prefix: 'X0',
        terms: {'L1_2': 'L1', 'N_2': 'N', 'PE_2': 'PE'}, params: {'ph': 1}),
    const LabPartDef(
        key: 'trafo', nameAr: 'محوّل تحكم', category: 'التغذية', sprite: 'control_transformer', engine: 'trafo', prefix: 'T',
        terms: {'P0': 'P0', 'P220': 'P220', 'P380': 'P380', 'S0': 'S0', 'S24': 'S24', 'S48': 'S48'}, mount: Mount.free),
    const LabPartDef(
        key: 'psu', nameAr: 'مزوّد قدرة 24 فولت مستمر', category: 'التغذية', sprite: 'power_supply_24v', engine: 'psu', prefix: 'G',
        terms: {'L': 'L', 'N': 'N', 'PE': 'PE', '+V': 'P', '+V.001': 'P2', '-V': 'M', '-V.001': 'M2'}),
    const LabPartDef(key: 'mcb1', nameAr: 'قاطع MCB قطب واحد', category: 'الحماية', sprite: 'mcb_1p', engine: 'mcb1', prefix: 'F', terms: {'1': '1', '2': '2'}),
    const LabPartDef(
        key: 'mcb2', nameAr: 'قاطع MCB قطبان', category: 'الحماية', sprite: 'mcb_2p', engine: 'mcb2', prefix: 'F', terms: {'1': '1', '2': '2', '3': '3', '4': '4'}),
    const LabPartDef(
        key: 'mcb3', nameAr: 'قاطع MCB ثلاثة أقطاب', category: 'الحماية', sprite: 'mcb_3p', engine: 'mcb3', prefix: 'Q',
        terms: {'1': '1', '2': '2', '3': '3', '4': '4', '5': '5', '6': '6'}),
    const LabPartDef(
        key: 'mcb4', nameAr: 'قاطع MCB أربعة أقطاب', category: 'الحماية', sprite: 'mcb_4p', engine: 'mcb4', prefix: 'Q',
        terms: {'1': '1', '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', '7': '7', '8': '8'}),
    const LabPartDef(
        key: 'mpcb', nameAr: 'قاطع حماية المحرك MPCB', category: 'الحماية', sprite: 'mpcb', engine: 'mpcb', prefix: 'Q',
        terms: {'1_L1': '1', '2_T1': '2', '3_L2': '3', '4_T2': '4', '5_L3': '5', '6_T3': '6'}, params: {'set': 8.5}),
    const LabPartDef(
        key: 'rccb', nameAr: 'قاطع التسرب الأرضي RCCB', category: 'الحماية', sprite: 'rccb', engine: 'rccb', prefix: 'Q',
        terms: {'1': '1', '2': '2', 'N': 'N', 'N2': 'N2'}),
    const LabPartDef(key: 'fuse', nameAr: 'حامل مصهر', category: 'الحماية', sprite: 'fuse_holder', engine: 'fuse', prefix: 'F', terms: {'1': '1', '2': '2'}),
    const LabPartDef(
        key: 'kc', nameAr: 'كونتاكتور', category: 'الكونتاكتورات', sprite: 'contactor', engine: 'kc', prefix: 'K', terms: _contactorTerms, params: {'coilV': 220.0}),
    const LabPartDef(
        key: 'kc_rev', nameAr: 'كونتاكتور عاكس: كونتاكتوران بينهما منع تداخل ميكانيكي', category: 'الكونتاكتورات', sprite: 'contactor', engine: 'kc', prefix: 'K',
        terms: _contactorTerms, params: {'coilV': 220.0}),
    const LabPartDef(
        key: 'aux', nameAr: 'بلوك نقاط مساعدة', category: 'الكونتاكتورات', sprite: 'aux_block', engine: 'aux', prefix: 'K',
        terms: {'53': '53', '54': '54', '61': '61', '62': '62', '71': '71', '72': '72', '83': '83', '84': '84'}, attachTo: 'kc'),
    const LabPartDef(
        key: 'ol', nameAr: 'أوفرلود يُركَّب على الكونتاكتور (خرج فقط)', category: 'الكونتاكتورات', sprite: 'overload', engine: 'ol', prefix: 'F',
        terms: {'2_T1': '2', '4_T2': '4', '6_T3': '6', '95': '95', '96': '96', '97': '97', '98': '98'}, params: {'set': 8.5}, attachTo: 'kc'),
    const LabPartDef(
        key: 'ol_free', nameAr: 'أوفرلود مستقل بدخل وخرج (على القضيب)', category: 'الكونتاكتورات', sprite: 'overload', engine: 'ol', prefix: 'F',
        terms: {'2_T1': '2', '4_T2': '4', '6_T3': '6', '95': '95', '96': '96', '97': '97', '98': '98'}, params: {'set': 8.5},
        extraTerms: {'1': (7.5, 5.0), '3': (18.5, 5.0), '5': (29.5, 5.0)}),
    const LabPartDef(
        key: 'relay', nameAr: 'مرحّل مساعد بقاعدته', category: 'المرحلات والمؤقتات', sprite: 'relay_my4', engine: 'relay', prefix: 'KA',
        terms: {'13': 'A1', '14': 'A2', '9': '11', '1': '12', '5': '14', '10': '21', '2': '22', '6': '24'}, params: {'coilV': 220.0}),
    const LabPartDef(
        key: 'timer', nameAr: 'مؤقت إلكتروني', category: 'المرحلات والمؤقتات', sprite: 'timer_din', engine: 'timer', prefix: 'KT',
        terms: {'A1': 'A1', 'A2': 'A2', '15': '15', '16': '16', '18': '18'}, params: {'mode': 'on', 'T': 5.0}),
    const LabPartDef(
        key: 'tsd', nameAr: 'مؤقت ستار دلتا', category: 'المرحلات والمؤقتات', sprite: 'timer_star_delta', engine: 'tsd', prefix: 'KT',
        terms: {'A1': 'A1', 'A2': 'A2', '17': '17', '18': '18', '28': '28'}, params: {'T': 5.0}),
    const LabPartDef(
        key: 'phr', nameAr: 'مرحّل مراقبة الأطوار', category: 'المرحلات والمؤقتات', sprite: 'phase_relay', engine: 'phr', prefix: 'KF',
        terms: {'L1': 'L1', 'L2': 'L2', 'L3': 'L3', '11': '11', '12': '12', '14': '14'}),
    const LabPartDef(
        key: 'pb_green', nameAr: 'ضاغط تشغيل NO', category: 'الضواغط والإشارة', sprite: 'pb_green_metal_face', engine: 'pb_no', prefix: 'S',
        side: ['13', '14'], params: {'col': 'g'}, mount: Mount.free),
    const LabPartDef(
        key: 'pb_black', nameAr: 'ضاغط NO (أمر إضافي)', category: 'الضواغط والإشارة', sprite: 'pb_green_metal_face', engine: 'pb_no', prefix: 'S',
        side: ['13', '14'], params: {'col': 'k'}, mount: Mount.free),
    const LabPartDef(
        key: 'pb_red', nameAr: 'ضاغط إيقاف NC', category: 'الضواغط والإشارة', sprite: 'pb_red_plastic_face', engine: 'pb_nc', prefix: 'S',
        side: ['11', '12'], params: {'col': 'r'}, mount: Mount.free),
    const LabPartDef(
        key: 'estop', nameAr: 'مفتاح طوارئ', category: 'الضواغط والإشارة', sprite: 'estop_face', engine: 'estop', prefix: 'S',
        side: ['11', '12'], mount: Mount.free),
    const LabPartDef(
        key: 'selector', nameAr: 'مفتاح اختيار 0-1', category: 'الضواغط والإشارة', sprite: 'selector_face', engine: 'sel', prefix: 'S',
        side: ['13', '14'], mount: Mount.free),
    const LabPartDef(
        key: 'lamp_green', nameAr: 'لمبة بيان خضراء', category: 'الضواغط والإشارة', sprite: 'lamp_green_face', engine: 'lamp', prefix: 'H',
        side: ['X1', 'X2'], params: {'col': 'g', 'V': 220.0}, mount: Mount.free),
    const LabPartDef(
        key: 'lamp_red', nameAr: 'لمبة بيان حمراء', category: 'الضواغط والإشارة', sprite: 'lamp_red_face', engine: 'lamp', prefix: 'H',
        side: ['X1', 'X2'], params: {'col': 'r', 'V': 220.0}, mount: Mount.free),
    const LabPartDef(
        key: 'lamp_amber', nameAr: 'لمبة بيان صفراء', category: 'الضواغط والإشارة', sprite: 'lamp_amber_face', engine: 'lamp', prefix: 'H',
        side: ['X1', 'X2'], params: {'col': 'y', 'V': 220.0}, mount: Mount.free),
    const LabPartDef(
        key: 'siren', nameAr: 'سرينة إنذار 230 فولت', category: 'الضواغط والإشارة', sprite: 'siren', engine: 'lamp', prefix: 'H',
        side: ['X1', 'X2'], params: {'V': 220.0, 'snd': 'siren', 'col': 'r'}, mount: Mount.free),
    LabPartDef(
        key: 'motor', nameAr: 'محرك 3 أطوار بستة أطراف (اربط نجمة أو دلتا بنفسك)', category: 'المحركات', sprite: 'motor', engine: 'motor', prefix: 'M',
        params: const {'links': 'none', 'In': 8.5}, mount: Mount.free, extraTerms: MotorPlate.terms()),
    LabPartDef(
        key: 'motor_d', nameAr: 'محرك 3 أطوار بقناطر دلتا جاهزة', category: 'المحركات', sprite: 'motor', engine: 'motor', prefix: 'M',
        params: const {'links': 'delta', 'In': 8.5}, mount: Mount.free, extraTerms: MotorPlate.terms()),
    LabPartDef(
        key: 'motor_s', nameAr: 'محرك 3 أطوار بقناطر نجمة جاهزة', category: 'المحركات', sprite: 'motor', engine: 'motor', prefix: 'M',
        params: const {'links': 'star', 'In': 5.0}, mount: Mount.free, extraTerms: MotorPlate.terms()),
    LabPartDef(
        key: 'motor1', nameAr: 'محرك أحادي الطور بمكثف', category: 'المحركات', sprite: 'motor', engine: 'motor1', prefix: 'M',
        params: const {'In': 4.0}, mount: Mount.free, extraTerms: MotorPlate.terms1()),
    const LabPartDef(
        key: 'mach_cart', nameAr: 'عربة على قضيب بمفتاحي نهاية شوط', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'cart'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_hoist', nameAr: 'ونش كهربائي (رفع وإنزال)', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'hoist'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_lift', nameAr: 'مصعد بثلاثة أدوار', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'lift'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_tank', nameAr: 'خزان بطلمبة وعوّامتين', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'tank'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_sort', nameAr: 'سير فرز المعادن (4 حساسات وصمام بستم)', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'sort'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_press', nameAr: 'مكبس نيوماتيك (3 حساسات وصمام)', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'press'}, mount: Mount.free),
    const LabPartDef(
        key: 'mach_fill', nameAr: 'خط تعبئة زجاجات (حساسين وصمام تعبئة)', category: 'الآلات والحساسات', sprite: '', engine: 'mach', prefix: 'W',
        params: {'kind': 'fill'}, mount: Mount.free),
    const LabPartDef(
        key: 'limit', nameAr: 'مفتاح نهاية الشوط', category: 'المحركات والحساسات', sprite: 'limit_roller', engine: 'ls', prefix: 'B',
        terms: {'21': '11', '22': '12', '13': '23', '14': '24'}, mount: Mount.free),
    const LabPartDef(key: 'tb', nameAr: 'طرف توصيل', category: 'التمديدات', sprite: 'terminal_block', engine: 'tb', prefix: 'X', terms: {'X1_1': '1', 'X1_2': '2'}),
    const LabPartDef(key: 'din_rail', nameAr: 'قضيب أوميجا 35 ملم', category: 'التمديدات', sprite: 'din_rail', engine: '', prefix: 'R', mount: Mount.free),
  ])
    d.key: d
};

/// The motor sprite has no terminal empties: its terminal plate is drawn by the lab
/// (six studs U1 V1 W1 / W2 U2 V2 and PE) at a fixed place under the motor body.
class MotorPlate {
  static const w = 220.0, h = 182.0; // mm, the motor part frame
  static const plateX = 79.0, plateY = 4.0, plateW = 70.0, plateH = 42.0;
  static Map<String, (double, double)> terms() => {
        'U1': (plateX + 12, plateY + 13),
        'V1': (plateX + 35, plateY + 13),
        'W1': (plateX + 58, plateY + 13),
        'W2': (plateX + 12, plateY + 31),
        'U2': (plateX + 35, plateY + 31),
        'V2': (plateX + 58, plateY + 31),
        'PE': (plateX + plateW + 12, plateY + 21),
      };

  /// single-phase motor: main winding U1-U2 (left), capacitor winding Z1-Z2 (right)
  static Map<String, (double, double)> terms1() => {
        'U1': (plateX + 12, plateY + 13),
        'Z1': (plateX + 58, plateY + 13),
        'U2': (plateX + 12, plateY + 31),
        'Z2': (plateX + 58, plateY + 31),
        'PE': (plateX + plateW + 12, plateY + 21),
      };
}

/// width of the terminal lug beside a face-on door device (mm)
const double kLug = 13;

/// Machines are drawn by the lab; their switch terminals sit on a strip along the bottom:
/// switch n → Sn1 Sn2 (NC) · Sn3 Sn4 (NO).
class MachineGeo {
  static Size size(String kind) => switch (kind) {
        // the machines' frames follow their Blender sprites (assets/panel/machine_sprites.json)
        'cart' => const Size(360, 210),
        'hoist' => const Size(260, 280),
        'lift' => const Size(240, 480),
        'tank' => const Size(240, 320),
        'sort' => const Size(420, 300),
        'press' => const Size(300, 400),
        'fill' => const Size(400, 300),
        _ => const Size(300, 200),
      };

  static Map<String, (double, double)> terms(String kind) {
    final n = machSwitches(kind);
    final valve = machValve(kind);
    final sz = size(kind);
    const pitch = 9.0, gap = 13.0;
    final total = n * 4 * pitch + (n - 1) * gap + (valve ? gap + 2 * pitch : 0);
    var x0 = (sz.width - total) / 2 + pitch / 2;
    final out = <String, (double, double)>{};
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= 4; j++) {
        out['S$i$j'] = (x0 + (j - 1) * pitch, sz.height - 9);
      }
      x0 += 4 * pitch + gap;
    }
    if (valve) {
      out['A1'] = (x0, sz.height - 9);
      out['A2'] = (x0 + pitch, sz.height - 9);
    }
    return out;
  }
}

const kStructural = {'din_rail'};
