import 'dart:ui';

import 'package:classic_control/schem/model.dart';
import 'package:classic_control/schem/sheet_paint.dart';
import 'package:classic_control/schem/symbols.dart';
import 'package:classic_control/sim/engine.dart';
import 'package:flutter_test/flutter_test.dart';

bool _orthogonal(List<Offset> r) {
  for (var i = 0; i < r.length - 1; i++) {
    final a = r[i], b = r[i + 1];
    if ((a.dx - b.dx).abs() > 0.01 && (a.dy - b.dy).abs() > 0.01) return false;
  }
  return true;
}

void main() {
  test('every library symbol is listed once and paints in every turn', () {
    final listed = [for (final (_, _, keys) in kSymCategories) ...keys];
    expect(listed.toSet().length, listed.length, reason: 'no symbol twice in the library');
    for (final k in listed) {
      expect(kSyms.containsKey(k), isTrue, reason: k);
    }
    expect(kSyms.keys.toSet(), listed.toSet(), reason: 'every symbol is reachable from the library');
    final names = kSyms.values.map((d) => d.nameAr).toList();
    expect(names.toSet().length, names.length, reason: 'the quiz needs distinct names');
    for (final d in kSyms.values) {
      for (final rot in [0, 1, 2, 3]) {
        for (final flip in [false, true]) {
          for (final look in [null, const SymLook(), const SymLook(closed: true, energised: true), const SymLook(fault: true, note: 'X')]) {
            final rec = PictureRecorder();
            final c = Canvas(rec);
            symTransform(c, d.w, d.h, rot, flip);
            paintSymbol(c, d, look: look, tag: 'X1', rot: rot, flip: flip);
            rec.endRecording();
          }
        }
      }
    }
  });

  test('turning and mirroring move the pins with the symbol', () {
    final s = SPlaced('_1', 'mcb1', 5, 5, 'F1'); // 2 × 4, pin 1 on top, pin 2 below
    expect(s.pinPos(s.pin('1')!), const Offset(6, 5));
    s.rot = 1; // a quarter turn clockwise: lies 4 × 2, pin 1 on the right
    expect(s.size, const Size(4, 2));
    expect(s.pinPos(s.pin('1')!), const Offset(9, 6));
    expect(s.pinPos(s.pin('2')!), const Offset(5, 6));
    expect(s.pinDir(s.pin('1')!), const Offset(1, 0));
    s.rot = 2;
    expect(s.pinPos(s.pin('1')!), const Offset(6, 9));
    expect(s.pinDir(s.pin('1')!), const Offset(0, 1));
    s.rot = 3;
    expect(s.pinPos(s.pin('1')!), const Offset(5, 6));
    expect(s.pinDir(s.pin('1')!), const Offset(-1, 0));
    final m = SPlaced('_2', 'mcb3', 0, 0, 'Q1', flip: true);
    expect(m.pinPos(m.pin('1')!), const Offset(5, 0), reason: 'pole 1 moves to the right edge');
    expect(m.pinPos(m.pin('5')!), const Offset(1, 0));
    // pins of every symbol stay on its footprint in every turn
    for (final d in kSyms.values) {
      for (final rot in [0, 1, 2, 3]) {
        for (final flip in [false, true]) {
          final p = SPlaced('_9', d.key, 3, 3, 'X', rot: rot, flip: flip);
          for (final pn in d.pins) {
            final o = p.pinPos(pn);
            expect(p.rect.inflate(0.01).contains(o), isTrue, reason: '${d.key} $rot $flip ${pn.id}');
          }
        }
      }
    }
    // saved with the drawing
    final doc = SchemDoc()..syms.addAll([SPlaced('_1', 'lamp', 2, 2, 'H1', rot: 3, flip: true)]);
    doc.wires.add(SWire('_1.X1', '_1.X2', c: 'gnye', pts: [const Offset(1, 1), const Offset(4, 1)]));
    final back = SchemDoc.fromJsonString(doc.toJsonString());
    expect(back.syms.single.rot, 3);
    expect(back.syms.single.flip, isTrue);
    expect(back.wires.single.c, 'gnye');
    expect(back.wires.single.pts, [const Offset(1, 1), const Offset(4, 1)]);
  });

  test('wires between turned symbols stay square, and a dragged leg keeps its pins', () {
    final d = SchemDoc();
    final a = SPlaced('_1', 'mcb1', 2, 2, 'F1', rot: 1); // pins point left / right
    final b = SPlaced('_2', 'lamp', 14, 8, 'H1'); // pins point up / down
    final c = SPlaced('_3', 'lamp', 2, 12, 'H2', rot: 3);
    d.syms.addAll([a, b, c]);
    final w1 = SWire('_1.1', '_2.X1'), w2 = SWire('_1.2', '_3.X1'), w3 = SWire('_2.X2', '_3.X2');
    d.wires.addAll([w1, w2, w3]);
    for (final w in d.wires) {
      final r = d.route(w)!;
      expect(_orthogonal(r), isTrue, reason: '${w.a} → ${w.b}: $r');
      expect(r.first, d.pinPos(w.a));
      expect(r.last, d.pinPos(w.b));
    }
    for (final w in d.wires) {
      final r = d.route(w)!;
      for (var leg = 0; leg < r.length - 1; leg++) {
        w.pts = dragLeg(r, leg, 1.5);
        final r2 = d.route(w)!;
        expect(_orthogonal(r2), isTrue, reason: 'leg $leg of ${w.a}: $r2');
        expect(r2.first, d.pinPos(w.a));
        expect(r2.last, d.pinPos(w.b));
        w.pts = null;
      }
    }
    // the student's bend points survive moving a symbol: the route re-squares itself
    w1.pts = dragLeg(d.route(w1)!, 0, -2);
    b.x += 3;
    b.y += 1;
    final r = d.route(w1)!;
    expect(_orthogonal(r), isTrue);
    expect(r.last, d.pinPos(w1.b));
    expect(wireDistance(d, w1, r[1]), lessThan(0.01));
  });

  test('three-phase supply block runs a motor through a breaker', () {
    final d = SchemDoc();
    final x = SPlaced('_1', 'sup3', 2, 1, 'X0'), q = SPlaced('_2', 'mcb3', 2, 6, 'Q1'), m = SPlaced('_3', 'motor3', 2, 12, 'M1', p: {'links': 'delta', 'In': 8.5});
    d.syms.addAll([x, q, m]);
    d.wires.addAll([
      SWire('_1.L1', '_2.1'),
      SWire('_1.L2', '_2.3'),
      SWire('_1.L3', '_2.5'),
      SWire('_2.2', '_3.U1'),
      SWire('_2.4', '_3.V1'),
      SWire('_2.6', '_3.W1'),
    ]);
    final s = d.toSim();
    final l = s.lab..setPower(true);
    l.run(4);
    expect(motorRunning(l, '_3'), isTrue);
    expect(l.events.any((e) => e.t == 'short'), isFalse);
    l.actuate('_2', 'mcb'); // switch the breaker off
    l.run(6);
    expect(motorRunning(l, '_3'), isFalse);
  });

  test('single-phase supply block lights a lamp, buzzer and heater', () {
    final d = SchemDoc();
    d.syms.addAll([
      SPlaced('_1', 'sup1', 2, 1, 'X0'),
      SPlaced('_2', 'lamp', 2, 6, 'H1'),
      SPlaced('_3', 'bz', 6, 6, 'P1'),
      SPlaced('_4', 'heat', 10, 6, 'E1'),
    ]);
    for (final id in ['_2', '_3', '_4']) {
      d.wires
        ..add(SWire('_1.L1', '$id.X1'))
        ..add(SWire('$id.X2', '_1.N'));
    }
    final l = d.toSim().lab..setPower(true);
    for (final id in ['_2', '_3', '_4']) {
      expect(l[id].s.v, greaterThan(200), reason: id);
    }
    expect(lookOf(d.syms[2], d.toSim()), isNotNull);
  });

  test('a 3-wire PNP sensor on a 24 V supply pulls in a 24 V relay; a float latches', () {
    final d = SchemDoc();
    final x = SPlaced('_1', 'sup1', 2, 1, 'X0'),
        g = SPlaced('_2', 'psu', 2, 6, 'G1'),
        b = SPlaced('_3', 'prox_ind', 2, 13, 'B1'),
        k = SPlaced('_4', 'coil_ka', 8, 20, 'KA1', p: {'coilV': 24.0}),
        f = SPlaced('_5', 'float_no', 14, 13, 'B2'),
        h = SPlaced('_6', 'lamp', 14, 20, 'H1', p: {'V': 24.0});
    d.syms.addAll([x, g, b, k, f, h]);
    d.wires.addAll([
      SWire('_1.L1', '_2.L'),
      SWire('_1.N', '_2.N'),
      SWire('_2.P', '_3.BN'),
      SWire('_2.M', '_3.BU'),
      SWire('_3.BK', '_4.A1'),
      SWire('_4.A2', '_2.M'),
      SWire('_2.P', '_5.23'),
      SWire('_5.24', '_6.X1'),
      SWire('_6.X2', '_2.M'),
    ]);
    final s = d.toSim();
    expect(s.warnings, isEmpty);
    final l = s.lab..setPower(true);
    l.run(0.5);
    expect(l['KA1'].s.on, isFalse);
    l.actuate('_3', 'ls', true); // a metal part in front of the sensor
    l.run(0.5);
    expect(l['KA1'].s.on, isTrue);
    l.actuate('_3', 'ls', false);
    l.run(0.5);
    expect(l['KA1'].s.on, isFalse);
    // the float is one shared device named by its tag
    l.actuate('B2', 'ls', true);
    l.run(2);
    expect(l['_6'].s.v, greaterThan(20), reason: 'float stays up and keeps the lamp on');
    expect(lookOf(f, s)!.closed, isTrue);
  });

  test('phase monitoring relay and disconnector', () {
    final d = SchemDoc();
    d.syms.addAll([
      SPlaced('_1', 'sup3', 2, 1, 'X0'),
      SPlaced('_2', 'isol3', 2, 6, 'Q0'),
      SPlaced('_3', 'phr', 2, 12, 'KF1'),
    ]);
    d.wires.addAll([
      SWire('_1.L1', '_2.1'),
      SWire('_1.L2', '_2.3'),
      SWire('_1.L3', '_2.5'),
      SWire('_2.2', '_3.L1'),
      SWire('_2.4', '_3.L2'),
      SWire('_2.6', '_3.L3'),
    ]);
    final l = d.toSim().lab..setPower(true);
    l.run(0.5);
    expect(l['_3'].s.on, isTrue, reason: 'all three phases in the right order');
    l.actuate('_2', 'mcb'); // open the disconnector
    l.run(0.5);
    expect(l['_3'].s.on, isFalse);
  });

  test('auto route handles every pair of pin directions', () {
    const dirs = [Offset(0, -1), Offset(0, 1), Offset(-1, 0), Offset(1, 0)];
    for (final da in dirs) {
      for (final db in dirs) {
        for (final b in const [Offset(6, 4), Offset(-5, 3), Offset(4, -6), Offset(0, 7), Offset(7, 0)]) {
          final r = autoRoute(Offset.zero, da, b, db);
          expect(_orthogonal(r), isTrue, reason: '$da $db $b: $r');
          expect(r.first, Offset.zero);
          expect(r.last, b);
        }
      }
    }
  });
}
