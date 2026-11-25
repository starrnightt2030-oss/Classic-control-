// Machines the schematic drives: a cart, a hoist, a three-floor lift, a sorting
// conveyor, a pneumatic press and a bottle-filling line. Each machine is bound to
// the drawing by device tags (M1, B1, Y1…): it reads the motors and valve coils of
// the running simulation and moves its own sensors and limit switches.
import 'dart:math' as math;

/// what a machine needs from the running circuit, by device tag
abstract class PlantIo {
  /// signed speed of the motor (−1…1), 0 when it is not running
  double motor(String tag);

  /// is the load (valve coil, lamp) with this tag energised
  bool on(String tag);

  /// set a sensor / limit switch
  void sense(String tag, bool active);

  /// is there a device with this tag in the drawing
  bool has(String tag);
}

class PlantTag {
  final String tag, role, nameAr; // role: motor · valve · sensor
  /// not used by the ready-made solution (for the student's own improvements)
  final bool extra;
  const PlantTag(this.tag, this.role, this.nameAr, {this.extra = false});
}

class PlantDef {
  final String key, title, desc, task, ready;
  final List<PlantTag> tags;
  final Plant Function() make;
  const PlantDef(this.key, this.title, this.desc, this.task, this.ready, this.tags, this.make);
}

class Box {
  static int _ids = 0;

  /// stays the same while the box is on the machine (the 3D scene follows it by id)
  final int id = ++_ids;
  double s; // position along the belt 0…1 (1 = end stop)
  final bool metal;
  double dwell = 0, fill = 0;
  bool pressed = false;
  Box(this.s, {this.metal = false});
}

abstract class Plant {
  String get key;
  double t = 0;
  final Map<String, bool> _last = {};

  /// counters shown under the scene
  final Map<String, int> count = {};
  void step(double dt, PlantIo io);

  void tick(double dt, PlantIo io) {
    t += dt;
    step(dt, io);
  }

  /// report a sensor only when it changes, so a student can still press it by hand
  void put(PlantIo io, String tag, bool v) {
    if (_last[tag] == v) return;
    _last[tag] = v;
    io.sense(tag, v);
  }

  void bump(String k) => count[k] = (count[k] ?? 0) + 1;

  /// sensor states as the machine last reported them (for the scene's lamps)
  bool sensor(String tag) => _last[tag] ?? false;

  /// a new simulation started: report every sensor again on the next step
  void resync() => _last.clear();

  /// a tap on the scene (0–1 across, 0–1 down): place or take a part
  void tap(double x, double y) {}
}

/// cart on a track between LS1 (left) and LS2 (right); M1 forward drives right
class CartPlant extends Plant {
  @override
  String get key => 'cart';
  double x = 0.5;
  @override
  void step(double dt, PlantIo io) {
    final was = x;
    x = (x + io.motor('M1') * 0.16 * dt).clamp(0.0, 1.0).toDouble();
    if (was > 0.02 && x <= 0.02 || was < 0.98 && x >= 0.98) bump('رحلات');
    put(io, 'LS1', x <= 0.02);
    put(io, 'LS2', x >= 0.98);
  }
}

/// hoist: M1 forward lifts the hook; B1 bottom limit, B2 top limit
class HoistPlant extends Plant {
  @override
  String get key => 'hoist';
  double z = 0;
  @override
  void step(double dt, PlantIo io) {
    final was = z;
    z = (z + io.motor('M1') * 0.12 * dt).clamp(0.0, 1.0).toDouble();
    if (was < 0.98 && z >= 0.98) bump('رفعات');
    put(io, 'B1', z <= 0.02);
    put(io, 'B2', z >= 0.98);
  }
}

/// three-floor lift: M1 forward goes up; floor switches B1 B2 B3
class LiftPlant extends Plant {
  @override
  String get key => 'lift';
  static const floors = [0.0, 0.5, 1.0];
  double z = 0, door = 1; // door 1 = open
  @override
  void step(double dt, PlantIo io) {
    final v = io.motor('M1');
    z = (z + v * 0.09 * dt).clamp(0.0, 1.0).toDouble();
    var at = -1;
    for (var i = 0; i < 3; i++) {
      final a = (z - floors[i]).abs() <= 0.015;
      put(io, 'B${i + 1}', a);
      if (a) at = i;
    }
    final open = v.abs() < 0.01 && at >= 0;
    final was = door;
    door = (door + (open ? 1.5 : -3) * dt).clamp(0.0, 1.0).toDouble();
    if (was < 1 && door >= 1) bump('وقفات');
  }

  int get floor {
    var best = 0;
    for (var i = 1; i < 3; i++) {
      if ((z - floors[i]).abs() < (z - floors[best]).abs()) best = i;
    }
    return best;
  }
}

/// belt sorting: M1 drives the belt, B2 (inductive) sees metal in front of the
/// pusher, Y1 pushes it into the bin; B1 (photo) sees a box at the end stop
class SortPlant extends Plant {
  @override
  String get key => 'sort';
  final boxes = <Box>[];
  double ext = 0; // pusher 0 retracted … 1 out
  double _feed = 1.2;
  final _r = math.Random(3);
  double belt = 0; // belt travel, for the moving slats
  static const sensorAt = 0.6, endAt = 1.0;
  @override
  void step(double dt, PlantIo io) {
    final v = math.max(0.0, io.motor('M1'));
    belt += v * 0.11 * dt;
    // feeder puts a box on the belt while it runs
    _feed -= dt * (v > 0.05 ? 1 : 0);
    if (_feed <= 0 && boxes.where((b) => b.s < 0.15).isEmpty && boxes.length < 7) {
      boxes.add(Box(0, metal: _r.nextDouble() < 0.5));
      _feed = 2.2;
    }
    for (final b in boxes) {
      b.s = math.min(endAt, b.s + v * 0.11 * dt);
      if (b.s >= endAt) b.dwell += dt;
    }
    // a worker takes the box at the end after a moment
    final taken = boxes.where((b) => b.dwell > 1.6).toList();
    for (final b in taken) {
      boxes.remove(b);
      bump(b.metal ? 'معدن فات' : 'بلاستيك');
    }
    final y1 = io.on('Y1');
    ext = (ext + (y1 ? 3.0 : -2.2) * dt).clamp(0.0, 1.0).toDouble();
    if (ext > 0.55) {
      final hit = boxes.where((b) => (b.s - sensorAt).abs() < 0.06).toList();
      for (final b in hit) {
        boxes.remove(b);
        bump(b.metal ? 'معدن اتفرز' : 'بلاستيك اتفرز غلط');
      }
    }
    put(io, 'B1', boxes.any((b) => b.s >= endAt - 0.03));
    put(io, 'B2', boxes.any((b) => b.metal && (b.s - sensorAt).abs() < 0.05));
    put(io, 'B3', ext < 0.05);
    put(io, 'B4', ext > 0.95);
  }

  @override
  void tap(double x, double y) {
    if (boxes.where((b) => b.s < 0.15).isEmpty) boxes.add(Box(0, metal: x > 0.5));
  }
}

/// pneumatic press: Y1 drives the ram down (spring return), B1 ram up, B2 ram down,
/// B3 (photo) a part in the die
class PressPlant extends Plant {
  @override
  String get key => 'press';
  double ext = 0;
  Box? part = Box(0.5);
  double _wait = 0;
  @override
  void step(double dt, PlantIo io) {
    final y1 = io.on('Y1');
    ext = (ext + (y1 ? 1.6 : -1.3) * dt).clamp(0.0, 1.0).toDouble();
    final p = part;
    if (p != null && ext > 0.95 && !p.pressed) {
      p.pressed = true;
      bump('قطع اتكبست');
    }
    if (p != null && p.pressed && ext < 0.05) {
      _wait += dt;
      if (_wait > 1.0) {
        part = null; // ejected
        _wait = 0;
      }
    } else if (p == null) {
      _wait += dt;
      if (_wait > 1.2) {
        part = Box(0.5);
        _wait = 0;
      }
    }
    put(io, 'B1', ext < 0.05);
    put(io, 'B2', ext > 0.95);
    put(io, 'B3', part != null && !(part!.pressed));
  }

  @override
  void tap(double x, double y) {
    part ??= Box(0.5);
  }
}

/// bottle filling: M1 belt, B1 (photo) bottle under the nozzle, Y1 filling valve,
/// B2 level probe: the bottle under the nozzle is full
class FillPlant extends Plant {
  @override
  String get key => 'fill';
  final bottles = <Box>[];
  double _feed = 0.5, belt = 0;
  static const nozzle = 0.5;
  @override
  void step(double dt, PlantIo io) {
    final v = math.max(0.0, io.motor('M1'));
    belt += v * 0.1 * dt;
    _feed -= dt * (v > 0.05 ? 1 : 0);
    if (_feed <= 0 && bottles.where((b) => b.s < 0.2).isEmpty) {
      bottles.add(Box(0));
      _feed = 3.0;
    }
    for (final b in bottles) {
      b.s += v * 0.1 * dt;
    }
    final under = bottles.where((b) => (b.s - nozzle).abs() < 0.03).toList();
    final y1 = io.on('Y1');
    for (final b in under) {
      if (y1) b.fill = math.min(1.0, b.fill + 0.32 * dt);
    }
    if (y1 && under.isEmpty) bump('مية وقعت على السير');
    final out = bottles.where((b) => b.s > 1.05).toList();
    for (final b in out) {
      bottles.remove(b);
      bump(b.fill >= 0.95 ? 'زجاجات مليانة' : 'زجاجات ناقصة');
    }
    put(io, 'B1', under.isNotEmpty);
    put(io, 'B2', under.any((b) => b.fill >= 0.95));
  }
}

const kPlants = <PlantDef>[
  PlantDef('cart', 'عربة نقل رايح جاي', 'عربة على قضبان بيحركها الموتور M1 بين مفتاحين نهاية شوط LS1 (شمال) وLS2 (يمين).',
      'ارسم دايرة عكس حركة: K1 يودّي العربة يمين وK2 يرجّعها. خلّي العربة ترجع لوحدها لما تلمس LS2، وتقف أو ترجع تاني عند LS1.', 'c_rev_auto', [
    PlantTag('M1', 'motor', 'موتور العربة (أمام = يمين)'),
    PlantTag('LS1', 'sensor', 'نهاية الشوط الشمال'),
    PlantTag('LS2', 'sensor', 'نهاية الشوط اليمين'),
  ], CartPlant.new),
  PlantDef('hoist', 'ونش رفع', 'ونش بيرفع حمل بالموتور M1، ومعاه مفتاح حد سفلي B1 وعلوي B2.',
      'S1 يرفع وS2 ينزّل طول ما إنت ضاغط. مفتاح الحد العلوي B2 يوقف الرفع، والسفلي B1 يوقف التنزيل، ولازم يبقى فيه منع تداخل بين K1 وK2.', 'x_hoist', [
    PlantTag('M1', 'motor', 'موتور الونش (أمام = رفع)'),
    PlantTag('B1', 'sensor', 'حد سفلي'),
    PlantTag('B2', 'sensor', 'حد علوي'),
  ], HoistPlant.new),
  PlantDef('lift', 'أسانسير 3 أدوار', 'كابينة أسانسير بيحركها الموتور M1، وفي كل دور حساس: B1 للأرضي، وB2 للأول، وB3 للتاني.',
      'زراير الطلب S1 وS2 وS3. الطلب لازم يتحفظ في ريليه لحد ما الكابينة توصل الدور. الكابينة تطلع لو الدور المطلوب فوقها وتنزل لو تحتها، وتقف عند حساس الدور.', 'x_lift', [
    PlantTag('M1', 'motor', 'موتور الأسانسير (أمام = طلوع)'),
    PlantTag('B1', 'sensor', 'حساس الدور الأرضي'),
    PlantTag('B2', 'sensor', 'حساس الدور الأول'),
    PlantTag('B3', 'sensor', 'حساس الدور التاني'),
  ], LiftPlant.new),
  PlantDef('sort', 'سير فرز المعادن', 'سير بيحركه M1 وعليه كراتين معدن وبلاستيك. الحساس الحثي B2 بيشوف المعدن قدام البستم Y1، والفوتوسل B1 بيشوف الكرتونة في آخر السير، والحساسين B3 وB4 بيبينوا البستم راجع ولا طالع.',
      'شغّل السير بضاغط تشغيل وإيقاف. أي كرتونة معدن توصل قدام البستم، البستم يزقها في صندوق المعادن. البلاستيك يكمّل لآخر السير.', 'x_sort', [
    PlantTag('M1', 'motor', 'موتور السير'),
    PlantTag('Y1', 'valve', 'ملف صمام البستم'),
    PlantTag('B1', 'sensor', 'فوتوسل آخر السير', extra: true),
    PlantTag('B2', 'sensor', 'حساس حثي للمعدن'),
    PlantTag('B3', 'sensor', 'ريد: البستم راجع', extra: true),
    PlantTag('B4', 'sensor', 'ريد: البستم طالع', extra: true),
  ], SortPlant.new),
  PlantDef('press', 'مكبس نيوماتيك', 'مكبس بيشتغل بالهوا: ملف الصمام Y1 بينزّل الذراع، ولما يتفصل الياي بيرجّعها. B1 بيبين إن الذراع فوق، وB2 إنها تحت، وB3 فوتوسل بيشوف القطعة.',
      'ضغطة على S1 تعمل دورة كبس واحدة، بشرط تكون القطعة موجودة (B3). الذراع تنزل لحد B2 وبعدين ترجع لوحدها.', 'x_press', [
    PlantTag('Y1', 'valve', 'ملف صمام المكبس'),
    PlantTag('B1', 'sensor', 'ريد: الذراع فوق', extra: true),
    PlantTag('B2', 'sensor', 'ريد: الذراع تحت'),
    PlantTag('B3', 'sensor', 'فوتوسل: القطعة موجودة'),
  ], PressPlant.new),
  PlantDef('fill', 'خط تعبئة زجاجات', 'سير بيحركه M1 وعليه زجاجات فاضية. الفوتوسل B1 بيشوف الزجاجة تحت البزبوز، وصمام التعبئة Y1، وحساس المستوى B2 بيبين إن الزجاجة اتملت.',
      'السير يمشي لحد ما زجاجة توصل تحت البزبوز، فيقف ويفتح Y1. لما B2 يحس إنها اتملت يقفل Y1 والسير يكمّل.', 'x_fill', [
    PlantTag('M1', 'motor', 'موتور السير'),
    PlantTag('Y1', 'valve', 'صمام التعبئة'),
    PlantTag('B1', 'sensor', 'فوتوسل تحت البزبوز'),
    PlantTag('B2', 'sensor', 'حساس مستوى الزجاجة'),
  ], FillPlant.new),
];

PlantDef? plantByKey(String? k) {
  for (final p in kPlants) {
    if (p.key == k) return p;
  }
  return null;
}
