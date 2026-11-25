// Panel Lab document: placed parts, DIN rails and hand-drawn wires (all in millimetres on the plate).
import 'dart:convert';
import 'dart:ui';

import '../sim/engine.dart';
import 'catalog.dart';

class Placed {
  String id;
  final String def;
  double x, y; // mm, top-left
  final Map<String, Object?> p;
  String? attach; // host part id (aux block / overload clipped on a contactor)
  Placed(this.id, this.def, this.x, this.y, {Map<String, Object?>? p, this.attach}) : p = {...?p};

  LabPartDef get d => kLabParts[def]!;
  bool get structural => kStructural.contains(def);

  Size get size {
    if (def == 'din_rail') return Size(len, 35);
    if (d.engine == 'motor' || d.engine == 'motor1') return const Size(MotorPlate.w, MotorPlate.h);
    return d.frame;
  }

  double get len => (p['len'] as num?)?.toDouble() ?? 300;
  Rect get rect => Rect.fromLTWH(x, y, size.width, size.height);

  Map<String, Offset> termsAbs() => {for (final e in d.termPos().entries) e.key: Offset(x + e.value.$1, y + e.value.$2)};

  Map<String, Object?> toJson() => {'id': id, 'def': def, 'x': x, 'y': y, 'p': p, if (attach != null) 'attach': attach};
  static Placed fromJson(Map<String, dynamic> j) =>
      Placed(j['id'] as String, j['def'] as String, (j['x'] as num).toDouble(), (j['y'] as num).toDouble(),
          p: (j['p'] as Map?)?.cast<String, Object?>(), attach: j['attach'] as String?);
}

class LabWire {
  final String a, b; // '<partId>.<engineTerm>'
  String color;
  LabWire(this.a, this.b, this.color);
  Map<String, Object?> toJson() => {'a': a, 'b': b, 'c': color};
  static LabWire fromJson(Map<String, dynamic> j) => LabWire(j['a'] as String, j['b'] as String, j['c'] as String);
}

class WireColor {
  final String key, nameAr;
  final Color color;
  final Color? stripe;
  const WireColor(this.key, this.nameAr, this.color, [this.stripe]);
}

const kWireColors = [
  WireColor('rd', 'أحمر (تحكم)', Color(0xFFE53935)),
  WireColor('br', 'بني L1', Color(0xFF8D5A3B)),
  WireColor('bk', 'أسود L2', Color(0xFF262A30)),
  WireColor('gy', 'رمادي L3', Color(0xFF8E959C)),
  WireColor('bu', 'أزرق N', Color(0xFF2F7FE0)),
  WireColor('ge', 'أخضر/أصفر PE', Color(0xFF2EAA4A), Color(0xFFF3D23B)),
  WireColor('db', 'أزرق غامق (تحكم مستمر)', Color(0xFF1F3A93)),
  WireColor('lb', 'أزرق فاتح', Color(0xFF6EC6FF)),
  WireColor('or', 'برتقالي', Color(0xFFFF8F1F)),
  WireColor('ye', 'أصفر', Color(0xFFF3D23B)),
  WireColor('gn', 'أخضر', Color(0xFF2EAA4A)),
  WireColor('vt', 'بنفسجي', Color(0xFF8E4FD8)),
  WireColor('pk', 'وردي', Color(0xFFF06EA9)),
  WireColor('wh', 'أبيض', Color(0xFFF2F4F6)),
];

WireColor wireColor(String k) => kWireColors.firstWhere((c) => c.key == k, orElse: () => kWireColors.first);

class LabDoc {
  final List<Placed> parts = [];
  final List<LabWire> wires = [];
  double plateW = 900, plateH = 700;
  /// work bench to the right of the plate for motors, machines and door devices (0 = none)
  double benchW = 0;
  /// mechanical interlocks (reversing / star-delta contactor pairs)
  final List<List<String>> mech = [];
  static const benchGap = 30.0;
  double get totalW => plateW + (benchW > 0 ? benchGap + benchW : 0);
  Rect get plateRect => Rect.fromLTWH(0, 0, plateW, plateH);
  Rect? get benchRect => benchW > 0 ? Rect.fromLTWH(plateW + benchGap, 0, benchW, plateH) : null;

  Placed? byId(String id) {
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  String nextId(String prefix) {
    var n = 1;
    final used = parts.map((p) => p.id).toSet();
    while (used.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  Offset? termPos(String key) {
    final i = key.indexOf('.');
    final p = byId(key.substring(0, i));
    if (p == null) return null;
    return p.termsAbs()[key.substring(i + 1)];
  }

  /// whether the terminal leaves upward (top half of its part)
  bool termUp(String key) => termDir(key).dy < 0;

  /// direction a wire leaves the terminal: up / down, or sideways for door-device lugs
  Offset termDir(String key) {
    final i = key.indexOf('.');
    final p = byId(key.substring(0, i));
    final t = termPos(key);
    if (p == null || t == null) return const Offset(0, -1);
    if (p.d.engine == 'motor' || p.d.engine == 'motor1') return const Offset(0, -1);
    if (p.d.machine != null) return const Offset(0, 1);
    if (p.d.side.isNotEmpty) return t.dx < p.x + p.size.width / 2 ? const Offset(-1, 0) : const Offset(1, 0);
    return t.dy < p.y + p.size.height / 2 ? const Offset(0, -1) : const Offset(0, 1);
  }

  void removePart(Placed p) {
    final ids = {p.id, for (final q in parts) if (q.attach == p.id) q.id};
    parts.removeWhere((q) => ids.contains(q.id));
    wires.removeWhere((w) => ids.contains(w.a.split('.').first) || ids.contains(w.b.split('.').first));
  }

  /// Equipotential numbering from the wiring alone (what the ferrules show).
  Map<String, int> netNumbers() {
    final parent = <String, String>{};
    String f(String a) {
      var r = parent[a] ?? a;
      if (r == a) {
        parent[a] = a;
        return a;
      }
      r = f(r);
      parent[a] = r;
      return r;
    }

    for (final w in wires) {
      final x = f(w.a), y = f(w.b);
      if (x != y) parent[x] = y;
    }
    final out = <String, int>{};
    final ids = <String, int>{};
    for (final w in wires) {
      for (final t in [w.a, w.b]) {
        out[t] = ids.putIfAbsent(f(t), () => ids.length + 1);
      }
    }
    return out;
  }

  /// Build a simulation lab from the drawing.
  Lab toLab() {
    final l = Lab();
    for (final p in parts) {
      if (p.structural || p.d.engine.isEmpty) continue;
      final params = <String, Object?>{...p.d.params, ...p.p};
      l.comps.add(Comp(p.id, p.d.engine, p: params, attach: p.attach));
    }
    for (final w in wires) {
      l.wires.add(Wire(w.a, w.b, col: w.color));
    }
    for (final m in mech) {
      if (l.byId(m[0]) != null && l.byId(m[1]) != null) l.mech.add(m);
    }
    l.solve();
    return l;
  }

  String toJsonString() => jsonEncode({
        'v': 1,
        'plate': [plateW, plateH],
        'bench': benchW,
        if (mech.isNotEmpty) 'mech': mech,
        'parts': [for (final p in parts) p.toJson()],
        'wires': [for (final w in wires) w.toJson()],
      });

  static LabDoc fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final d = LabDoc();
    final pl = j['plate'] as List?;
    if (pl != null) {
      d.plateW = (pl[0] as num).toDouble();
      d.plateH = (pl[1] as num).toDouble();
      d.benchW = (j['bench'] as num?)?.toDouble() ?? 0;
      for (final m in (j['mech'] as List? ?? const [])) {
        d.mech.add((m as List).cast<String>());
      }
    }
    for (final p in (j['parts'] as List)) {
      final q = Placed.fromJson(p as Map<String, dynamic>);
      if (kLabParts.containsKey(q.def)) d.parts.add(q);
    }
    for (final w in (j['wires'] as List)) {
      d.wires.add(LabWire.fromJson(w as Map<String, dynamic>));
    }
    return d;
  }

  LabDoc copy() => fromJsonString(toJsonString());
}
