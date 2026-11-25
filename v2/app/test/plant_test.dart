import 'dart:ui';

import 'package:classic_control/schem/plant_paint.dart';
import 'package:classic_control/schem/ladder.dart';
import 'package:classic_control/schem/model.dart';
import 'package:classic_control/schem/plant_io.dart';
import 'package:classic_control/sim/plant.dart';
import 'package:flutter_test/flutter_test.dart';

/// a ready circuit running its machine
class Rig {
  final SchemDoc d;
  final SchemSim s;
  final Plant p;
  final SchemPlantIo io;
  Rig._(this.d, this.s, this.p, this.io);
  factory Rig(String ready) {
    final r = readyById(ready)!;
    final d = r.build();
    final s = d.toSim();
    final p = plantByKey(r.plant)!.make();
    final io = SchemPlantIo(d, s);
    s.lab.setPower(true);
    final rig = Rig._(d, s, p, io);
    rig.run(0.2);
    return rig;
  }
  void run(double secs) {
    for (var t = 0.0; t < secs; t += 0.05) {
      s.lab.step(0.05);
      p.tick(0.05, io);
    }
  }

  String id(String tag, String sym) => d.syms.firstWhere((x) => x.tag == tag && x.sym == sym).id;
  void press(String tag, [double hold = 0.3]) {
    final i = id(tag, 'pb_no');
    s.lab.actuate(i, 'press', true);
    run(hold);
    s.lab.actuate(i, 'press', false);
  }
}

void main() {
  test('every machine has a ready circuit using its tags', () {
    for (final p in kPlants) {
      final r = readyById(p.ready);
      expect(r, isNotNull, reason: p.key);
      expect(r!.plant, p.key);
      final d = r.build();
      expect(d.toSim().warnings, isEmpty, reason: p.key);
      for (final t in p.tags.where((t) => !t.extra)) {
        expect(d.syms.any((s) => s.tag == t.tag), isTrue, reason: '${p.key} ${t.tag}');
      }
    }
  });

  test('cart shuttles between the limit switches', () {
    final r = Rig('c_rev_auto');
    final cart = r.p as CartPlant;
    r.press('S1');
    r.run(6);
    expect(cart.count['رحلات'] ?? 0, greaterThanOrEqualTo(1), reason: 'reached the right end');
    r.run(14);
    expect(cart.count['رحلات'] ?? 0, greaterThanOrEqualTo(2), reason: 'came back by itself');
  });

  test('hoist lifts while pressed and stops at the top limit', () {
    final r = Rig('x_hoist');
    final h = r.p as HoistPlant;
    r.press('S1', 12);
    expect(h.z, greaterThan(0.97));
    expect(r.s.lab['K1'].s.on, isFalse, reason: 'top limit opened the up contactor');
    r.press('S2', 12);
    expect(h.z, lessThan(0.03));
  });

  test('lift answers calls to every floor', () {
    final r = Rig('x_lift');
    final lift = r.p as LiftPlant;
    r.press('S3');
    r.run(16);
    expect(lift.floor, 2);
    expect(r.s.lab['K1'].s.on || r.s.lab['K2'].s.on, isFalse);
    r.press('S2');
    r.run(9);
    expect(lift.floor, 1, reason: 'down to the middle floor');
    r.press('S1');
    r.run(9);
    expect(lift.floor, 0);
    r.press('S2');
    r.run(9);
    expect(lift.floor, 1, reason: 'up to the middle floor');
  });

  test('sorting conveyor pushes metal boxes off', () {
    final r = Rig('x_sort');
    final p = r.p as SortPlant;
    r.press('S1');
    r.run(60);
    expect(p.count['معدن اتفرز'] ?? 0, greaterThan(2));
    expect(p.count['بلاستيك اتفرز غلط'] ?? 0, 0);
    expect(p.count['معدن فات'] ?? 0, 0);
  });

  test('press makes one stroke per start, only with a part', () {
    final r = Rig('x_press');
    final p = r.p as PressPlant;
    r.press('S1');
    r.run(4);
    expect(p.count['قطع اتكبست'], 1);
    r.run(4);
    expect(p.count['قطع اتكبست'], 1, reason: 'no second stroke without a new start');
    r.press('S1');
    r.run(4);
    expect(p.count['قطع اتكبست'], 2);
  });

  test('filling line fills every bottle', () {
    final r = Rig('x_fill');
    final p = r.p as FillPlant;
    r.press('S1');
    r.run(90);
    expect(p.count['زجاجات مليانة'] ?? 0, greaterThan(8));
    expect(p.count['زجاجات ناقصة'] ?? 0, 0);
    expect(p.count['مية وقعت على السير'] ?? 0, 0);
  });

  test('every machine scene paints, idle and running', () {
    for (final d in kPlants) {
      final r = Rig(d.ready);
      for (final io in [null, r.io]) {
        final rec = PictureRecorder();
        PlantPainter(r.p, io, 0).paint(Canvas(rec), const Size(320, 200));
        rec.endRecording();
      }
    }
  });
}
