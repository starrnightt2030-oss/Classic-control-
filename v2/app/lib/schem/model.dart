// Schematic document: placed symbols + pin-to-pin wires on a grid, and its
// translation into the simulation engine (the same engine as the panel lab).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import '../sim/engine.dart';
import 'symbols.dart';

class SPlaced {
  final String id; // unique on the sheet ('_7')
  final String sym;
  double x, y; // grid units, top-left
  String tag; // device tag (K1, S1…); contacts carry their host's tag
  final Map<String, Object?> p;
  SPlaced(this.id, this.sym, this.x, this.y, this.tag, {Map<String, Object?>? p}) : p = {...?p};

  SymDef get d => kSyms[sym]!;
  Rect get rect => Rect.fromLTWH(x, y, d.w, d.h);
  Offset pinPos(SymPin pn) => Offset(x + pn.x, y + pn.y);
  SymPin? pin(String id) {
    for (final p in d.pins) {
      if (p.id == id) return p;
    }
    return null;
  }

  Map<String, Object?> toJson() => {'id': id, 's': sym, 'x': x, 'y': y, 't': tag, 'p': p};
  static SPlaced fromJson(Map<String, dynamic> j) =>
      SPlaced(j['id'] as String, j['s'] as String, (j['x'] as num).toDouble(), (j['y'] as num).toDouble(), j['t'] as String? ?? '', p: (j['p'] as Map?)?.cast<String, Object?>());
}

class SWire {
  final String a, b; // '<symId>.<pin>'
  final double? y; // height of the horizontal run (grid), when the drawing fixes it
  SWire(this.a, this.b, {this.y});
  Map<String, Object?> toJson() => {'a': a, 'b': b, if (y != null) 'y': y};
  static SWire fromJson(Map<String, dynamic> j) => SWire(j['a'] as String, j['b'] as String, y: (j['y'] as num?)?.toDouble());
}

/// What the student built, translated for the engine.
class SchemSim {
  final Lab lab;
  final Map<String, String> pinToTerm; // '<symId>.<pin>' → engine terminal
  final Map<int, int> wireIndex; // engine wire index → document wire index
  final Map<String, String> compOf; // symbol id → engine component id
  final List<String> warnings;
  SchemSim(this.lab, this.pinToTerm, this.wireIndex, this.compOf, this.warnings);
}

class SchemDoc {
  final List<SPlaced> syms = [];
  final List<SWire> wires = [];
  /// mechanical interlocks between two device tags (reversing / star-delta contactors)
  final List<List<String>> mech = [];
  String title = 'دائرة جديدة';
  double sheetW = 64, sheetH = 42; // grid units

  SPlaced? byId(String id) {
    for (final s in syms) {
      if (s.id == id) return s;
    }
    return null;
  }

  String newId() {
    var n = syms.length + 1;
    final used = syms.map((s) => s.id).toSet();
    while (used.contains('_$n')) {
      n++;
    }
    return '_$n';
  }

  /// next free tag with the symbol's prefix (K1, K2…)
  String nextTag(String prefix) {
    var n = 1;
    final used = syms.map((s) => s.tag).toSet();
    while (used.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  /// tags of devices a contact can follow: contactors, relays, timers, overloads
  List<String> hostTags({String? kind}) {
    final out = <String>[];
    for (final s in syms) {
      final r = s.d.role;
      if (r != SymRole.host && r != SymRole.hostPart) continue;
      final e = s.d.engine;
      if (kind != null) {
        if (kind.startsWith('OL') && e != 'ol') continue;
        if (kind.startsWith('T') && e != 'timer') continue;
        if ((kind == 'NO' || kind == 'NC') && e == 'ol') continue;
      }
      if (!out.contains(s.tag)) out.add(s.tag);
    }
    return out;
  }

  Offset? pinPos(String key) {
    final i = key.indexOf('.');
    final s = byId(key.substring(0, i));
    final pn = s?.pin(key.substring(i + 1));
    if (s == null || pn == null) return null;
    return s.pinPos(pn);
  }

  bool pinUp(String key) {
    final i = key.indexOf('.');
    final s = byId(key.substring(0, i));
    return s?.pin(key.substring(i + 1))?.up ?? true;
  }

  void removeSym(SPlaced s) {
    syms.remove(s);
    wires.removeWhere((w) => w.a.startsWith('${s.id}.') || w.b.startsWith('${s.id}.'));
  }

  /// printed contact numbers: 13-14, 23-24… for NO, 21-22, 31-32… for NC (per tag)
  Map<String, String> contactNumbers() {
    final out = <String, String>{};
    final no = <String, int>{}, nc = <String, int>{};
    for (final s in syms) {
      final k = s.d.kind;
      if (s.d.role != SymRole.contact) continue;
      final fixed = s.p['no'];
      if (fixed is String) {
        out[s.id] = fixed;
        continue;
      }
      switch (k) {
        case 'OLNC':
          out[s.id] = '95-96';
        case 'OLNO':
          out[s.id] = '97-98';
        case 'TNO':
          out[s.id] = '67-68';
        case 'TNC':
          out[s.id] = '55-56';
        case 'NO':
          final n = (no[s.tag] = (no[s.tag] ?? 0) + 1);
          out[s.id] = '${n}3-${n}4';
        case 'NC':
          final n = (nc[s.tag] = (nc[s.tag] ?? 0) + 1) + 1;
          out[s.id] = '${n}1-${n}2';
      }
    }
    return out;
  }

  /// equipotential numbers for the wires (by connectivity of pins)
  Map<int, int> wireNumbers() {
    final parent = <String, String>{};
    String f(String a) {
      final r = parent[a] ?? a;
      if (r == a) return parent[a] = a;
      return parent[a] = f(r);
    }

    for (final w in wires) {
      final x = f(w.a), y = f(w.b);
      if (x != y) parent[x] = y;
    }
    final ids = <String, int>{};
    return {for (var i = 0; i < wires.length; i++) i: ids.putIfAbsent(f(wires[i].a), () => ids.length + 1)};
  }

  /// Translate to the engine. Hosts (coils / overload heaters) become one engine
  /// device per tag; every auxiliary contact becomes a contact that follows it.
  SchemSim toSim() {
    final l = Lab();
    final pin = <String, String>{};
    final compOf = <String, String>{};
    final warn = <String>[];
    // hosts first
    final hosts = <String, Comp>{};
    for (final s in syms) {
      if (s.d.role != SymRole.host) continue;
      if (hosts.containsKey(s.tag)) {
        warn.add('الرمز ${s.tag} مكرر: لكل جهاز ملف واحد فقط.');
        continue;
      }
      final c = Comp(s.tag, s.d.engine, p: {...s.d.params, ...s.p});
      hosts[s.tag] = c;
      l.comps.add(c);
    }
    for (final s in syms) {
      if (s.d.role == SymRole.hostPart && !hosts.containsKey(s.tag)) {
        final c = Comp(s.tag, s.d.engine);
        hosts[s.tag] = c;
        l.comps.add(c);
        warn.add('تلامسات ${s.tag} بلا ملف: لن تُغلق أبدًا.');
      }
    }
    var hasSup = false;
    for (final s in syms) {
      switch (s.d.role) {
        case SymRole.source:
          hasSup = true;
          pin['${s.id}.o'] = 'X0.${s.sym}';
        case SymRole.host:
        case SymRole.hostPart:
          compOf[s.id] = s.tag;
          for (final pn in s.d.pins) {
            pin['${s.id}.${pn.id}'] = '${s.tag}.${pn.id}';
          }
        case SymRole.contact:
          final host = hosts[s.tag];
          if (host == null) warn.add('التلامس ${s.tag} لا يتبع أي ملف أو أوفرلود باسم ${s.tag}.');
          l.comps.add(Comp(s.id, 'contact', p: {'kind': s.d.kind}, attach: host?.id));
          compOf[s.id] = s.id;
          pin['${s.id}.1'] = '${s.id}.1';
          pin['${s.id}.2'] = '${s.id}.2';
        case SymRole.device:
          // shared devices (a limit switch drawn as its NO and its NC contact) are one engine device per tag
          final id = s.d.shared ? s.tag : s.id;
          if (!s.d.shared || l.byId(id) == null) l.comps.add(Comp(id, s.d.engine, p: {...s.d.params, ...s.p}));
          compOf[s.id] = id;
          for (final pn in s.d.pins) {
            pin['${s.id}.${pn.id}'] = '$id.${pn.id}';
          }
      }
    }
    if (hasSup) l.comps.insert(0, Comp('X0', 'sup'));
    final wi = <int, int>{};
    for (var i = 0; i < wires.length; i++) {
      final a = pin[wires[i].a], b = pin[wires[i].b];
      if (a == null || b == null) continue;
      wi[l.wires.length] = i;
      l.wires.add(Wire(a, b));
    }
    for (final c in l.comps) {
      if (c.p['burnt'] == true) c.s.dead = true;
    }
    for (final m in mech) {
      if (l.byId(m[0]) != null && l.byId(m[1]) != null) l.mech.add(m);
    }
    return SchemSim(l, pin, wi, compOf, warn);
  }

  /// bill of materials: one line per physical device
  List<(String, String, String)> bom() {
    final seen = <String>{};
    final out = <(String, String, String)>[];
    String spec(SPlaced s) {
      final p = {...s.d.params, ...s.p};
      switch (s.d.engine) {
        case 'kc':
        case 'relay':
          return 'ملف ${(p['coilV'] as num?)?.round() ?? 220} فولت';
        case 'timer':
          return '${p['mode'] == 'off' ? 'تأخير فصل' : 'تأخير توصيل'} · ${(p['T'] as num?)?.round() ?? 5} ث';
        case 'ol':
          return 'ضبط ${(p['set'] as num?)?.toStringAsFixed(1) ?? '8.5'} أمبير';
        case 'lamp':
          return '${(p['V'] as num?)?.round() ?? 220} فولت · ${{'r': 'أحمر', 'y': 'أصفر', 'b': 'أزرق', 'w': 'أبيض'}[p['col']] ?? 'أخضر'}';
        case 'motor':
          return '400 فولت · ${(p['In'] as num?)?.toStringAsFixed(1) ?? '8.5'} أمبير';
      }
      return '';
    }

    for (final s in syms) {
      if (s.d.role == SymRole.source || s.d.role == SymRole.contact) continue;
      if (!seen.add(s.tag)) continue;
      final kc = syms.any((o) => o.tag == s.tag && o.sym == 'coil_kc') || s.sym == 'kc3';
      var name = s.d.nameAr;
      if (s.sym == 'coil_kc' || s.sym == 'kc3') name = 'كونتاكتور';
      if (s.sym == 'coil_ka') name = 'مرحّل مساعد';
      if (s.sym == 'coil_kt') name = 'مؤقت زمني';
      if (s.sym == 'ol3') name = 'أوفرلود حراري';
      final aux = syms.where((o) => o.tag == s.tag && o.d.role == SymRole.contact).length;
      var sp = spec(kc ? syms.firstWhere((o) => o.tag == s.tag && o.sym == 'coil_kc', orElse: () => s) : s);
      if (aux > 0) sp = '$sp${sp.isEmpty ? '' : ' · '}$aux تلامس مساعد';
      out.add((s.tag, name, sp));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  String toJsonString() => jsonEncode({
        'v': 1,
        'title': title,
        'sheet': [sheetW, sheetH],
        'syms': [for (final s in syms) s.toJson()],
        'wires': [for (final w in wires) w.toJson()],
        if (mech.isNotEmpty) 'mech': mech,
      });

  static SchemDoc fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final d = SchemDoc()..title = j['title'] as String? ?? 'دائرة';
    final sh = j['sheet'] as List?;
    if (sh != null) {
      d.sheetW = (sh[0] as num).toDouble();
      d.sheetH = (sh[1] as num).toDouble();
    }
    for (final x in (j['syms'] as List)) {
      final p = SPlaced.fromJson(x as Map<String, dynamic>);
      if (kSyms.containsKey(p.sym)) d.syms.add(p);
    }
    for (final x in (j['wires'] as List)) {
      d.wires.add(SWire.fromJson(x as Map<String, dynamic>));
    }
    for (final m in (j['mech'] as List? ?? const [])) {
      d.mech.add((m as List).cast<String>());
    }
    return d;
  }
}

/// Orthogonal route between two pins (grid units): leave each pin straight out,
/// then one horizontal run.
List<Offset> schemRoute(Offset a, bool upA, Offset b, bool upB, [double? via]) {
  const out = 0.8;
  if (via != null) {
    final pts = [a, Offset(a.dx, via), Offset(b.dx, via), b];
    final clean = <Offset>[pts.first];
    for (final p in pts.skip(1)) {
      if ((p - clean.last).distance > 0.01) clean.add(p);
    }
    return clean;
  }
  final a1 = Offset(a.dx, a.dy + (upA ? -out : out));
  final b1 = Offset(b.dx, b.dy + (upB ? -out : out));
  if ((a.dx - b.dx).abs() < 0.01) {
    // same column: straight when facing each other
    if ((!upA && upB && a.dy < b.dy) || (upA && !upB && a.dy > b.dy)) return [a, b];
  }
  double y;
  if (!upA && upB) {
    y = a1.dy <= b1.dy ? (a.dy + b.dy) / 2 : math.max(a1.dy, b1.dy);
  } else if (upA && !upB) {
    y = a1.dy >= b1.dy ? (a.dy + b.dy) / 2 : math.min(a1.dy, b1.dy);
  } else if (upA && upB) {
    y = math.min(a1.dy, b1.dy);
  } else {
    y = math.max(a1.dy, b1.dy);
  }
  y = (y * 2).roundToDouble() / 2; // half-grid
  final pts = <Offset>[a, Offset(a.dx, y), Offset(b.dx, y), b];
  // drop zero-length segments
  final clean = <Offset>[pts.first];
  for (final p in pts.skip(1)) {
    if ((p - clean.last).distance > 0.01) clean.add(p);
  }
  return clean;
}

/// The worked example: DOL starter, power and control circuit on one sheet.
SchemDoc dolSchematic() {
  final d = SchemDoc()..title = 'تشغيل مباشر DOL';
  SPlaced add(String sym, double x, double y, String tag, [Map<String, Object?>? p]) {
    final s = SPlaced(d.newId(), sym, x, y, tag, p: p);
    d.syms.add(s);
    return s;
  }

  void w(SPlaced a, String pa, SPlaced b, String pb) => d.wires.add(SWire('${a.id}.$pa', '${b.id}.$pb'));
  // power circuit
  final l1 = add('L1', 4, 2, 'L1'), l2 = add('L2', 6, 2, 'L2'), l3 = add('L3', 8, 2, 'L3');
  final q1 = add('mcb3', 4, 7, 'Q1');
  final k1m = add('kc3', 4, 14, 'K1');
  final f2 = add('ol3', 4, 21, 'F2');
  final m1 = add('motor3', 4, 28, 'M1');
  w(l1, 'o', q1, '1');
  w(l2, 'o', q1, '3');
  w(l3, 'o', q1, '5');
  w(q1, '2', k1m, '1');
  w(q1, '4', k1m, '3');
  w(q1, '6', k1m, '5');
  w(k1m, '2', f2, '1');
  w(k1m, '4', f2, '3');
  w(k1m, '6', f2, '5');
  w(f2, '2', m1, 'U1');
  w(f2, '4', m1, 'V1');
  w(f2, '6', m1, 'W1');
  // control circuit
  final cl = add('L1', 20, 2, 'L1');
  final f1 = add('mcb1', 20, 5, 'F1');
  final f2c = add('olnc', 20, 11, 'F2');
  final s0 = add('pb_nc', 20, 17, 'S0');
  final s1 = add('pb_no', 20, 23, 'S1');
  final k1h = add('no', 25, 23, 'K1');
  final k1 = add('coil_kc', 19, 30, 'K1');
  final cn = add('N', 20, 37, 'N');
  w(cl, 'o', f1, '1');
  w(f1, '2', f2c, '1');
  w(f2c, '2', s0, '11');
  w(s0, '12', s1, '13');
  w(s0, '12', k1h, '1');
  w(s1, '14', k1, 'A1');
  w(k1h, '2', k1, 'A1');
  w(k1, 'A2', cn, 'o');
  // pilot lamps
  final k1a = add('no', 31, 17, 'K1');
  final k1b = add('nc', 36, 17, 'K1');
  final h1 = add('lamp', 31, 25, 'H1', {'col': 'g'});
  final h2 = add('lamp', 36, 25, 'H2', {'col': 'r'});
  final n2 = add('N', 31, 37, 'N'), n3 = add('N', 36, 37, 'N');
  w(f2c, '2', k1a, '1');
  w(k1a, '1', k1b, '1');
  w(k1a, '2', h1, 'X1');
  w(k1b, '2', h2, 'X1');
  w(h1, 'X2', n2, 'o');
  w(h2, 'X2', n3, 'o');
  return d;
}
