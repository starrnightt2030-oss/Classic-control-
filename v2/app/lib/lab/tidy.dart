// Panel Lab "tidy wiring": re-route every wire the way a panel builder would lay it,
// square legs only, going round the parts, wires sharing a run laid side by side
// instead of on top of each other, and as few bends as the path allows.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'model.dart';

/// grid pitch (mm): also the spacing between wires that run side by side
const double kTidyPitch = 5.0;

const _dirs = [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)];

int _dirIndex(Offset d) {
  if (d.dx.abs() >= d.dy.abs()) return d.dx >= 0 ? 0 : 2;
  return d.dy >= 0 ? 1 : 3;
}

/// Re-route the wires of [doc] (all of them, or those in [only]). Returns how many
/// wires got a new route; a wire with no way round the parts keeps its old one.
int tidyWires(LabDoc doc, {Set<int>? only}) {
  const g = kTidyPitch;
  // the search area: the parts with room round them, kept on the board (a big,
  // mostly empty plate would only slow the search down)
  var area = Rect.zero;
  var first = true;
  for (final p in doc.parts) {
    if (p.structural) continue;
    area = first ? p.rect : area.expandToInclude(p.rect);
    first = false;
  }
  area = area.inflate(80).intersect(Rect.fromLTWH(0, 0, math.max(doc.totalW, 100.0), math.max(doc.plateH, 100.0)));
  if (area.width <= 0 || area.height <= 0) return 0;
  final ox = (area.left / g).floor() * g, oy = (area.top / g).floor() * g;
  final cols = ((area.right - ox) / g).ceil() + 1, rows = ((area.bottom - oy) / g).ceil() + 1;
  final n = cols * rows;

  // parts are no-go areas (DIN rails sit under the parts and wires may cross them)
  final blocked = Uint8List(n);
  for (final p in doc.parts) {
    if (p.structural) continue;
    final r = p.rect.inflate(1.5).translate(-ox, -oy);
    final c0 = math.max(0, (r.left / g).ceil()), c1 = math.min(cols - 1, (r.right / g).floor());
    final r0 = math.max(0, (r.top / g).ceil()), r1 = math.min(rows - 1, (r.bottom / g).floor());
    for (var y = r0; y <= r1; y++) {
      for (var x = c0; x <= c1; x++) {
        blocked[y * cols + x] = 1;
      }
    }
  }
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows;

  // the first cell clear of every part, leaving the terminal straight out of its own
  // part (and the blocks clipped on it); a neighbour in the way: try the other sides
  (int, int, List<(int, int)>)? exitCell(String key, Offset t, Offset dir) {
    final owner = doc.byId(key.substring(0, key.indexOf('.')));
    final own = <Rect>[
      for (final p in doc.parts)
        if (owner != null && (p == owner || p.attach == owner.id || owner.attach == p.id)) p.rect.inflate(1.5)
    ];
    bool mine(int x, int y) => own.any((r) => r.contains(Offset(x * g + ox, y * g + oy)));
    final d0 = _dirIndex(dir);
    (int, int, List<(int, int)>)? walk(int di, bool pushThrough) {
      final d = _dirs[di];
      var x = ((t.dx - ox) / g).round(), y = ((t.dy - oy) / g).round();
      final stub = <(int, int)>[];
      for (var k = 0; k < 80; k++) {
        if (!inside(x, y)) return null;
        stub.add((x, y));
        if (k >= 1 && blocked[y * cols + x] == 0) return (x, y, stub);
        if (k >= 1 && !pushThrough && !mine(x, y)) return null; // ran into another part
        x += d.dx.toInt();
        y += d.dy.toInt();
      }
      return null;
    }

    for (final di in [d0, 1, 3, (d0 + 2) % 4, 0, 2]) {
      final e = walk(di, false);
      if (e != null) return e;
    }
    // other parts overlap the terminal: leave by the shortest way through them
    (int, int, List<(int, int)>)? best;
    for (var di = 0; di < 4; di++) {
      final e = walk(di, true);
      if (e != null && (best == null || e.$3.length < best.$3.length)) best = e;
    }
    return best;
  }

  final order = [
    for (var i = 0; i < doc.wires.length; i++)
      if (only == null || only.contains(i)) i
  ];
  final ends = <int, (Offset, Offset)>{};
  for (final i in order) {
    final a = doc.termPos(doc.wires[i].a), b = doc.termPos(doc.wires[i].b);
    if (a != null && b != null) ends[i] = (a, b);
  }
  order.removeWhere((i) => !ends.containsKey(i));
  // each wire's way out of its two terminals
  final exits = <int, ((int, int, List<(int, int)>), (int, int, List<(int, int)>))>{};
  for (final i in order) {
    final wire = doc.wires[i];
    final (a, b) = ends[i]!;
    final ea = exitCell(wire.a, a, doc.termDir(wire.a)), eb = exitCell(wire.b, b, doc.termDir(wire.b));
    if (ea != null && eb != null) exits[i] = (ea, eb);
  }
  order.removeWhere((i) => !exits.containsKey(i));
  int heading(List<(int, int)> st) {
    final (x0, y0) = st[st.length - 2];
    final (x1, y1) = st.last;
    return _dirIndex(Offset((x1 - x0).toDouble(), (y1 - y0).toDouble()));
  }

  // lay the wires one after another in this order; the score is the total of the routes
  (Map<int, List<(int, int)>>, int) pass(List<int> seq) {
    final used = Uint8List(n); // bit 1 = a horizontal run here, bit 2 = a vertical one
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
      for (var k = 0; k + 1 < cells.length; k++) {
        final (x0, y0) = cells[k];
        final (x1, y1) = cells[k + 1];
        final bit = y0 == y1 ? 1 : 2;
        used[y0 * cols + x0] |= bit;
        used[y1 * cols + x1] |= bit;
      }
      out[i] = cells;
    }
    return (out, score);
  }

  double len(int k) {
    final d = ends[k]!.$1 - ends[k]!.$2;
    return d.dx.abs() + d.dy.abs();
  }

  // short wires first (they keep the direct runs) and long wires first (they keep
  // the trunks): whichever lays out shorter with fewer bends wins
  final shortFirst = [...order]..sort((i, j) => len(i).compareTo(len(j)));
  final longFirst = shortFirst.reversed.toList();
  final p1 = pass(shortFirst), p2 = pass(longFirst);
  final best = p1.$2 <= p2.$2 ? p1.$1 : p2.$1;
  for (final e in best.entries) {
    final (a, b) = ends[e.key]!;
    doc.wires[e.key].pts = _corners(e.value, a, b, g, Offset(ox, oy));
  }
  return best.length;
}

/// A* over (cell, heading): each step costs 1, a bend 8, running along a wire
/// already laid the same way 30 (so wires lie side by side), crossing one 2.
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
      // collapse repeated cells (heading changes recorded on the spot)
      final r = <(int, int)>[];
      for (final c in out.reversed) {
        if (r.isEmpty || r.last != c) r.add(c);
      }
      return (r, cost[st]);
    }
    if (++expanded > 600000) return null;
    final x = cell % cols, y = cell ~/ cols;
    for (var nd = 0; nd < 4; nd++) {
      if (nd == (d + 2) % 4) continue; // no U-turn on the spot
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

/// the corner points of a grid route, with the first and last legs moved onto
/// the terminals' own lines so the wire leaves and enters them dead straight
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
  if (pts.isEmpty) {
    // a straight run: a single mid point keeps it a straight line (no bends means a curve)
    return [Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2)];
  }
  bool firstVert(int k) => cells[k].$1 == cells[k + 1].$1;
  // the leg out of a: put it on a's line
  if (firstVert(0)) {
    pts[0] = Offset(a.dx, pts[0].dy);
  } else {
    pts[0] = Offset(pts[0].dx, a.dy);
  }
  // the leg into b
  final last = cells.length - 2;
  if (firstVert(last)) {
    pts[pts.length - 1] = Offset(b.dx, pts.last.dy);
  } else {
    pts[pts.length - 1] = Offset(pts.last.dx, b.dy);
  }
  return pts;
}

/// a small binary min-heap of (state, priority)
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
