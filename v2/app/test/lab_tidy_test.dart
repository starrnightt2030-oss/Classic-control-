// Panel lab "tidy wiring": square routes round the parts, side by side, undo-able.
import 'package:classic_control/lab/catalog.dart';
import 'package:classic_control/lab/model.dart';
import 'package:classic_control/lab/templates.dart';
import 'package:classic_control/lab/tidy.dart';
import 'package:flutter_test/flutter_test.dart';

List<Offset> route(LabDoc d, LabWire w) => [d.termPos(w.a)!, ...w.pts, d.termPos(w.b)!];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Sprites.load();
  });

  test('every wire of the DOL example gets square legs that miss the other parts', () {
    final d = dolTemplate();
    for (final w in d.wires) {
      w.pts = [];
    }
    final n = tidyWires(d);
    expect(n, d.wires.length);
    for (final w in d.wires) {
      final r = route(d, w);
      expect(w.pts, isNotEmpty, reason: 'a tidied wire is never left as a free curve');
      final own = {w.a.split('.').first, w.b.split('.').first};
      for (var k = 0; k + 1 < r.length; k++) {
        final p = r[k], q = r[k + 1];
        expect((p.dx - q.dx).abs() < 0.01 || (p.dy - q.dy).abs() < 0.01, isTrue, reason: '${w.a}-${w.b} leg $k is square');
        // sample the leg: it must not cross a part it is not wired to
        for (var t = 0.0; t <= 1.0; t += 0.02) {
          final s = Offset.lerp(p, q, t)!;
          for (final part in d.parts) {
            if (part.structural || own.contains(part.id) || part.attach != null && own.contains(part.attach)) continue;
            if (own.any((o) => d.byId(o)?.attach == part.id)) continue;
            // door devices overlap lug to lug: a part over the terminal itself is let through
            if (part.rect.contains(r.first) || part.rect.contains(r.last)) continue;
            expect(part.rect.deflate(1).contains(s), isFalse, reason: '${w.a}-${w.b} runs over ${part.id}');
          }
        }
      }
    }
  });

  test('two wires over the same run are laid side by side, not on top of each other', () {
    final d = LabDoc()
      ..plateW = 500
      ..plateH = 400;
    d.parts.addAll([Placed('K1', 'kc', 60, 200), Placed('K2', 'kc', 330, 200)]);
    d.wires
      ..add(LabWire('K1.1', 'K2.1', 'bk'))
      ..add(LabWire('K1.3', 'K2.3', 'bk'));
    tidyWires(d);
    final r0 = route(d, d.wires[0]), r1 = route(d, d.wires[1]);
    double runY(List<Offset> r) {
      var best = 0.0, y = 0.0;
      for (var k = 0; k + 1 < r.length; k++) {
        final l = (r[k + 1].dx - r[k].dx).abs();
        if ((r[k].dy - r[k + 1].dy).abs() < 0.01 && l > best) {
          best = l;
          y = r[k].dy;
        }
      }
      return y;
    }

    expect((runY(r0) - runY(r1)).abs(), greaterThanOrEqualTo(kTidyPitch - 0.01));
  });

  test('tidy keeps a saved board loadable and is undone by restoring the snapshot', () {
    final d = dolTemplate();
    final before = d.toJsonString();
    tidyWires(d);
    final e = LabDoc.fromJsonString(d.toJsonString());
    expect(e.wires.length, d.wires.length);
    expect(LabDoc.fromJsonString(before).toJsonString(), before);
  });
}
