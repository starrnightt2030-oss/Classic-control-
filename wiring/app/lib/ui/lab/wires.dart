// Wire geometry for the board and the drawings: the route of each wire (the student's
// own bends, or the "tidy" router's), its path with rounded corners, and hit tests.
// The router is a port of the Control Academy panel-lab router: square legs only,
// round the parts, wires that share a run laid side by side, as few bends as it can.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../sim/model.dart';
import '../../sim/solver.dart';

/// grid pitch (mm), also the gap between wires running side by side
const double kPitch = 5.0;

/// board size (mm)
const boardSize = Size(1000, 620);

Offset? termAt(Sim s, String key) {
  final i = key.indexOf('.');
  final p = s.part(key.substring(0, i));
  if (p == null) return null;
  final id = key.substring(i + 1);
  if (!p.type.terms.any((t) => t.id == id)) return null;
  return p.termPos(id);
}

Offset termDirAt(Sim s, String key) {
  final i = key.indexOf('.');
  final p = s.part(key.substring(0, i));
  return p == null ? const Offset(0, 1) : p.termDir(key.substring(i + 1));
}

/// all the points of wire [i]: its two terminals and the bends between them
List<Offset>? wirePoints(Sim s, int i) {
  final w = s.wires[i];
  final a = termAt(s, w.a), b = termAt(s, w.b);
  if (a == null || b == null) return null;
  if (w.pts.isNotEmpty) return [a, ...w.pts, b];
  // no route yet: leave each terminal straight out, then one square corner
  final da = termDirAt(s, w.a), db = termDirAt(s, w.b);
  final sa = a + da * 10, sb = b + db * 10;
  final corner = da.dy != 0 ? Offset(sb.dx, sa.dy) : Offset(sa.dx, sb.dy);
  return [a, sa, corner, sb, b];
}

/// a polyline with rounded corners (radius in mm)
Path roundedPath(List<Offset> pts, {double rad = 5}) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1];
    final v1 = p1 - p0, v2 = p2 - p1;
    final l1 = v1.distance, l2 = v2.distance;
    if (l1 < .3 || l2 < .3) {
      p.lineTo(p1.dx, p1.dy);
      continue;
    }
    final rr = math.min(rad, math.min(l1, l2) / 2);
    final st = p1 - v1 / l1 * rr, en = p1 + v2 / l2 * rr;
    p.lineTo(st.dx, st.dy);
    p.quadraticBezierTo(p1.dx, p1.dy, en.dx, en.dy);
  }
  p.lineTo(pts.last.dx, pts.last.dy);
  return p;
}

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 < 1e-9) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// wire under [p] (mm), or null
int? hitWire(Sim s, Offset p, {double tol = 3.5}) {
  for (var i = s.wires.length - 1; i >= 0; i--) {
    final pts = wirePoints(s, i);
    if (pts == null) continue;
    for (var k = 0; k + 1 < pts.length; k++) {
      if (_segDist(p, pts[k], pts[k + 1]) < tol) return i;
    }
  }
  return null;
}

/// which leg of wire [i] is under [p]: index k of the segment pts[k]..pts[k+1]
int? hitLeg(Sim s, int i, Offset p, {double tol = 4}) {
  final pts = wirePoints(s, i);
  if (pts == null) return null;
  for (var k = 0; k + 1 < pts.length; k++) {
    if (_segDist(p, pts[k], pts[k + 1]) < tol) return k;
  }
  return null;
}

/// terminal under [p] (mm), or null
String? hitTerm(Sim s, Offset p, {double r = 6}) {
  String? best;
  var bd = r;
  for (final part in s.parts) {
    for (final t in part.type.terms) {
      final d = (part.termPos(t.id) - p).distance;
      if (d < bd) {
        bd = d;
        best = '${part.id}.${t.id}';
      }
    }
  }
  return best;
}

Part? hitPart(Sim s, Offset p) {
  for (final part in s.parts.reversed) {
    if (part.rect.contains(p)) return part;
  }
  return null;
}

// ---------------------------------------------------------------------- tidy
const _dirs = [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)];

int _dirIndex(Offset d) {
  if (d.dx.abs() >= d.dy.abs()) return d.dx >= 0 ? 0 : 2;
  return d.dy >= 0 ? 1 : 3;
}

/// Re-route the wires of [s] (all, or those in [only]). Returns how many got a route.
int tidyWires(Sim s, {Set<int>? only}) {
  const g = kPitch;
  final area = Offset.zero & boardSize;
  final ox = 0.0, oy = 0.0;
  final cols = (area.width / g).ceil() + 1, rows = (area.height / g).ceil() + 1;
  final n = cols * rows;
  final blocked = Uint8List(n);
  for (final p in s.parts) {
    final r = p.rect.inflate(1.5);
    final c0 = math.max(0, (r.left / g).ceil()), c1 = math.min(cols - 1, (r.right / g).floor());
    final r0 = math.max(0, (r.top / g).ceil()), r1 = math.min(rows - 1, (r.bottom / g).floor());
    for (var y = r0; y <= r1; y++) {
      for (var x = c0; x <= c1; x++) {
        blocked[y * cols + x] = 1;
      }
    }
  }
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows;

  (int, int, List<(int, int)>)? exitCell(String key, Offset t, Offset dir) {
    final owner = s.part(key.substring(0, key.indexOf('.')));
    final own = owner?.rect.inflate(1.5);
    bool mine(int x, int y) => own != null && own.contains(Offset(x * g + ox, y * g + oy));
    final d0 = _dirIndex(dir);
    (int, int, List<(int, int)>)? walk(int di, bool pushThrough) {
      final d = _dirs[di];
      var x = ((t.dx - ox) / g).round(), y = ((t.dy - oy) / g).round();
      final stub = <(int, int)>[];
      for (var k = 0; k < 80; k++) {
        if (!inside(x, y)) return null;
        stub.add((x, y));
        if (k >= 1 && blocked[y * cols + x] == 0) return (x, y, stub);
        if (k >= 1 && !pushThrough && !mine(x, y)) return null;
        x += d.dx.toInt();
        y += d.dy.toInt();
      }
      return null;
    }

    for (final di in [d0, 1, 3, (d0 + 2) % 4, 0, 2]) {
      final e = walk(di, false);
      if (e != null) return e;
    }
    (int, int, List<(int, int)>)? best;
    for (var di = 0; di < 4; di++) {
      final e = walk(di, true);
      if (e != null && (best == null || e.$3.length < best.$3.length)) best = e;
    }
    return best;
  }

  final order = [
    for (var i = 0; i < s.wires.length; i++)
      if (only == null || only.contains(i)) i
  ];
  final ends = <int, (Offset, Offset)>{};
  for (final i in order) {
    final a = termAt(s, s.wires[i].a), b = termAt(s, s.wires[i].b);
    if (a != null && b != null) ends[i] = (a, b);
  }
  order.removeWhere((i) => !ends.containsKey(i));
  final exits = <int, ((int, int, List<(int, int)>), (int, int, List<(int, int)>))>{};
  for (final i in order) {
    final w = s.wires[i];
    final (a, b) = ends[i]!;
    final ea = exitCell(w.a, a, termDirAt(s, w.a)), eb = exitCell(w.b, b, termDirAt(s, w.b));
    if (ea != null && eb != null) exits[i] = (ea, eb);
  }
  order.removeWhere((i) => !exits.containsKey(i));
  int heading(List<(int, int)> st) {
    if (st.length < 2) return 1;
    final (x0, y0) = st[st.length - 2];
    final (x1, y1) = st.last;
    return _dirIndex(Offset((x1 - x0).toDouble(), (y1 - y0).toDouble()));
  }

  // wires that keep their route still occupy the grid
  final baseUsed = Uint8List(n);
  void mark(Uint8List used, List<(int, int)> cells) {
    for (var k = 0; k + 1 < cells.length; k++) {
      final (x0, y0) = cells[k];
      final (x1, y1) = cells[k + 1];
      final bit = y0 == y1 ? 1 : 2;
      if (inside(x0, y0)) used[y0 * cols + x0] |= bit;
      if (inside(x1, y1)) used[y1 * cols + x1] |= bit;
    }
  }

  if (only != null) {
    for (var i = 0; i < s.wires.length; i++) {
      if (only.contains(i)) continue;
      final pts = wirePoints(s, i);
      if (pts == null) continue;
      for (var k = 0; k + 1 < pts.length; k++) {
        final a = pts[k], b = pts[k + 1];
        final steps = math.max(1, ((b - a).distance / g).round());
        final cells = <(int, int)>[
          for (var j = 0; j <= steps; j++) (((a.dx + (b.dx - a.dx) * j / steps) / g).round(), ((a.dy + (b.dy - a.dy) * j / steps) / g).round())
        ];
        mark(baseUsed, cells);
      }
    }
  }

  (Map<int, List<(int, int)>>, int) pass(List<int> seq) {
    final used = Uint8List.fromList(baseUsed);
    final out = <int, List<(int, int)>>{};
    var score = 0;
    for (final i in seq) {
      final (ea, eb) = exits[i]!;
      final r = _search(cols, rows, blocked, used, ea, eb, heading(ea.$3), (heading(eb.$3) + 2) % 4);
      if (r == null) {
        score += 100000;
        continue;
      }
      score += r.$2;
      final cells = <(int, int)>[...ea.$3, ...r.$1.skip(1), ...eb.$3.reversed.skip(1)];
      mark(used, cells);
      out[i] = cells;
    }
    return (out, score);
  }

  double len(int k) {
    final d = ends[k]!.$1 - ends[k]!.$2;
    return d.dx.abs() + d.dy.abs();
  }

  final shortFirst = [...order]..sort((i, j) => len(i).compareTo(len(j)));
  final p1 = pass(shortFirst);
  final p2 = order.length > 1 ? pass(shortFirst.reversed.toList()) : p1;
  final best = p1.$2 <= p2.$2 ? p1.$1 : p2.$1;
  for (final e in best.entries) {
    final (a, b) = ends[e.key]!;
    s.wires[e.key].pts = _corners(e.value, a, b, g, Offset(ox, oy));
  }
  return best.length;
}

(List<(int, int)>, int)? _search(
    int cols, int rows, Uint8List blocked, Uint8List used, (int, int, List<(int, int)>) s, (int, int, List<(int, int)>) t, int d0, int dEnd) {
  final n = cols * rows;
  const inf = 1 << 30;
  final cost = Int32List(n * 4)..fillRange(0, n * 4, inf);
  final from = Int32List(n * 4)..fillRange(0, n * 4, -1);
  final start = (s.$2 * cols + s.$1) * 4 + d0;
  final goal = t.$2 * cols + t.$1;
  int hdist(int cell) => ((cell % cols) - t.$1).abs() + ((cell ~/ cols) - t.$2).abs();
  final open = _Heap();
  cost[start] = 0;
  open.add(start, hdist(start ~/ 4));
  var expanded = 0;
  while (open.isNotEmpty) {
    final st = open.removeFirst();
    final cell = st ~/ 4, d = st % 4;
    if (cell == goal) {
      final out = <(int, int)>[];
      var k = st;
      while (k >= 0) {
        final c = k ~/ 4;
        out.add((c % cols, c ~/ cols));
        k = from[k];
      }
      final r = <(int, int)>[];
      for (final c in out.reversed) {
        if (r.isEmpty || r.last != c) r.add(c);
      }
      return (r, cost[st]);
    }
    if (++expanded > 400000) return null;
    final x = cell % cols, y = cell ~/ cols;
    for (var nd = 0; nd < 4; nd++) {
      if (nd == (d + 2) % 4) continue;
      final dd = _dirs[nd];
      final nx = x + dd.dx.toInt(), ny = y + dd.dy.toInt();
      if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
      final nc = ny * cols + nx;
      if (blocked[nc] == 1 && nc != goal) continue;
      final horiz = nd % 2 == 0;
      final u = used[nc];
      var step = 1 + (nd != d ? 12 : 0);
      if (u & (horiz ? 1 : 2) != 0) step += 30;
      if (u & (horiz ? 2 : 1) != 0) step += 2;
      if (nc == goal && nd != dEnd) step += 12;
      final ns = nc * 4 + nd;
      final c = cost[st] + step;
      if (c < cost[ns]) {
        cost[ns] = c;
        from[ns] = st;
        open.add(ns, c + hdist(nc));
      }
    }
  }
  return null;
}

List<Offset> _corners(List<(int, int)> cells, Offset a, Offset b, double g, Offset o) {
  final pts = <Offset>[];
  final bends = <int>[];
  for (var k = 1; k + 1 < cells.length; k++) {
    final h1 = cells[k - 1].$2 == cells[k].$2, h2 = cells[k].$2 == cells[k + 1].$2;
    if (h1 != h2) bends.add(k);
  }
  for (final k in bends) {
    pts.add(Offset(cells[k].$1 * g, cells[k].$2 * g) + o);
  }
  if (pts.isEmpty) return [Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2)];
  bool vert(int k) => cells[k].$1 == cells[k + 1].$1;
  pts[0] = vert(0) ? Offset(a.dx, pts[0].dy) : Offset(pts[0].dx, a.dy);
  final last = cells.length - 2;
  pts[pts.length - 1] = vert(last) ? Offset(b.dx, pts.last.dy) : Offset(pts.last.dx, b.dy);
  return pts;
}

class _Heap {
  final _s = <int>[], _p = <int>[];
  bool get isNotEmpty => _s.isNotEmpty;
  void add(int s, int p) {
    _s.add(s);
    _p.add(p);
    var i = _s.length - 1;
    while (i > 0) {
      final up = (i - 1) >> 1;
      if (_p[up] <= _p[i]) break;
      _swap(i, up);
      i = up;
    }
  }

  int removeFirst() {
    final top = _s[0];
    final ls = _s.removeLast(), lp = _p.removeLast();
    if (_s.isNotEmpty) {
      _s[0] = ls;
      _p[0] = lp;
      var i = 0;
      final len = _s.length;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < len && _p[l] < _p[m]) m = l;
        if (r < len && _p[r] < _p[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int i, int j) {
    final s = _s[i], p = _p[i];
    _s[i] = _s[j];
    _p[i] = _p[j];
    _s[j] = s;
    _p[j] = p;
  }
}
