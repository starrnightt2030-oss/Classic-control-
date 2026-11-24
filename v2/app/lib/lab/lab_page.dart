// «معمل اللوحة» — full-screen panel builder + live simulation.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_service.dart';
import '../sim/engine.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'catalog.dart';
import 'faults.dart';
import 'model.dart';
import 'paint.dart';
import 'templates.dart';

const _prefKey = 'lab_doc_v2';
const showUiBottom = 100.0;

class LabPage extends StatefulWidget {
  /// 0 normal · 1 start the DOL demo running · 2 open the library (CI screenshots)
  final int demo;
  const LabPage({super.key, this.demo = 0});
  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with SingleTickerProviderStateMixin {
  LabDoc doc = LabDoc();
  bool ready = false;
  final tc = TransformationController();
  final List<String> _undo = [], _redo = [];

  String? selPart;
  int? selWire;
  String? pending; // first terminal of a wire being drawn
  String color = 'auto';
  bool showUi = true;
  bool libOpen = false;
  String query = '';

  // drag state
  String? dragId;
  Offset? _downMm;
  Offset? _partStart;
  final Map<String, Offset> _childStart = {};
  bool _moved = false;
  int? _pointer;
  bool _blocked = false;

  // simulation
  Lab? sim;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0;
  final Map<int, String> _pressBy = {};

  // faults (free mode)
  FaultSession? fault;

  // multimeter
  bool meter = false;
  String? probeRed, probeBlack;

  Timer? _save;

  bool get running => sim != null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _save?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    await Sprites.load();
    final prefs = await SharedPreferences.getInstance();
    final s = widget.demo > 0 ? null : prefs.getString(_prefKey);
    LabDoc d;
    try {
      d = s == null ? dolTemplate() : LabDoc.fromJsonString(s);
    } catch (_) {
      d = dolTemplate();
    }
    setState(() {
      doc = d;
      ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fit();
      if (widget.demo == 1) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          _power();
          sim?.actuate('S1', 'press', true);
          Future<void>.delayed(const Duration(milliseconds: 400), () => sim?.actuate('S1', 'press', false));
        });
      }
      if (widget.demo == 2) setState(() => libOpen = true);
    });
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, doc.toJsonString());
    });
  }

  void _snapshot() {
    _undo.add(doc.toJsonString());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _changed() {
    _persist();
    setState(() {});
  }

  void _undoAct() {
    if (_undo.isEmpty || !_editable()) return;
    _redo.add(doc.toJsonString());
    doc = LabDoc.fromJsonString(_undo.removeLast());
    selPart = null;
    selWire = null;
    _changed();
  }

  void _redoAct() {
    if (_redo.isEmpty || !_editable()) return;
    _undo.add(doc.toJsonString());
    doc = LabDoc.fromJsonString(_redo.removeLast());
    _changed();
  }

  bool _editable({bool warn = true}) {
    if (!running) return true;
    if (warn) _toast('افصل التغذية أولًا. التعديل على لوحة عليها جهد ممنوع.');
    AudioService.instance.sfx('soft_fail');
    return false;
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  // --------------------------------------------------------------- view helpers
  double get _scale => tc.value.getMaxScaleOnAxis();

  void _fit() {
    final sz = context.size;
    if (sz == null) return;
    final w = doc.plateW * kPx, h = doc.plateH * kPx;
    const top = 70.0, bottom = showUiBottom;
    final s = math.min((sz.width - 40) / w, (sz.height - top - bottom) / h);
    final dx = (sz.width - w * s) / 2, dy = top + (sz.height - top - bottom - h * s) / 2;
    tc.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(s);
  }

  Offset _viewCenterMm() {
    final sz = context.size ?? const Size(800, 600);
    final p = tc.toScene(Offset(sz.width / 2, sz.height / 2));
    return p / kPx;
  }

  // --------------------------------------------------------------- hit tests
  Set<String> _hiddenTerms() {
    final h = <String>{};
    for (final p in doc.parts) {
      if (p.def == 'ol' && p.attach != null) {
        for (final t in ['2', '4', '6']) {
          h.add('${p.attach}.$t');
        }
      }
    }
    return h;
  }

  String? _termAt(Offset mm) {
    final r = math.max(3.8, 16 / (_scale * kPx));
    final hidden = _hiddenTerms();
    String? best;
    var bd = r;
    for (final p in doc.parts.reversed) {
      for (final e in p.termsAbs().entries) {
        final k = '${p.id}.${e.key}';
        if (hidden.contains(k)) continue;
        final d = (e.value - mm).distance;
        if (d < bd) {
          bd = d;
          best = k;
        }
      }
    }
    return best;
  }

  int? _wireAt(Offset mm) {
    final router = WireRouter(doc);
    final tol = math.max(2.4, 10 / (_scale * kPx));
    int? best;
    var bd = tol;
    for (var i = 0; i < doc.wires.length; i++) {
      final w = doc.wires[i];
      if (doc.termPos(w.a) == null || doc.termPos(w.b) == null) continue;
      final d = routeDistance(wirePath(router.route(w, i)), mm);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  List<Placed> _drawOrder() {
    int rank(Placed p) => p.structural ? 0 : (p.def == 'aux' ? 1 : (p.def == 'ol' ? 3 : 2));
    final l = [...doc.parts]..sort((a, b) => rank(a).compareTo(rank(b)));
    return l;
  }

  Placed? _partAt(Offset mm) {
    for (final p in _drawOrder().reversed) {
      if (p.rect.contains(mm)) return p;
    }
    return null;
  }

  // --------------------------------------------------------------- pointer handling
  void _down(PointerDownEvent e) {
    final mm = e.localPosition / kPx;
    if (running) {
      if (meter) {
        final t = _termAt(mm);
        if (t != null) {
          _probe(t);
          return;
        }
      }
      final p = _partAt(mm);
      if (p != null) _runPress(p, e.pointer, true);
      return;
    }
    if (_pointer != null) return; // second finger: let the viewer zoom
    _pointer = e.pointer;
    _downMm = mm;
    _moved = false;
    _blocked = false;
    if (_termAt(mm) != null) return; // terminals: handled on up (tap)
    final p = _partAt(mm);
    if (p != null && (p.id == selPart || !p.structural)) {
      final root = p.attach != null ? doc.byId(p.attach!) ?? p : p;
      setState(() => dragId = root.id);
      _partStart = Offset(root.x, root.y);
      _childStart
        ..clear()
        ..addEntries([for (final c in doc.parts) if (c.attach == root.id) MapEntry(c.id, Offset(c.x, c.y))]);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || dragId == null || _downMm == null) return;
    final mm = e.localPosition / kPx;
    final d = mm - _downMm!;
    if (!_moved && d.distance < 1.5) return;
    if (!_moved) {
      _snapshot();
      _moved = true;
    }
    final p = doc.byId(dragId!)!;
    p.x = _partStart!.dx + d.dx;
    p.y = _partStart!.dy + d.dy;
    for (final c in doc.parts) {
      final s = _childStart[c.id];
      if (s != null) {
        c.x = s.dx + d.dx;
        c.y = s.dy + d.dy;
      }
    }
    _blocked = _collides(p);
    setState(() {});
  }

  void _up(PointerUpEvent e) {
    final mm = e.localPosition / kPx;
    if (running) {
      _runPress(null, e.pointer, false);
      return;
    }
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (dragId != null && _moved) {
      final p = doc.byId(dragId!)!;
      _drop(p);
      setState(() => dragId = null);
      return;
    }
    setState(() => dragId = null);
    _tap(mm);
  }

  void _cancel(PointerCancelEvent e) {
    if (running) {
      _runPress(null, e.pointer, false);
      return;
    }
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (dragId != null && _moved) _drop(doc.byId(dragId!)!);
    setState(() => dragId = null);
  }

  void _tap(Offset mm) {
    final t = _termAt(mm);
    if (t != null && meter) {
      _probe(t);
      return;
    }
    if (t != null) {
      _terminalTap(t);
      return;
    }
    if (pending != null) {
      setState(() => pending = null);
      return;
    }
    final w = _wireAt(mm);
    if (w != null) {
      AudioService.instance.sfx('ui_tap');
      setState(() {
        selWire = w;
        selPart = null;
      });
      return;
    }
    final p = _partAt(mm);
    setState(() {
      selPart = p?.id;
      selWire = null;
    });
    if (p != null) AudioService.instance.sfx('part_select');
  }

  void _terminalTap(String t) {
    final count = doc.wires.where((w) => w.a == t || w.b == t).length;
    if (pending == null) {
      if (count >= 2) {
        _toast('الطرف عليه سلكان بالفعل. لا يُربط أكثر من سلكين تحت مسمار واحد.');
        AudioService.instance.sfx('soft_fail');
        return;
      }
      AudioService.instance.sfx('ui_tap');
      setState(() {
        pending = t;
        selPart = null;
        selWire = null;
      });
      return;
    }
    if (t == pending) {
      setState(() => pending = null);
      return;
    }
    if (count >= 2) {
      _toast('الطرف عليه سلكان بالفعل.');
      AudioService.instance.sfx('soft_fail');
      return;
    }
    if (doc.wires.any((w) => (w.a == t && w.b == pending) || (w.b == t && w.a == pending))) {
      setState(() => pending = null);
      return;
    }
    _snapshot();
    final c = color == 'auto' ? _autoColor(pending!, t) : color;
    doc.wires.add(LabWire(pending!, t, c));
    AudioService.instance.sfx('screw_tighten');
    pending = null;
    _changed();
  }

  void _probe(String t) {
    AudioService.instance.sfx('meter_beep');
    setState(() {
      if (probeRed == null || (probeRed != null && probeBlack != null)) {
        probeRed = t;
        probeBlack = null;
      } else {
        probeBlack = t;
      }
    });
  }

  /// what the multimeter shows between the two probes
  (String, String) _reading() {
    final a = probeRed, b = probeBlack;
    if (a == null || b == null) return ('- - -', 'ضع المجسّ الأحمر ثم الأسود على طرفين');
    if (running) {
      final n = sim!.nets!;
      final v = n.vAcross(a, b);
      final g = n.group(a) ?? n.group(b) ?? 'M';
      final dc = g.startsWith('D:');
      return ('${v.toStringAsFixed(v < 100 ? 1 : 0)} V ${dc ? 'DC' : 'AC'}', 'قياس الجهد: ${_pretty(a)} ↔ ${_pretty(b)}');
    }
    final l = doc.toLab();
    fault?.applyTo(l);
    final n = l.buildNets();
    if (n.same(a, b)) return ('0.0 Ω', 'توصيل: ${_pretty(a)} ↔ ${_pretty(b)}');
    final ia = a.indexOf('.'), ib = b.indexOf('.');
    final pa = a.substring(0, ia), ta = a.substring(ia + 1), tb = b.substring(ib + 1);
    if (pa == b.substring(0, ib)) {
      final c = l.byId(pa);
      final pair = {ta, tb};
      if (c != null && c.t.coil != null && pair.containsAll(c.t.coil!)) {
        if (c.s.fault == 'coil_open' || c.s.dead) return ('OL', 'الملف مقطوع: ${_pretty(a)} ↔ ${_pretty(b)}');
        final r = c.type == 'timer' || c.type == 'tsd' ? 'electronic' : (((c.p['coilV'] as num?) ?? 220) < 50 ? '68' : '580');
        return (r == 'electronic' ? '— —' : '$r Ω', r == 'electronic' ? 'مدخل إلكتروني: لا يُقاس بالأوم' : 'مقاومة الملف ${c.id}');
      }
      if (c != null && c.type == 'lamp' && pair.containsAll(const ['X1', 'X2'])) {
        return c.s.fault == 'lamp_dead' ? ('OL', 'اللمبة مفتوحة') : ('1.2 kΩ', 'مقاومة اللمبة ${c.id}');
      }
      if (c != null && c.type == 'motor') {
        const w = [{'U1', 'U2'}, {'V1', 'V2'}, {'W1', 'W2'}];
        if (w.any((x) => x.containsAll(pair))) return ('2.4 Ω', 'مقاومة ملف المحرك ${c.id}');
      }
    }
    return ('OL', 'لا يوجد توصيل (دائرة مفتوحة)');
  }

  String _pretty(String key) {
    final i = key.indexOf('.');
    final p = doc.byId(key.substring(0, i));
    return '${key.substring(0, i)}:${p?.d.printed(key.substring(i + 1)) ?? key.substring(i + 1)}';
  }

  String _autoColor(String a, String b) {
    String col(String key) {
      final i = key.indexOf('.');
      final p = doc.byId(key.substring(0, i));
      final t = key.substring(i + 1);
      if (p == null) return '';
      if (t == 'PE') return 'ge';
      if (t == 'N' || t == 'N2') return 'bu';
      if (p.def == 'psu' && (t == 'P' || t == 'P2' || t == 'M' || t == 'M2')) return 'db';
      const pole = {'1': 'br', '2': 'br', '3': 'bk', '4': 'bk', '5': 'gy', '6': 'gy', '7': 'bu', '8': 'bu'};
      if (const {'supply'}.contains(p.def)) return {'L1': 'br', 'L2': 'bk', 'L3': 'gy'}[t] ?? '';
      if (const {'mcb3', 'mcb4', 'mpcb', 'kc', 'ol'}.contains(p.def)) return pole[t] ?? '';
      if (p.def == 'motor') return {'U1': 'br', 'V1': 'bk', 'W1': 'gy', 'U2': 'br', 'V2': 'bk', 'W2': 'gy'}[t] ?? '';
      return '';
    }

    final ca = col(a), cb = col(b);
    if (ca == 'ge' || cb == 'ge') return 'ge';
    if (ca == 'bu' || cb == 'bu') return 'bu';
    if (ca == 'db' || cb == 'db') return 'db';
    if (ca.isNotEmpty && ca == cb) return ca;
    if (ca.isNotEmpty && cb.isNotEmpty) return ca;
    return 'rd';
  }

  // --------------------------------------------------------------- placing
  bool _collides(Placed p) {
    final family = {p.id, for (final c in doc.parts) if (c.attach == p.id) c.id};
    final mine = [for (final q in doc.parts) if (family.contains(q.id)) q.rect.deflate(0.8)];
    for (final q in doc.parts) {
      if (family.contains(q.id)) continue;
      if (q.def == 'din_rail' && !p.structural) continue;
      if (p.def == 'din_rail' && !q.structural) continue;
      if (p.structural && q.structural && (p.def == 'din_rail') != (q.def == 'din_rail')) {
        // a rail may cross a duct only at its ends — keep it simple: no overlap
      }
      for (final r in mine) {
        if (r.overlaps(q.rect.deflate(0.8))) return true;
      }
    }
    final plate = Rect.fromLTWH(0, 0, doc.plateW, doc.plateH);
    for (final r in mine) {
      if (!plate.contains(r.topLeft) || !plate.contains(r.bottomRight)) return true;
    }
    return false;
  }

  void _drop(Placed p) {
    // DIN mounting: snap the part's centre line onto the nearest rail
    if (p.d.mount == Mount.din && p.attach == null) {
      Placed? best;
      var bd = 40.0;
      for (final r in doc.parts.where((q) => q.def == 'din_rail')) {
        final cy = r.y + r.size.height / 2;
        final pc = p.y + p.size.height / 2;
        if (p.x + p.size.width < r.x || p.x > r.x + r.len) continue;
        if ((cy - pc).abs() < bd) {
          bd = (cy - pc).abs();
          best = r;
        }
      }
      if (best != null) {
        final dy = best.y + best.size.height / 2 - (p.y + p.size.height / 2);
        p.y += dy;
        for (final c in doc.parts.where((c) => c.attach == p.id)) {
          c.y += dy;
        }
      }
    }
    // clip-on parts: attach to the contactor under them
    if (p.d.attachTo != null) {
      Placed? host;
      for (final q in doc.parts) {
        if (q.d.engine == p.d.attachTo && q.rect.inflate(20).overlaps(p.rect) && !doc.parts.any((o) => o.attach == q.id && o.def == p.def && o.id != p.id)) {
          host = q;
          break;
        }
      }
      if (host != null) {
        p.attach = host.id;
        placeAttached(p, host);
      } else {
        p.attach = null;
      }
    }
    // snap to 1 mm
    final sx = p.x.roundToDouble() - p.x, sy = p.y.roundToDouble() - p.y;
    p.x += sx;
    p.y += sy;
    for (final c in doc.parts.where((c) => c.attach == p.id)) {
      c.x += sx;
      c.y += sy;
    }
    if (_collides(p)) {
      final dx = _partStart!.dx - p.x, dy = _partStart!.dy - p.y;
      p.x += dx;
      p.y += dy;
      for (final c in doc.parts.where((c) => c.attach == p.id)) {
        final s = _childStart[c.id];
        if (s != null) {
          c.x = s.dx;
          c.y = s.dy;
        }
      }
      if (_undo.isNotEmpty) _undo.removeLast();
      _toast('المكان مشغول. اترك مسافة بين المكونات وبعيدًا عن مجاري الأسلاك.');
      AudioService.instance.sfx('soft_fail');
    } else {
      AudioService.instance.sfx(p.d.mount == Mount.din ? 'din_rail_click' : 'assemble_snap');
    }
    _blocked = false;
    _changed();
  }

  void _addPart(String def) {
    if (!_editable()) return;
    final d = kLabParts[def]!;
    final c = _viewCenterMm();
    final id = doc.nextId(d.prefix);
    final p = Placed(id, def, 0, 0, p: {
      ...d.params,
      if (kStructural.contains(def)) 'len': def == 'duct_v' ? 300.0 : 400.0,
    });
    p.x = (c.dx - p.size.width / 2).clamp(0.0, doc.plateW - p.size.width).toDouble();
    p.y = (c.dy - p.size.height / 2).clamp(0.0, doc.plateH - p.size.height).toDouble();
    // find a free spot near the centre
    for (var i = 0; i < 120 && _collides(p); i++) {
      final a = i * 0.7, r = 6.0 + i * 3;
      p.x = (c.dx - p.size.width / 2 + math.cos(a) * r).clamp(0.0, doc.plateW - p.size.width).toDouble();
      p.y = (c.dy - p.size.height / 2 + math.sin(a) * r).clamp(0.0, doc.plateH - p.size.height).toDouble();
    }
    _snapshot();
    doc.parts.add(p);
    _partStart = Offset(p.x, p.y);
    _childStart.clear();
    _drop(p);
    if (doc.parts.contains(p)) selPart = p.id;
    selWire = null;
    _changed();
  }

  void _deleteSel() {
    if (!_editable()) return;
    _snapshot();
    if (selWire != null && selWire! < doc.wires.length) {
      doc.wires.removeAt(selWire!);
      selWire = null;
    } else if (selPart != null) {
      final p = doc.byId(selPart!);
      if (p != null) doc.removePart(p);
      selPart = null;
    }
    AudioService.instance.sfx('ui_whoosh');
    _changed();
  }

  // --------------------------------------------------------------- simulation
  void _power() {
    if (running) {
      AudioService.instance.sfx('mcb_trip');
      _ticker.stop();
      setState(() {
        sim = null;
        _pressBy.clear();
      });
      return;
    }
    final l = doc.toLab();
    fault?.applyTo(l);
    AudioService.instance.sfx('mcb_on');
    l.setPower(true);
    _last = Duration.zero;
    setState(() {
      sim = l;
      pending = null;
      selPart = null;
      selWire = null;
    });
    _handle(l.drain());
    _ticker.start();
  }

  void _tick(Duration now) {
    final l = sim;
    if (l == null) return;
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = now;
    l.step(dt);
    _phase = (_phase + dt * 0.8) % 1;
    _handle(l.drain());
    fault?.tick(dt);
    setState(() {});
  }

  void _handle(List<SimEvent> evs) {
    final a = AudioService.instance;
    for (final e in evs) {
      switch (e.t) {
        case 'kon':
          a.sfx(e.data['type'] == 'kc' ? 'contactor_pull_in' : 'relay_click');
        case 'koff':
          a.sfx(e.data['type'] == 'kc' ? 'contactor_drop_out' : 'relay_click');
        case 'tsw':
          a.sfx('timer_tick');
        case 'short':
          a.sfx('short_circuit_bang');
          _toast('قصر! فصل ${e.id ?? 'المصدر'}. راجع آخر سلك وصّلته.');
        case 'trip':
          if (e.data['why'] != 'short') a.sfx('mcb_trip');
        case 'mainTrip':
          _toast('قصر لم يفصله أي قاطع، فانقطعت التغذية الرئيسية.');
        case 'oltrip':
          a.sfx('overload_trip');
          _toast('فصل ${e.id} بسبب زيادة الحمل. ابحث عن السبب، ثم أعد الضبط.');
        case 'olhot':
          _toast('الأوفرلود ما زال ساخنًا. انتظر قليلًا.');
        case 'burn':
        case 'mburn':
        case 'pop':
          a.sfx('error_buzz');
          _toast('احترق ${e.id} بسبب جهد غير مناسب.');
        case 'motor':
          final m = e.data['mode'], p = e.data['prev'];
          if ((m == 'star' || m == 'delta') && p == 'off') a.sfx('motor_start');
          if (m == 'off' && (p == 'star' || p == 'delta')) a.sfx('motor_stop');
          if (m == 'single') {
            a.sfx('motor_strain');
            _toast('فقد فاز: المحرك ${e.id} يطنّ ولا يدور.');
          }
        case 'chatter':
          _toast('الدائرة غير مستقرة: كونتاكتور يفتح ويغلق باستمرار.');
      }
    }
  }

  void _runPress(Placed? p, int pointer, bool down) {
    final l = sim;
    if (l == null) return;
    if (down && p != null) {
      final c = l.byId(p.id);
      switch (p.d.engine) {
        case 'pb_no':
        case 'pb_nc':
        case 'ls':
          _pressBy[pointer] = p.id;
          AudioService.instance.sfx('pushbutton_click');
          l.actuate(p.id, p.d.engine == 'ls' ? 'ls' : 'press', true);
        case 'estop':
          AudioService.instance.sfx('estop_latch');
          l.actuate(p.id, 'estop');
        case 'sel':
          AudioService.instance.sfx('selector_detent');
          l.actuate(p.id, 'sel');
        case 'mcb1':
        case 'mcb2':
        case 'mcb3':
        case 'mcb4':
        case 'rccb':
        case 'fuse':
        case 'mpcb':
          AudioService.instance.sfx(c != null && c.s.on ? 'mcb_trip' : 'mcb_on');
          l.actuate(p.id, 'mcb');
        case 'ol':
          _olSheet(p.id);
        case 'motor':
          l.actuate(p.id, 'load');
          _toast(l[p.id].s.load ? 'تم تحميل المحرك بحمل زائد.' : 'رُفع الحمل الزائد عن المحرك.');
      }
    } else if (!down) {
      final id = _pressBy.remove(pointer);
      if (id != null) {
        final c = l.byId(id);
        l.actuate(id, c?.type == 'ls' ? 'ls' : 'press', false);
      }
    }
    _handle(l.drain());
    setState(() {});
  }

  // --------------------------------------------------------------- sheets
  void _olSheet(String id) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = sim?.byId(id);
        final p = doc.byId(id);
        if (p == null) return const SizedBox();
        final setA = (c?.num_('set') ?? (p.p['set'] as num?)?.toDouble() ?? 8.5);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.d.nameAr} $id', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(c == null ? 'التيار غير مقاس الآن' : 'تيار المحرك الآن: ${c.s.current.toStringAsFixed(1)} أمبير · الحرارة ${(c.s.heat / 1.5).round()}٪',
                style: const TextStyle(color: CC.muted)),
            const SizedBox(height: 14),
            Text('ضبط التيار: ${setA.toStringAsFixed(1)} أمبير', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              min: 4,
              max: 14,
              divisions: 40,
              value: setA.clamp(4.0, 14.0).toDouble(),
              onChanged: (v) {
                p.p['set'] = v;
                c?.p['set'] = v;
                set(() {});
                setState(() {});
                _persist();
              },
            ),
            const Text('اضبطه على تيار لوحة المحرك (8.5 أمبير). الأقل يفصل بلا سبب، والأعلى يلغي الحماية.',
                style: TextStyle(fontSize: 12.5, color: CC.muted, height: 1.6)),
            const SizedBox(height: 14),
            if (p.def == 'ol')
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: c == null
                            ? null
                            : () {
                                sim!.actuate(id, 'oltest');
                                _handle(sim!.drain());
                                set(() {});
                              },
                        child: const Text('TEST اختبار'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton(
                        onPressed: c == null
                            ? null
                            : () {
                                sim!.actuate(id, 'olreset');
                                _handle(sim!.drain());
                                set(() {});
                              },
                        child: const Text('RESET إعادة ضبط'))),
              ]),
          ]),
        );
      }),
    );
  }

  void _propsSheet(Placed p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(String k, Object v) {
          _snapshot();
          p.p[k] = v;
          set(() {});
          _changed();
        }

        Widget chips(String k, List<(Object, String)> opts) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, t) in opts)
                ChoiceChip(label: Text(t), selected: (p.p[k] ?? p.d.params[k]) == v, onSelected: (_) => upd(k, v)),
            ]);
        final e = p.d.engine;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.d.nameAr} · ${p.id}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (e == 'kc' || e == 'relay') ...[
              const Text('جهد الملف', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              chips('coilV', [(24.0, '24 فولت'), (110.0, '110 فولت'), (220.0, '220 فولت'), (380.0, '380 فولت')]),
            ],
            if (e == 'lamp') ...[
              const Text('جهد اللمبة', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              chips('V', [(24.0, '24 فولت'), (220.0, '220 فولت')]),
            ],
            if (e == 'timer') ...[
              const Text('نوع التأخير', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              chips('mode', [('on', 'تأخير التوصيل ON-DELAY'), ('off', 'تأخير الفصل OFF-DELAY')]),
            ],
            if (e == 'timer' || e == 'tsd') ...[
              const SizedBox(height: 12),
              Text('الزمن: ${((p.p['T'] ?? p.d.params['T']) as num).toStringAsFixed(0)} ثانية', style: const TextStyle(color: CC.text2)),
              Slider(min: 1, max: 30, divisions: 29, value: ((p.p['T'] ?? p.d.params['T']) as num).toDouble(), onChanged: (v) => upd('T', v)),
            ],
            if (e == 'ol' || e == 'mpcb') ...[
              Text('ضبط التيار: ${((p.p['set'] ?? 8.5) as num).toStringAsFixed(1)} أمبير', style: const TextStyle(color: CC.text2)),
              Slider(min: 4, max: 14, divisions: 40, value: ((p.p['set'] ?? 8.5) as num).toDouble(), onChanged: (v) => upd('set', v)),
            ],
            if (e == 'motor') ...[
              const Text('توصيلة صندوق الأطراف', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              chips('links', [('delta', 'دلتا (قناطر رأسية)'), ('star', 'ستار (قنطرة أفقية)'), ('none', 'بدون قناطر (ستار دلتا)')]),
              const SizedBox(height: 12),
              Text('تيار اللوحة الاسمية: ${((p.p['In'] ?? 8.5) as num).toStringAsFixed(1)} أمبير', style: const TextStyle(color: CC.text2)),
              Slider(min: 2, max: 20, divisions: 36, value: ((p.p['In'] ?? 8.5) as num).toDouble(), onChanged: (v) => upd('In', v)),
            ],
            if (p.structural) ...[
              Text('الطول: ${p.len.round()} ملم', style: const TextStyle(color: CC.text2)),
              Slider(
                  min: 60,
                  max: p.def == 'duct_v' ? doc.plateH : doc.plateW,
                  value: p.len.clamp(60.0, p.def == 'duct_v' ? doc.plateH : doc.plateW).toDouble(),
                  onChanged: (v) {
                    p.p['len'] = v.roundToDouble();
                    set(() {});
                    _changed();
                  }),
            ],
            const SizedBox(height: 8),
            Text('الأطراف: ${p.d.termPos().keys.map(p.d.printed).join('  ·  ')}', style: const TextStyle(fontSize: 12.5, color: CC.muted)),
          ]),
        );
      }),
    );
  }

  void _colorSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(selWire != null ? 'لون السلك المختار' : 'لون الأسلاك الجديدة', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (selWire == null)
              _ColorDot(label: 'تلقائي حسب الطرف', color: null, selected: color == 'auto', onTap: () {
                setState(() => color = 'auto');
                Navigator.pop(ctx);
              }),
            for (final c in kWireColors)
              _ColorDot(
                  label: c.nameAr,
                  color: c,
                  selected: selWire != null ? doc.wires[selWire!].color == c.key : color == c.key,
                  onTap: () {
                    if (selWire != null) {
                      _snapshot();
                      doc.wires[selWire!].color = c.key;
                      _changed();
                    } else {
                      setState(() => color = c.key);
                    }
                    Navigator.pop(ctx);
                  }),
          ]),
        ]),
      ),
    );
  }

  void _moreSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const CcIcon(CcIcons.lab, color: CC.accentSoft),
              title: const Text('مثال جاهز: تشغيل مباشر DOL'),
              subtitle: const Text('لوحة كاملة موصّلة تشغّلها وتجرّب عليها', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                if (!_editable()) return;
                _snapshot();
                doc = dolTemplate();
                fault = null;
                _changed();
                _fit();
              }),
          ListTile(
              leading: const CcIcon(CcIcons.reset, color: CC.accentSoft),
              title: const Text('لوحة جديدة فارغة'),
              subtitle: const Text('قضبان أوميجا ومجاري أسلاك جاهزة', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                if (!_editable()) return;
                _snapshot();
                doc = emptyPanel();
                fault = null;
                _changed();
                _fit();
              }),
          ListTile(
              leading: const CcIcon(CcIcons.warning, color: CC.gold),
              title: const Text('مولّد الأعطال'),
              subtitle: const Text('عطل مخفي في لوحتك: ابحث عنه بالقياس وأصلحه', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                _startFault();
              }),
          ListTile(
              leading: const CcIcon(CcIcons.list, color: CC.accentSoft),
              title: const Text('سجل الأعطال'),
              onTap: () {
                Navigator.pop(ctx);
                showFaultHistory(context);
              }),
        ]),
      ),
    );
  }

  // --------------------------------------------------------------- faults
  void _startFault() {
    if (running) _power();
    final f = FaultSession.create(doc);
    if (f == null) {
      _toast('اللوحة صغيرة جدًا على مولّد الأعطال. ابدأ بالمثال الجاهز أو وصّل دائرة كاملة.');
      return;
    }
    setState(() => fault = f);
    AudioService.instance.sfx('warning_alert');
    _toast('تم إدخال عطل مخفي. شغّل اللوحة ولاحظ العَرَض، ثم حدّد مكان العطل.');
  }

  void _faultPanel() {
    final f = fault;
    if (f == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FaultSheet(
        session: f,
        doc: doc,
        onSolved: () {
          setState(() => fault = null);
          if (running) _power();
        },
      ),
    );
  }

  // --------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF070C1A)),
            child: CustomPaint(painter: _DotGrid(tc.value)),
          ),
        ),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: tc,
            constrained: false,
            minScale: 0.08,
            maxScale: 6,
            panEnabled: dragId == null,
            scaleEnabled: dragId == null,
            boundaryMargin: const EdgeInsets.all(2400),
            onInteractionUpdate: (_) => setState(() {}),
            child: SizedBox(
              width: doc.plateW * kPx,
              height: doc.plateH * kPx,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: PlatePainter(doc, selPart))),
                for (final p in _drawOrder())
                  if (!p.structural) _partWidget(p),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: WirePainter(doc: doc, selectedWire: selWire, nets: sim?.nets, phase: _phase, pending: pending),
                    ),
                  ),
                ),
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(
                            painter: TermPainter(doc, pending, !running && !meter, _hiddenTerms(), probeRed: probeRed, probeBlack: probeBlack)))),
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _cancel,
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (showUi) ..._overlays(context) else _restoreButton(),
      ]),
    );
  }

  Widget _partWidget(Placed p) {
    final sel = p.id == selPart || p.id == dragId;
    final sz = p.size;
    final c = sim?.byId(p.id);
    final children = <Widget>[];
    if (p.def == 'motor') {
      children
        ..add(Positioned.fill(child: CustomPaint(painter: MotorPlatePainter((p.p['links'] ?? 'delta') as String))))
        ..add(Positioned(
          left: 0,
          right: 0,
          top: (MotorPlate.plateY + MotorPlate.plateH + 6) * kPx,
          bottom: 0,
          child: Image.asset(p.d.info?.asset ?? 'assets/panel/motor.webp', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ));
    } else {
      children.add(Positioned.fill(child: Image.asset(p.d.info?.asset ?? '', fit: BoxFit.fill, filterQuality: FilterQuality.medium)));
    }
    if (c != null) children.addAll(_liveOverlay(p, c));
    // id label
    children.add(Positioned(
      left: 0,
      right: 0,
      bottom: -11 * kPx,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 2.2 * kPx, vertical: 0.2 * kPx),
          decoration: BoxDecoration(color: const Color(0xFFF5D547), borderRadius: BorderRadius.circular(1.5 * kPx), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2))]),
          child: Text('-${p.id}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 5.6 * kPx, fontWeight: FontWeight.w800, color: const Color(0xFF15181B), height: 1.2)),
        ),
      ),
    ));
    if (sel) {
      children.add(Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _blocked && p.id == dragId ? CC.red : CC.amber, width: 3),
              borderRadius: BorderRadius.circular(6),
              boxShadow: glow(_blocked && p.id == dragId ? CC.red : CC.amber, 0.9),
            ),
          ),
        ),
      ));
    }
    return Positioned(
      left: p.x * kPx,
      top: p.y * kPx,
      width: sz.width * kPx,
      height: sz.height * kPx,
      child: IgnorePointer(child: Stack(clipBehavior: Clip.none, children: children)),
    );
  }

  List<Widget> _liveOverlay(Placed p, Comp c) {
    final sz = p.size;
    Widget badge(String t, Color col) => Positioned(
          top: -11 * kPx,
          left: -20 * kPx,
          right: -20 * kPx,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 2.6 * kPx, vertical: 0.3 * kPx),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3 * kPx), boxShadow: glow(col, 0.8)),
              child: Text(t, style: TextStyle(fontSize: 5.4 * kPx, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
            ),
          ),
        );
    switch (p.d.engine) {
      case 'lamp':
        final lit = c.s.v > (c.num_('V') * 0.6) && !c.s.dead && c.s.fault != 'lamp_dead';
        if (!lit) return const [];
        final col = switch (p.p['col'] ?? p.d.params['col']) { 'r' => const Color(0xFFFF3B30), 'y' => const Color(0xFFFFC21A), _ => const Color(0xFF2FE07A) };
        // the lens is the coloured cap at the top of the side-view sprite
        return [
          Positioned(
            left: sz.width * kPx * 0.06,
            right: sz.width * kPx * 0.06,
            top: -sz.height * kPx * 0.01,
            height: sz.height * kPx * 0.07,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3 * kPx),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.95), col, col.withValues(alpha: 0.9)]),
                boxShadow: [BoxShadow(color: col.withValues(alpha: 0.85), blurRadius: 60, spreadRadius: 10), BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 16)],
              ),
            ),
          ),
        ];
      case 'kc':
      case 'relay':
        return [badge(c.s.on ? 'ON' : (c.s.hum ? 'HUM' : 'OFF'), c.s.on ? const Color(0xFF1FA463) : (c.s.hum ? CC.red : const Color(0xFF59657A)))];
      case 'timer':
      case 'tsd':
        final tm = c.num_('T');
        final txt = c.s.on ? '${math.min(c.s.el, tm).toStringAsFixed(1)} / ${tm.toStringAsFixed(0)} ث' : 'OFF';
        return [badge(txt, c.s.on ? CC.amber : const Color(0xFF59657A))];
      case 'phr':
        return [badge(c.s.on ? 'OK' : 'FAULT', c.s.on ? const Color(0xFF1FA463) : CC.red)];
      case 'mcb1':
      case 'mcb2':
      case 'mcb3':
      case 'mcb4':
      case 'rccb':
      case 'fuse':
      case 'mpcb':
        return [badge(c.s.trip ? 'TRIP' : (c.s.on ? 'I · ON' : 'O · OFF'), c.s.trip ? CC.red : (c.s.on ? const Color(0xFF1FA463) : const Color(0xFF59657A)))];
      case 'ol':
        return [badge(c.s.trip ? 'TRIP' : '${c.num_('set').toStringAsFixed(1)} A', c.s.trip ? CC.red : const Color(0xFF59657A))];
      case 'pb_no':
      case 'pb_nc':
      case 'estop':
        final down = c.type == 'estop' ? c.s.lat : c.s.pr;
        if (!down) return const [];
        return [
          Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: sz.height * kPx * 0.3,
              child: Transform.translate(
                offset: Offset(0, 1.5 * kPx),
                child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(4 * kPx))),
              )),
          badge(c.type == 'estop' ? 'مضغوط' : 'مضغوط', CC.amber),
        ];
      case 'motor':
        final run = c.s.mode == 'star' || c.s.mode == 'delta';
        final mode = {'off': 'STOPPED', 'star': 'RUN · STAR', 'delta': 'RUN · DELTA', 'single': 'PHASE LOSS', 'over': 'OVERVOLT', 'dead': 'BURNT'}[c.s.mode] ?? c.s.mode;
        final bad = c.s.mode == 'single' || c.s.mode == 'over' || c.s.mode == 'dead';
        return [
          Positioned(
            right: 4 * kPx,
            bottom: 6 * kPx,
            child: Container(
              padding: EdgeInsets.all(2.2 * kPx),
              decoration: BoxDecoration(color: const Color(0xE60A1228), borderRadius: BorderRadius.circular(3 * kPx), border: Border.all(color: bad ? CC.red : (run ? CC.green : CC.line2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(mode, style: TextStyle(fontSize: 7 * kPx, fontWeight: FontWeight.w800, color: bad ? CC.red : (run ? CC.green : CC.text2))),
                Text('${(c.s.spd * 1450).round()} rpm · ${c.s.current.toStringAsFixed(1)} A',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 5.4 * kPx, color: CC.text2, fontFamily: CC.mono)),
                if (c.s.load) Text('حمل زائد', style: TextStyle(fontSize: 5.4 * kPx, color: CC.gold, fontWeight: FontWeight.w700)),
                if (run) Text(c.s.dir == 1 ? '↻' : '↺', style: TextStyle(fontSize: 9 * kPx, color: CC.cyan, height: 1)),
              ]),
            ),
          ),
          Positioned(
            left: 2 * kPx,
            top: 58 * kPx,
            child: Transform.rotate(
              angle: c.s.ang * math.pi / 180,
              child: Icon(Icons.toys, size: 26 * kPx, color: run ? CC.cyan : CC.muted),
            ),
          ),
        ];
    }
    return const [];
  }

  // --------------------------------------------------------------- overlays
  Widget _restoreButton() => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 12,
        child: Glass(
          radius: 22,
          child: IconButton(
            tooltip: 'إظهار الأدوات',
            onPressed: () => setState(() => showUi = true),
            icon: const Icon(Icons.unfold_more_rounded, color: CC.text),
          ),
        ),
      );

  List<Widget> _overlays(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final selP = selPart == null ? null : doc.byId(selPart!);
    return [
      // top bar
      Positioned(
        top: top + 10,
        left: 12,
        right: 12,
        child: Row(children: [
          Glass(
            radius: 22,
            child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_forward_rounded, color: CC.text), tooltip: 'رجوع'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Glass(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: running ? CC.green : CC.muted, boxShadow: running ? glow(CC.green) : null),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending != null
                        ? 'اختر الطرف الثاني للسلك…'
                        : running
                            ? 'اللوحة تعمل · اضغط على الضواغط والقواطع للتشغيل'
                            : 'معمل اللوحة · المس طرفين لتوصيل سلك، واسحب المكوّن لتحريكه',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (fault != null)
                  TextButton.icon(
                    onPressed: _faultPanel,
                    icon: const CcIcon(CcIcons.warning, color: CC.gold, size: 18),
                    label: Text(fault!.clockText(), style: const TextStyle(color: CC.gold, fontFamily: CC.mono)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Glass(
            radius: 22,
            child: IconButton(
                onPressed: () => setState(() {
                      showUi = false;
                      libOpen = false;
                    }),
                icon: const Icon(Icons.fullscreen_rounded, color: CC.text),
                tooltip: 'إخفاء الأدوات'),
          ),
        ]),
      ),
      // library drawer
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        top: top + 70,
        bottom: bottom + 96,
        right: libOpen ? 12 : -340,
        width: 320,
        child: _library(),
      ),
      if (meter) _meterPanel(bottom),
      // bottom toolbar
      Positioned(
        left: 12,
        right: 12,
        bottom: bottom + 12,
        child: Center(
          child: Glass(
            radius: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _tool(Icons.add_rounded, 'المكونات', () => setState(() => libOpen = !libOpen), active: libOpen),
                _colorTool(),
                _PowerButton(on: running, onTap: _power),
                _tool(Icons.speed_rounded, 'جهاز القياس', () => setState(() {
                      meter = !meter;
                      pending = null;
                      if (!meter) {
                        probeRed = null;
                        probeBlack = null;
                      }
                    }), active: meter),
                _tool(Icons.center_focus_strong_rounded, 'ملء الشاشة', _fit),
                _tool(Icons.undo_rounded, 'تراجع', _undo.isEmpty ? null : _undoAct),
                _tool(Icons.redo_rounded, 'إعادة', _redo.isEmpty ? null : _redoAct),
                if (selP != null) _tool(Icons.tune_rounded, 'الخصائص', () => _propsSheet(selP)),
                if (selP != null || selWire != null) _tool(Icons.delete_outline_rounded, 'حذف', _deleteSel, danger: true),
                _tool(Icons.more_horiz_rounded, 'المزيد', _moreSheet),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _meterPanel(double bottom) {
    final (value, note) = _reading();
    return Positioned(
      left: 12,
      bottom: bottom + 92,
      child: Glass(
        radius: 22,
        tint: const Color(0xF0141A22),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SizedBox(
          width: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.speed_rounded, color: Color(0xFFF5C518), size: 20),
              const SizedBox(width: 6),
              Text(running ? 'جهد V~' : 'توصيل Ω', style: const TextStyle(color: Color(0xFFF5C518), fontWeight: FontWeight.w700)),
              const Spacer(),
              InkWell(
                  onTap: () => setState(() {
                        probeRed = null;
                        probeBlack = null;
                      }),
                  child: const Icon(Icons.restart_alt_rounded, color: CC.muted, size: 20)),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF9FB59A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF2A2F35), width: 3)),
              child: Text(value,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: CC.mono, fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF1C2420))),
            ),
            const SizedBox(height: 6),
            Text(note, style: const TextStyle(fontSize: 12.5, color: CC.text2, height: 1.5)),
            if (!running)
              const Text('اللوحة مفصولة: القياس بالأوم آمن. شغّل التغذية لقياس الجهد.', style: TextStyle(fontSize: 11.5, color: CC.muted, height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _tool(IconData i, String tip, VoidCallback? onTap, {bool active = false, bool danger = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          tooltip: tip,
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: active ? const Color(0x333D8BFF) : null),
          icon: Icon(i, color: onTap == null ? CC.line2 : (danger ? CC.red : (active ? CC.amber : CC.text)), size: 26),
        ),
      );

  Widget _colorTool() {
    final w = selWire != null && selWire! < doc.wires.length ? wireColor(doc.wires[selWire!].color) : (color == 'auto' ? null : wireColor(color));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkResponse(
        onTap: _colorSheet,
        radius: 26,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: w?.color,
            gradient: w == null ? const SweepGradient(colors: [Color(0xFF8D5A3B), Color(0xFF262A30), Color(0xFF8E959C), Color(0xFF2F7FE0), Color(0xFFE53935), Color(0xFF8D5A3B)]) : null,
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
          ),
          child: w == null ? const Center(child: Text('A', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))) : null,
        ),
      ),
    );
  }

  Widget _library() {
    final q = query.trim();
    return Glass(
      radius: 24,
      tint: const Color(0xE60A1228),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: 'ابحث في المكونات',
              prefixIcon: Icon(Icons.search_rounded, color: CC.muted),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [
            for (final cat in kLabCategories)
              if (q.isEmpty || cat.parts.any((k) => kLabParts[k]!.nameAr.contains(q)))
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: q.isNotEmpty || cat == kLabCategories.first,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(cat.color))),
                    title: Text(cat.nameAr, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Text('${cat.parts.length}', style: const TextStyle(color: CC.muted)),
                    children: [
                      for (final k in cat.parts)
                        if (q.isEmpty || kLabParts[k]!.nameAr.contains(q)) _libItem(kLabParts[k]!),
                    ],
                  ),
                ),
          ]),
        ),
      ]),
    );
  }

  Widget _libItem(LabPartDef d) {
    Widget thumb;
    if (kStructural.contains(d.key)) {
      thumb = Icon(d.key == 'din_rail' ? Icons.horizontal_rule_rounded : (d.key == 'duct_v' ? Icons.view_week_rounded : Icons.view_stream_rounded), color: CC.text2);
    } else {
      thumb = Image.asset(d.info?.asset ?? '', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.memory_rounded, color: CC.muted));
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        _addPart(d.key);
        AudioService.instance.sfx('ui_tap');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          SizedBox(width: 54, height: 54, child: thumb),
          const SizedBox(width: 10),
          Expanded(child: Text(d.nameAr, style: const TextStyle(fontSize: 14))),
          const Icon(Icons.add_circle_outline_rounded, color: CC.accentSoft, size: 20),
        ]),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _PowerButton({required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on ? const [Color(0xFFFF7A7A), Color(0xFFD7263D)] : const [Color(0xFF4BE39A), Color(0xFF16A35B)]),
            boxShadow: glow(on ? CC.red : CC.green, 1.1),
          ),
          child: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String label;
  final WireColor? color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({required this.label, required this.color, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: panelBox(color: selected ? CC.amberBg : CC.surface, border: selected ? CC.amber : CC.line, radius: 14),
        child: Column(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color?.color,
              gradient: color == null
                  ? const SweepGradient(colors: [Color(0xFF8D5A3B), Color(0xFF262A30), Color(0xFF8E959C), Color(0xFF2F7FE0), Color(0xFFE53935), Color(0xFF8D5A3B)])
                  : (color!.stripe != null ? LinearGradient(colors: [color!.color, color!.stripe!, color!.color, color!.stripe!]) : null),
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, height: 1.3)),
        ]),
      ),
    );
  }
}

class _DotGrid extends CustomPainter {
  final Matrix4 m;
  _DotGrid(this.m);
  @override
  void paint(Canvas c, Size size) {
    final s = m.getMaxScaleOnAxis();
    final step = math.max(18.0, 40 * s * kPx / 4);
    final tx = m.getTranslation().x % step, ty = m.getTranslation().y % step;
    final p = Paint()..color = const Color(0x22A9C8FF);
    for (var x = tx; x < size.width; x += step) {
      for (var y = ty; y < size.height; y += step) {
        c.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGrid old) => true;
}
