// Panel lab editing: renaming parts, resizing them, clip-on blocks on either flank,
// and wires with hand-made bends.
import 'dart:ui';

import 'package:classic_control/lab/model.dart';
import 'package:classic_control/lab/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renaming a contactor carries its wires, clip-on block and interlock', () {
    final d = LabDoc();
    final k1 = Placed('K1', 'kc', 100, 100), k2 = Placed('K2', 'kc', 150, 100), aux = Placed('K3', 'aux', 0, 0, attach: 'K1');
    d.parts.addAll([k1, k2, aux]);
    d.mech.add(['K1', 'K2']);
    d.wires.add(LabWire('K1.A1', 'K3.53', 'rd'));
    expect(d.renamePart(k1, 'KM1'), isTrue);
    expect(d.wires.single.a, 'KM1.A1');
    expect(aux.attach, 'KM1');
    expect(d.mech.single, ['KM1', 'K2']);
    expect(d.label(aux), 'KM1', reason: 'a clip-on block is tagged with its contactor');
    expect(d.renamePart(k2, 'KM1'), isFalse, reason: 'names stay unique');
  });

  test('a resized part scales its terminals with it', () {
    final p = Placed('W1', 'mach_sort', 10, 20);
    final key = p.termsAbs().keys.last;
    final t0 = p.termsAbs()[key]!;
    p.p['scale'] = 1.5;
    final t1 = p.termsAbs()[key]!;
    expect(t1.dx - 10, closeTo((t0.dx - 10) * 1.5, 1e-9));
    expect(p.size.width, closeTo(p.baseSize.width * 1.5, 1e-9));
  });

  test('an auxiliary block goes on the right flank of the right-hand contactor', () {
    final host = Placed('K2', 'kc', 200, 100);
    final l = Placed('K3', 'aux', 0, 0), r = Placed('K4', 'aux', 0, 0, p: {'side': 'r'});
    placeAttached(l, host);
    placeAttached(r, host);
    expect(l.rect.right, lessThanOrEqualTo(host.rect.left + 4));
    expect(r.rect.left, greaterThanOrEqualTo(host.rect.right - 4));
  });

  test('wire bends survive saving', () {
    final d = LabDoc();
    d.parts.addAll([Placed('K1', 'kc', 100, 100), Placed('K2', 'kc', 200, 100)]);
    d.wires.add(LabWire('K1.A1', 'K2.A1', 'rd', [const Offset(120, 80), const Offset(220, 80)]));
    final e = LabDoc.fromJsonString(d.toJsonString());
    expect(e.wires.single.pts, [const Offset(120, 80), const Offset(220, 80)]);
  });

  test('a longer, wider plate keeps the parts on it and slides the bench along', () {
    final d = LabDoc()
      ..plateW = 400
      ..plateH = 300
      ..benchW = 300;
    final k = Placed('K1', 'kc', 100, 100), m = Placed('M1', 'motor', 450, 40);
    d.parts.addAll([k, m]);
    d.wires.add(LabWire('K1.A1', 'M1.U1', 'bk')..pts = [const Offset(120, 250), const Offset(460, 250)]);
    d.resizePlate(600, 900);
    expect(d.plateH, 900);
    expect(k.x, 100, reason: 'parts on the plate stay put');
    expect(m.x, 650, reason: 'the bench moved 200 mm right with its motor');
    expect(d.wires.single.pts, [const Offset(120, 250), const Offset(660, 250)]);
    d.resizePlate(50, 50);
    expect(d.plateW, greaterThanOrEqualTo(k.rect.right));
    expect(d.plateH, greaterThanOrEqualTo(k.rect.bottom));
    expect(m.x, greaterThanOrEqualTo(d.plateW + LabDoc.benchGap), reason: 'the bench never lands on the plate');
    final back = LabDoc.fromJsonString(d.toJsonString());
    expect(back.plateW, d.plateW);
    expect(back.plateH, d.plateH);
  });
}
