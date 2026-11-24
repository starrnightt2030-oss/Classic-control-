/// Library organisation: categories, display order and variant labels.
library;

class Category {
  final String id;
  final String nameAr;
  final List<String> components;
  const Category(this.id, this.nameAr, this.components);
}

const categories = <Category>[
  Category('protection', 'الحماية', ['mcb', 'rccb', 'mpcb', 'overload', 'fuse', 'electronic_protection']),
  Category('control', 'التحكم', [
    'contactor',
    'reversing_contactor',
    'aux_block',
    'control_relay',
    'timer',
    'pneumatic_timer',
    'control_transformer',
    'power_supply_24v',
  ]),
  Category('operator', 'الأزرار والإشارة', ['pushbutton', 'estop', 'selector', 'pilot_lamp', 'pb_station', 'rotary_switches', 'signaling']),
  Category('sensors', 'الحساسات', ['proximity_sensor', 'limit_switch', 'float_pressure']),
  Category('motors', 'المحركات والمشغّلات', ['motor', 'motor_1ph', 'solenoid_valve']),
  Category('measure', 'القياس والعدّة', ['panel_meter', 'current_transformer', 'tools']),
  Category('install', 'اللوحة والتركيب', ['enclosure', 'installation']),
];

String? categoryOf(String componentId) {
  for (final c in categories) {
    if (c.components.contains(componentId)) return c.id;
  }
  return null;
}

/// Arabic labels for model variants (file stem → label).
const variantLabels = <String, String>{
  'relay_my4': 'MY4 · 14 رجل',
  'relay_mk3p': 'MK3P · 11 رجل',
  'socket_8pin': 'قاعدة 8 رجل',
  'socket_11pin': 'قاعدة 11 رجل',
  'phase_relay': 'ريلاي الفازات',
  'voltage_monitor': 'مراقب الجهد',
  'va_protector': 'حماية جهد وتيار',
  'kwh_meter': 'عداد كيلووات',
  'counter': 'عداد نبضات',
  'estop': 'طوارئ',
  'estop_key': 'طوارئ بمفتاح',
  'estop_box': 'علبة طوارئ',
  'float_switch': 'عوامة',
  'pressure_switch': 'بريشر سويتش',
  'din_rail': 'دين ريل',
  'wire_duct': 'مجرى السلك',
  'terminal_block': 'ترمينال',
  'terminal_strip': 'شريحة ترامل',
  'ferrules_lugs': 'جلب وكوسات',
  'limit_roller': 'ببكرة',
  'limit_rod': 'بذراع',
  'limit_wand': 'بسلك',
  'limit_plunger': 'بكبّاس',
  'mcb_1p': '1P',
  'mcb_2p': '2P',
  'mcb_3p': '3P',
  'mcb_4p': '4P',
  'motor': 'الموتور',
  'motor_tbox_delta': 'علبة الترامل دلتا',
  'motor_tbox_star': 'علبة الترامل ستار',
  'ammeter': 'أميتر',
  'voltmeter': 'فولتميتر',
  'station_2': 'علبة زرارين',
  'station_3': 'علبة 3 زراير',
  'lamp_green': 'أخضر',
  'lamp_red': 'أحمر',
  'lamp_amber': 'كهرماني',
  'prox_inductive_m18': 'حثّي M18',
  'prox_capacitive_m30': 'سعوي M30',
  'prox_square': 'مربع',
  'photo_sensor': 'فوتوسيل',
  'pb_green_metal': 'أخضر معدن',
  'pb_red_plastic': 'أحمر بلاستيك',
  'pb_green_extended': 'أخضر بارز',
  'pb_double': 'مزدوج',
  'cam_switch': 'كام سويتش',
  'voltmeter_selector': 'سليكتور فولتميتر',
  'main_isolator': 'سكينة رئيسية',
  'beacon': 'فلاشر',
  'siren': 'سارينة',
  'signal_tower': 'برج إشارة',
  'timer_st3p': 'ST3P',
  'timer_din': 'تايمر دين ريل',
  'timer_star_delta': 'تايمر ستار دلتا',
  'multimeter': 'أفوميتر',
  'clamp_meter': 'كلامب ميتر',
  'test_leads': 'أطراف القياس',
  'wire_stripper': 'قشّارة',
  'ferrule_crimper': 'كبّاسة جلب',
  'screwdriver': 'مفك',
};

String variantLabel(String file) {
  final stem = file.endsWith('.glb') ? file.substring(0, file.length - 4) : file;
  return variantLabels[stem] ?? stem;
}
