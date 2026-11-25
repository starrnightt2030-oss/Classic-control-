// «محاكي الدوائر الخطية» — draw an IEC schematic from the symbol library, wire it
// pin to pin, and simulate it with the same engine as the panel lab.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lab/projects.dart';
import '../services/audio_service.dart';
import '../sim/engine.dart';
import '../ui/theme.dart';
import 'export.dart';
import 'ladder.dart';
import 'model.dart';
import 'sheet_paint.dart';
import 'symbols.dart';

const _prefKey = 'schem_doc_v1';

typedef DeliverBytes = Future<String?> Function(Uint8List bytes, String fileName, String mime);

class SchemPage extends StatefulWidget {
  /// hands the PDF to the user (share sheet / save dialog); null in the web preview
  final DeliverBytes? deliver;

  /// previews: 0 normal · 1 DOL example running · 2 library open · 3 DOL example editing
  final int demo;

  /// open this drawing (a ready-made circuit) instead of the saved sheet; it is not autosaved
  final SchemDoc? initial;
  const SchemPage({super.key, this.deliver, this.demo = 0, this.initial});
  @override
  State<SchemPage> createState() => _SchemPageState();
}

class _SchemPageState extends State<SchemPage> with SingleTickerProviderStateMixin {
  SchemDoc doc = SchemDoc();
  bool ready = false;
  final tc = TransformationController();
  final List<String> _undo = [], _redo = [];

  String? sel;
  int? selWire;
  String? pending;
  bool showUi = true;
  bool libOpen = false;

  // pointer state
  int? _pointer;
  Offset? _downG;
  String? _dragId;
  Offset? _dragStart;
  bool _moved = false;
  String? _wireFrom;
  Offset? _wireTo;
  // dragging one leg of a wire sideways: wire index, leg, route when grabbed
  (int, int, List<Offset>)? _leg;

  /// colour new wires get (null: default black)
  String? pen;

  // simulation
  SchemSim? sim;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0, _clock = 0;
  Map<int, int> flows = {};
  Set<int> flash = {};
  double _flashUntil = 0;
  final Map<int, String> _pressBy = {};
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
    final prefs = await SharedPreferences.getInstance();
    final s = widget.demo > 0 || widget.initial != null ? null : prefs.getString(_prefKey);
    SchemDoc d;
    try {
      d = widget.initial ??
          switch (widget.demo) {
            1 || 3 => readyById('c_dol')!.build(),
            4 => readyById('c_sd')!.build(),
            5 => readyById('c_rev_auto')!.build(),
            _ => s == null ? SchemDoc() : SchemDoc.fromJsonString(s),
          };
    } catch (_) {
      d = SchemDoc();
    }
    setState(() {
      doc = d;
      ready = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fit();
      if (widget.demo == 2) setState(() => libOpen = true);
      if (widget.demo == 4) Future<void>.delayed(const Duration(milliseconds: 500), () {
        _simulate();
        final s1 = doc.syms.firstWhere((s) => s.tag == 'S1');
        sim?.lab.actuate(s1.id, 'press', true);
        Future<void>.delayed(const Duration(milliseconds: 400), () => sim?.lab.actuate(s1.id, 'press', false));
      });
      if (widget.demo == 1) {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          _simulate();
          final s1 = doc.syms.firstWhere((s) => s.tag == 'S1');
          sim?.lab.actuate(s1.id, 'press', true);
          Future<void>.delayed(const Duration(milliseconds: 400), () => sim?.lab.actuate(s1.id, 'press', false));
        });
      }
    });
  }

  void _persist() {
    if (widget.initial != null || widget.demo > 0) return;
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

  bool _editable() {
    if (!running) return true;
    _toast('أوقف المحاكاة أولًا لتعديل الرسم.');
    return false;
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  double get _scale => tc.value.getMaxScaleOnAxis();

  void _fit() {
    final sz = context.size;
    if (sz == null) return;
    final w = doc.sheetW * kG, h = doc.sheetH * kG;
    const top = 70.0, bottom = 100.0;
    final s = math.min((sz.width - 32) / w, (sz.height - top - bottom) / h);
    tc.value = Matrix4.identity()
      ..translate((sz.width - w * s) / 2, top + (sz.height - top - bottom - h * s) / 2)
      ..scale(s);
  }

  // ------------------------------------------------------------ hit tests (grid units)
  String? _pinAt(Offset g) {
    final r = math.max(0.45, 14 / (_scale * kG));
    String? best;
    var bd = r;
    for (final s in doc.syms) {
      for (final pn in s.d.pins) {
        final d = (s.pinPos(pn) - g).distance;
        if (d < bd) {
          bd = d;
          best = '${s.id}.${pn.id}';
        }
      }
    }
    return best;
  }

  SPlaced? _symAt(Offset g) {
    for (final s in doc.syms.reversed) {
      if (s.rect.inflate(0.3).contains(g)) return s;
    }
    return null;
  }

  int? _wireAt(Offset g) {
    final tol = math.max(0.3, 9 / (_scale * kG));
    int? best;
    var bd = tol;
    for (var i = 0; i < doc.wires.length; i++) {
      final d = wireDistance(doc, doc.wires[i], g);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  // ------------------------------------------------------------ pointer
  void _down(PointerDownEvent e) {
    final g = e.localPosition / kG;
    if (running) {
      final s = _symAt(g);
      if (s != null) _actuate(s, e.pointer, true);
      return;
    }
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downG = g;
    _moved = false;
    final pn = _pinAt(g);
    if (pn != null) {
      setState(() => _wireFrom = pn);
      return;
    }
    final s = _symAt(g);
    if (s != null) {
      setState(() => _dragId = s.id);
      _dragStart = Offset(s.x, s.y);
      return;
    }
    final wi = _wireAt(g);
    if (wi != null) {
      final r = doc.route(doc.wires[wi]);
      if (r != null && r.length >= 2) setState(() => _leg = (wi, nearestLeg(r, g).$1, r));
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _downG == null) return;
    final g = e.localPosition / kG;
    if (_wireFrom != null) {
      if (_wireTo != null || (g - _downG!).distance > 0.4) setState(() => _wireTo = g);
      return;
    }
    final lg = _leg;
    if (lg != null) {
      final d = g - _downG!;
      if (!_moved && d.distance < 0.3) return;
      if (!_moved) {
        _snapshot();
        _moved = true;
      }
      final (wi, k, r) = lg;
      final vertical = (r[k].dx - r[k + 1].dx).abs() < 0.01;
      final delta = ((vertical ? d.dx : d.dy) * 2).roundToDouble() / 2; // half-grid steps
      doc.wires[wi].pts = dragLeg(r, k, delta);
      setState(() {});
      return;
    }
    if (_dragId == null) return;
    final d = g - _downG!;
    if (!_moved && d.distance < 0.3) return;
    if (!_moved) {
      _snapshot();
      _moved = true;
    }
    final s = doc.byId(_dragId!)!;
    s.x = (_dragStart!.dx + d.dx).roundToDouble().clamp(0.0, doc.sheetW - s.size.width).toDouble();
    s.y = (_dragStart!.dy + d.dy).roundToDouble().clamp(0.0, doc.sheetH - s.size.height).toDouble();
    setState(() {});
  }

  void _up(PointerUpEvent e) {
    final g = e.localPosition / kG;
    if (running) {
      _release(e.pointer);
      return;
    }
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_wireFrom != null && _wireTo != null) {
      final from = _wireFrom!, to = _pinAt(g);
      setState(() {
        _wireFrom = null;
        _wireTo = null;
        pending = null;
      });
      if (to != null && to != from) _connect(from, to);
      return;
    }
    _wireFrom = null;
    if (_leg != null) {
      final moved = _moved, wi = _leg!.$1;
      setState(() => _leg = null);
      if (moved) {
        setState(() {
          selWire = wi;
          sel = null;
        });
        _changed();
        return;
      }
    }
    if (_dragId != null && _moved) {
      final s = doc.byId(_dragId!)!;
      if (_collides(s)) {
        s.x = _dragStart!.dx;
        s.y = _dragStart!.dy;
        if (_undo.isNotEmpty) _undo.removeLast();
        _toast('المكان مشغول برمز آخر.');
      } else {
        AudioService.instance.sfx('ui_tap');
      }
      setState(() => _dragId = null);
      _changed();
      return;
    }
    setState(() => _dragId = null);
    _tap(g);
  }

  void _cancel(PointerCancelEvent e) {
    if (running) {
      _release(e.pointer);
      return;
    }
    if (e.pointer != _pointer) return;
    _pointer = null;
    _wireFrom = null;
    _wireTo = null;
    if (_leg != null && _moved) _changed();
    _leg = null;
    if (_dragId != null && _moved) {
      final s = doc.byId(_dragId!)!;
      if (_collides(s)) {
        s.x = _dragStart!.dx;
        s.y = _dragStart!.dy;
      }
      _changed();
    }
    setState(() => _dragId = null);
  }

  void _tap(Offset g) {
    final pn = _pinAt(g);
    if (pn != null) {
      if (pending == null) {
        setState(() {
          pending = pn;
          sel = null;
          selWire = null;
        });
      } else if (pending == pn) {
        setState(() => pending = null);
      } else {
        final a = pending!;
        pending = null;
        _connect(a, pn);
      }
      return;
    }
    if (pending != null) {
      setState(() => pending = null);
      return;
    }
    final s = _symAt(g);
    if (s != null) {
      setState(() {
        sel = s.id;
        selWire = null;
      });
      return;
    }
    final w = _wireAt(g);
    setState(() {
      selWire = w;
      sel = null;
    });
  }

  void _connect(String a, String b) {
    if (doc.wires.any((w) => (w.a == a && w.b == b) || (w.a == b && w.b == a))) return;
    _snapshot();
    doc.wires.add(SWire(a, b, c: pen));
    AudioService.instance.sfx('screw_tighten');
    _changed();
  }

  bool _collides(SPlaced s) {
    final r = s.rect.deflate(0.05);
    for (final o in doc.syms) {
      if (o.id != s.id && o.rect.deflate(0.05).overlaps(r)) return true;
    }
    return false;
  }

  // ------------------------------------------------------------ editing
  void _add(String key) {
    if (!_editable()) return;
    final d = kSyms[key]!;
    String tag;
    switch (d.role) {
      case SymRole.source:
        tag = key;
      case SymRole.contact:
      case SymRole.hostPart:
        final hosts = doc.hostTags(kind: d.role == SymRole.hostPart ? 'NO' : d.kind);
        final selS = sel == null ? null : doc.byId(sel!);
        if (selS != null && hosts.contains(selS.tag)) {
          tag = selS.tag;
        } else if (hosts.isNotEmpty) {
          tag = hosts.last;
        } else {
          tag = d.kind.startsWith('OL') ? 'F1' : (d.kind.startsWith('T') ? 'KT1' : 'K1');
        }
      case SymRole.host:
        // a coil for main contacts already on the sheet takes their tag
        final orphan = doc.syms.where((o) => o.d.role == SymRole.hostPart && !doc.syms.any((h) => h.d.role == SymRole.host && h.tag == o.tag)).toList();
        tag = (key == 'coil_kc' && orphan.isNotEmpty) ? orphan.first.tag : doc.nextTag(d.prefix);
      case SymRole.device:
        tag = doc.nextTag(d.prefix);
    }
    // place near the middle of the view, on a free grid spot
    final sz = context.size ?? const Size(800, 600);
    final c = tc.toScene(Offset(sz.width / 2, sz.height / 2)) / kG;
    final s = SPlaced(doc.newId(), key, 0, 0, tag, p: {...d.params});
    for (var i = 0; i < 400; i++) {
      final a = i * 0.9, r = i * 0.35;
      s.x = (c.dx - d.w / 2 + math.cos(a) * r).roundToDouble().clamp(1.0, doc.sheetW - d.w - 1).toDouble();
      s.y = (c.dy - d.h / 2 + math.sin(a) * r).roundToDouble().clamp(1.0, doc.sheetH - d.h - 1).toDouble();
      if (!_collides(s)) break;
    }
    _snapshot();
    doc.syms.add(s);
    sel = s.id;
    selWire = null;
    AudioService.instance.sfx('assemble_snap');
    _changed();
  }

  /// turn the selected symbol a quarter turn clockwise (or mirror it) about its centre
  void _turn({bool mirror = false}) {
    if (!_editable() || sel == null) return;
    final s = doc.byId(sel!);
    if (s == null) return;
    _snapshot();
    final c0 = s.rect.center;
    final r0 = s.rot, f0 = s.flip, x0 = s.x, y0 = s.y;
    if (mirror) {
      s.flip = !s.flip;
    } else {
      s.rot = (s.rot + 1) % 4;
    }
    s.x = (c0.dx - s.size.width / 2).roundToDouble().clamp(0.0, doc.sheetW - s.size.width).toDouble();
    s.y = (c0.dy - s.size.height / 2).roundToDouble().clamp(0.0, doc.sheetH - s.size.height).toDouble();
    if (_collides(s)) {
      s
        ..rot = r0
        ..flip = f0
        ..x = x0
        ..y = y0;
      _undo.removeLast();
      _toast('مفيش مكان كفاية للف الرمز هنا. حرّكه لمكان فاضي الأول.');
      return;
    }
    AudioService.instance.sfx('assemble_snap');
    _changed();
  }

  void _wireSheet() {
    final wi = selWire;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final w = wi != null && wi < doc.wires.length ? doc.wires[wi] : null;
        final cur = w?.c ?? pen;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(w != null ? 'لون السلك' : 'لون الأسلاك الجديدة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('اللون بيتطبق على السلك المختار، وكمان على أي سلك جديد ترسمه بعد كده.', style: TextStyle(color: CC.muted, height: 1.5)),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final (k, v, name) in [(null, 0xFF1B2330, 'افتراضي'), ...kWireColors])
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (w != null) {
                        _snapshot();
                        w.c = k;
                      }
                      pen = k;
                      set(() {});
                      _changed();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cur == k ? CC.amber : CC.line2, width: cur == k ? 2 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(v),
                            gradient: k == 'gnye' ? const LinearGradient(colors: [Color(0xFF2EAA4A), Color(0xFFFFD60A), Color(0xFF2EAA4A)]) : null,
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(name, style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
              ]),
              if (w != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: w.pts == null
                      ? null
                      : () {
                          _snapshot();
                          w.pts = null;
                          set(() {});
                          _changed();
                        },
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('رجّع السلك لمساره التلقائي'),
                ),
                const SizedBox(height: 6),
                const Text('عشان تنسّق السلك: اسحب أي جزء منه يمين وشمال أو فوق وتحت.', style: TextStyle(color: CC.muted, fontSize: 12.5, height: 1.5)),
              ],
            ]),
          ),
        );
      }),
    );
  }

  void _delete() {
    if (!_editable()) return;
    _snapshot();
    if (selWire != null && selWire! < doc.wires.length) {
      doc.wires.removeAt(selWire!);
      selWire = null;
    } else if (sel != null) {
      final s = doc.byId(sel!);
      if (s != null) doc.removeSym(s);
      sel = null;
    }
    AudioService.instance.sfx('ui_whoosh');
    _changed();
  }

  void _undoAct() {
    if (_undo.isEmpty || !_editable()) return;
    _redo.add(doc.toJsonString());
    doc = SchemDoc.fromJsonString(_undo.removeLast());
    sel = null;
    selWire = null;
    _changed();
  }

  void _redoAct() {
    if (_redo.isEmpty || !_editable()) return;
    _undo.add(doc.toJsonString());
    doc = SchemDoc.fromJsonString(_redo.removeLast());
    _changed();
  }

  // ------------------------------------------------------------ simulation
  void _simulate() {
    if (running) {
      AudioService.instance.sfx('mcb_trip');
      _ticker.stop();
      setState(() {
        sim = null;
        flows = {};
        flash = {};
        _pressBy.clear();
      });
      return;
    }
    if (doc.syms.isEmpty) {
      _toast('الورقة فارغة. افتح المكتبة وأضف الرموز ثم وصّلها.');
      return;
    }
    if (!doc.syms.any((s) => s.d.role == SymRole.source)) {
      _toast('لا توجد تغذية في الرسم. أضف مصدر تغذية (ثلاثي أو وجه واحد) أو خط الطور L1 وخط التعادل N من مجموعة التغذية.');
      return;
    }
    final s = doc.toSim();
    AudioService.instance.sfx('mcb_on');
    s.lab.setPower(true);
    setState(() {
      sim = s;
      pending = null;
      sel = null;
      selWire = null;
    });
    _handle(s.lab.drain());
    flows = _flows();
    if (s.warnings.isNotEmpty) _toast(s.warnings.first);
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  Map<int, int> _flows() {
    final s = sim;
    if (s == null) return {};
    return {
      for (final e in s.lab.flowPaths().entries)
        if (s.wireIndex[e.key] != null) s.wireIndex[e.key]!: e.value
    };
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = now;
    _clock += dt;
    _phase = (_phase + dt * 0.8) % 1;
    if (flash.isNotEmpty && _clock > _flashUntil) flash = {};
    final s = sim;
    if (s == null) {
      _ticker.stop();
      return;
    }
    s.lab.step(dt);
    _handle(s.lab.drain());
    flows = _flows();
    setState(() {});
  }

  SPlaced? _symOfComp(String compId) {
    for (final s in doc.syms) {
      if (s.d.role == SymRole.host && s.tag == compId) return s;
      if (s.id == compId) return s;
    }
    return null;
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
          HapticFeedback.heavyImpact();
          final sh = sim?.lab.short;
          if (sh != null) {
            final pin = sim!.pinToTerm;
            flash = {
              for (var i = 0; i < doc.wires.length; i++)
                if (sh.terms.contains(pin[doc.wires[i].a]) || sh.terms.contains(pin[doc.wires[i].b])) i
            };
            _flashUntil = _clock + (widget.demo > 0 ? 1e9 : 2.0);
          }
          final br = e.id == null ? null : _symOfComp(e.id!);
          _toast('قصر كهربائي! فصل ${br?.tag ?? 'المصدر الرئيسي'}. الأسلاك الوامضة بالأحمر هي مسار القصر.');
        case 'mainTrip':
          _toast('قصر بلا قاطع حماية في المسار: انقطعت التغذية كلها. أضف قاطعًا أو مصهرًا.');
        case 'oltrip':
          a.sfx('overload_trip');
          _toast('فصل الأوفرلود ${e.id} بسبب زيادة التيار.');
        case 'burn':
        case 'mburn':
        case 'pop':
          a.sfx('short_circuit_bang');
          HapticFeedback.heavyImpact();
          final s = e.id == null ? null : _symOfComp(e.id!);
          if (s != null) {
            s.p['burnt'] = true;
            _persist();
          }
          _toast(e.t == 'mburn' ? 'احترق المحرك ${s?.tag ?? ''}: فاز ناقص بلا حماية.' : 'احترق ${s?.tag ?? e.id} لأنه وُصّل على جهد أعلى من جهده.');
        case 'motor':
          final m = e.data['mode'], p = e.data['prev'];
          if ((m == 'star' || m == 'delta') && p == 'off') a.sfx('motor_start');
          if (m == 'off' && (p == 'star' || p == 'delta')) a.sfx('motor_stop');
          if (m == 'single') a.sfx('motor_strain');
        case 'chatter':
          _toast('الدائرة غير مستقرة: ملف يفتح ويغلق باستمرار.');
      }
    }
  }

  void _actuate(SPlaced s, int pointer, bool down) {
    final sm = sim;
    if (sm == null) return;
    final l = sm.lab;
    final id = sm.compOf[s.id];
    if (id == null) return;
    final c = l.byId(id);
    switch (s.d.engine) {
      case 'pb_no':
      case 'pb_nc':
        _pressBy[pointer] = id;
        AudioService.instance.sfx('pushbutton_click');
        l.actuate(id, 'press', true);
      case 'ls':
      case 'prox':
        AudioService.instance.sfx('relay_click');
        if (s.d.params['latch'] == true) {
          // floats, pressure switches, thermostats: a tap changes their state and it stays
          l.actuate(id, 'ls', !(c?.s.act ?? false));
          _toast(c != null && c.s.act ? '${s.tag}: اتفعّل (${_senseText(s.sym)})' : '${s.tag}: رجع لوضعه الطبيعي');
        } else {
          _pressBy[pointer] = id;
          l.actuate(id, 'ls', true);
        }
      case 'estop':
        AudioService.instance.sfx('estop_latch');
        l.actuate(id, 'estop');
      case 'sel':
        AudioService.instance.sfx('selector_detent');
        l.actuate(id, 'sel');
      case 'mcb1':
      case 'mcb2':
      case 'mcb3':
      case 'mcb4':
      case 'rccb':
      case 'mpcb':
      case 'isol3':
      case 'fuse':
        AudioService.instance.sfx(c != null && c.s.on ? 'mcb_trip' : 'mcb_on');
        l.actuate(id, 'mcb');
      case 'motor':
        l.actuate(id, 'load');
        _toast(c?.s.load == true ? 'تم تحميل المحرك بحمل زائد.' : 'رُفع الحمل الزائد.');
      default:
        if (s.d.kind.startsWith('OL') || s.d.engine == 'ol') {
          final host = s.d.engine == 'ol' ? id : l.byId(id)?.attach;
          if (host != null) _olSheet(host);
        }
    }
    _handle(l.drain());
    setState(() {});
  }

  String _senseText(String sym) => switch (sym) {
        'float_no' || 'float_nc' => 'المية وصلت للعوامة',
        'press_no' => 'الضغط وصل للضبط',
        'thermo_nc' => 'الحرارة عدّت الضبط',
        _ => 'فيه حاجة قدام الحساس',
      };

  void _release(int pointer) {
    final id = _pressBy.remove(pointer);
    final l = sim?.lab;
    if (id != null && l != null) {
      final t = l.byId(id)?.type;
      l.actuate(id, t == 'ls' || t == 'prox' ? 'ls' : 'press', false);
      _handle(l.drain());
      setState(() {});
    }
  }

  void _olSheet(String id) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = sim?.lab.byId(id);
        if (c == null) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('أوفرلود $id', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('التيار: ${c.s.current.toStringAsFixed(1)} أمبير · الضبط ${c.num_('set').toStringAsFixed(1)} أمبير${c.s.trip ? ' · مفصول' : ''}', style: const TextStyle(color: CC.muted)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () {
                        sim!.lab.actuate(id, 'oltest');
                        _handle(sim!.lab.drain());
                        set(() {});
                      },
                      child: const Text('TEST اختبار'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      onPressed: () {
                        sim!.lab.actuate(id, 'olreset');
                        _handle(sim!.lab.drain());
                        set(() {});
                      },
                      child: const Text('RESET إعادة ضبط'))),
            ]),
          ]),
        );
      }),
    );
  }

  // ------------------------------------------------------------ sheets
  void _props(SPlaced s) {
    final tagCtl = TextEditingController(text: s.tag);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(String k, Object v) {
          _snapshot();
          s.p[k] = v;
          set(() {});
          _changed();
        }

        Widget chips(String k, List<(Object, String)> opts) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, t) in opts) ChoiceChip(label: Text(t), selected: (s.p[k] ?? s.d.params[k]) == v, onSelected: (_) => upd(k, v)),
            ]);
        final e = s.d.engine;
        final role = s.d.role;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(s.d.nameAr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (s.p['burnt'] == true) ...[
                const Text('هذا المكوّن محترق. صحّح سبب الحريق ثم استبدله.', style: TextStyle(color: CC.red, height: 1.6)),
                const SizedBox(height: 6),
                FilledButton.icon(
                    onPressed: () {
                      _snapshot();
                      s.p.remove('burnt');
                      Navigator.pop(ctx);
                      _changed();
                    },
                    icon: const Icon(Icons.build_rounded),
                    label: const Text('استبدال بمكوّن جديد')),
                const SizedBox(height: 14),
              ],
              if (role == SymRole.contact || role == SymRole.hostPart) ...[
                const Text('يتبع الجهاز', style: TextStyle(color: CC.text2)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in doc.hostTags(kind: role == SymRole.hostPart ? 'NO' : s.d.kind))
                    ChoiceChip(
                        label: Text(t, textDirection: TextDirection.ltr),
                        selected: s.tag == t,
                        onSelected: (_) {
                          _snapshot();
                          s.tag = t;
                          set(() {});
                          _changed();
                        }),
                ]),
                if (doc.hostTags(kind: role == SymRole.hostPart ? 'NO' : s.d.kind).isEmpty)
                  const Text('أضف أولًا الملف أو الأوفرلود الذي يتبعه هذا التلامس.', style: TextStyle(color: CC.muted)),
                const SizedBox(height: 12),
              ] else if (role != SymRole.source) ...[
                TextField(
                  controller: tagCtl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رمز الجهاز (مثل K1 أو S2)', isDense: true),
                  onSubmitted: (v) => _rename(s, v),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) _rename(s, v, quiet: true);
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (e == 'kc' && role == SymRole.host || e == 'relay') ...[
                const Text('جهد الملف', style: TextStyle(color: CC.text2)),
                const SizedBox(height: 6),
                chips('coilV', [(24.0, '24 فولت'), (110.0, '110 فولت'), (220.0, '220 فولت'), (380.0, '380 فولت')]),
                const SizedBox(height: 12),
              ],
              if (e == 'timer') ...[
                const Text('نوع التأخير', style: TextStyle(color: CC.text2)),
                const SizedBox(height: 6),
                chips('mode', [('on', 'تأخير توصيل ON-DELAY'), ('off', 'تأخير فصل OFF-DELAY')]),
                const SizedBox(height: 10),
                Text('الزمن: ${((s.p['T'] ?? 5) as num).round()} ثانية', style: const TextStyle(color: CC.text2)),
                Slider(min: 1, max: 30, divisions: 29, value: ((s.p['T'] ?? 5) as num).toDouble(), onChanged: (v) => upd('T', v)),
              ],
              if (e == 'lamp') ...[
                if (s.sym == 'lamp') ...[
                  const Text('اللون', style: TextStyle(color: CC.text2)),
                  const SizedBox(height: 6),
                  chips('col', [('g', 'أخضر'), ('r', 'أحمر'), ('y', 'أصفر'), ('b', 'أزرق'), ('w', 'أبيض')]),
                  const SizedBox(height: 10),
                ],
                const Text('جهد التشغيل', style: TextStyle(color: CC.text2)),
                const SizedBox(height: 6),
                chips('V', [(24.0, '24 فولت'), (220.0, '220 فولت')]),
              ],
              const SizedBox(height: 12),
              const Text('الاتجاه', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () {
                          _turn();
                          set(() {});
                        },
                        icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
                        label: const Text('لف 90°'))),
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () {
                          _turn(mirror: true);
                          set(() {});
                        },
                        icon: const Icon(Icons.flip_rounded),
                        label: const Text('قلب (مراية)'))),
              ]),
              if (e == 'ol') ...[
                Text('ضبط التيار: ${((s.p['set'] ?? 8.5) as num).toStringAsFixed(1)} أمبير', style: const TextStyle(color: CC.text2)),
                Slider(min: 4, max: 14, divisions: 40, value: ((s.p['set'] ?? 8.5) as num).toDouble(), onChanged: (v) => upd('set', v)),
              ],
              if (e == 'motor') ...[
                Text('التيار الاسمي: ${((s.p['In'] ?? 8.5) as num).toStringAsFixed(1)} أمبير', style: const TextStyle(color: CC.text2)),
                Slider(min: 2, max: 20, divisions: 36, value: ((s.p['In'] ?? 8.5) as num).toDouble(), onChanged: (v) => upd('In', v)),
              ],
            ]),
          ),
        );
      }),
    );
  }

  /// rename a device; its contacts follow the new tag
  void _rename(SPlaced s, String v, {bool quiet = false}) {
    final t = v.trim().toUpperCase();
    if (t.isEmpty || t == s.tag) return;
    if (s.d.role == SymRole.device && doc.syms.any((o) => o.id != s.id && o.tag == t)) {
      if (!quiet) _toast('الرمز $t مستخدم بالفعل.');
      return;
    }
    final old = s.tag;
    for (final o in doc.syms) {
      if (o.tag == old && (o.d.role == SymRole.contact || o.d.role == SymRole.hostPart || o.d.role == SymRole.host)) o.tag = t;
    }
    s.tag = t;
    _changed();
  }

  void _renameSheet() {
    final ctl = TextEditingController(text: doc.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الدائرة'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                doc.title = ctl.text.trim().isEmpty ? doc.title : ctl.text.trim();
                Navigator.pop(ctx);
                _changed();
              },
              child: const Text('حفظ')),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    _toast('جارٍ تجهيز ملف PDF…');
    try {
      final bytes = await schematicPdf(doc);
      final d = widget.deliver;
      if (d == null) return;
      final name = 'ControlAcademy_schematic_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final where = await d(bytes, name, 'application/pdf');
      if (where != null) _toast(where == 'shared' ? 'الملف جاهز للطباعة أو الحفظ أو المشاركة' : 'اتحفظ في: $where');
    } catch (_) {
      _toast('تعذّر تجهيز الملف، جرّب مرة أخرى.');
    }
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.save_outlined, color: CC.accentSoft),
              title: const Text('حفظ وفتح المشاريع'),
              onTap: () {
                Navigator.pop(ctx);
                showProjectsSheet(context, kind: 'schem', suggestedName: doc.title, current: doc.toJsonString, onOpen: (j, n) {
                  if (running) _simulate();
                  _snapshot();
                  doc = SchemDoc.fromJsonString(j);
                  _changed();
                  _fit();
                });
              }),
          ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: CC.accentSoft),
              title: const Text('طباعة / تصدير PDF'),
              subtitle: const Text('رسم الدائرة وقائمة المكونات', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                _exportPdf();
              }),
          ListTile(
              leading: const Icon(Icons.auto_fix_high_rounded, color: CC.accentSoft),
              title: const Text('ترتيب كل الأسلاك تلقائيًا'),
              subtitle: const Text('يلغي أي تنسيق يدوي للأسلاك', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                if (!_editable()) return;
                _snapshot();
                for (final w in doc.wires) {
                  w.pts = null;
                }
                _changed();
              }),
          ListTile(
              leading: const Icon(Icons.edit_outlined, color: CC.accentSoft),
              title: const Text('تغيير اسم الدائرة'),
              onTap: () {
                Navigator.pop(ctx);
                _renameSheet();
              }),
          ListTile(
              leading: const Icon(Icons.auto_awesome_outlined, color: CC.accentSoft),
              title: const Text('مثال محلول: تشغيل مباشر DOL'),
              onTap: () {
                Navigator.pop(ctx);
                if (!_editable()) return;
                _snapshot();
                doc = dolSchematic();
                _changed();
                _fit();
              }),
          ListTile(
              leading: const Icon(Icons.note_add_outlined, color: CC.accentSoft),
              title: const Text('ورقة جديدة فارغة'),
              onTap: () {
                Navigator.pop(ctx);
                if (!_editable()) return;
                _snapshot();
                doc = SchemDoc();
                _changed();
                _fit();
              }),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pf = _wireFrom == null ? null : doc.pinPos(_wireFrom!);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR): _turn,
        const SingleActivator(LogicalKeyboardKey.keyF): () => _turn(mirror: true),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (sel != null || selWire != null) _delete();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoAct,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoAct,
      },
      child: Focus(autofocus: true, child: _scaffold(context, pf)),
    );
  }

  Widget _scaffold(BuildContext context, Offset? pf) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF070C1A))),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: tc,
            constrained: false,
            minScale: 0.15,
            maxScale: 6,
            panEnabled: _dragId == null && _wireFrom == null && _leg == null,
            scaleEnabled: _dragId == null && _wireFrom == null && _leg == null,
            boundaryMargin: const EdgeInsets.all(1600),
            onInteractionUpdate: (_) => setState(() {}),
            child: SizedBox(
              width: doc.sheetW * kG,
              height: doc.sheetH * kG,
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: SheetPainter(doc,
                        sim: sim,
                        flows: flows,
                        flash: flash,
                        phase: _phase,
                        selected: sel,
                        selWire: selWire,
                        pending: pending ?? _wireFrom,
                        drag: pf != null && _wireTo != null ? (pf, _wireTo!, doc.pinUp(_wireFrom!)) : null,
                        date: todayText()),
                  ),
                ),
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
        if (showUi) ..._overlays(context) else _restore(),
      ]),
    );
  }

  Widget _restore() => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 12,
        child: Glass(radius: 22, child: IconButton(onPressed: () => setState(() => showUi = true), icon: const Icon(Icons.unfold_more_rounded, color: CC.text))),
      );

  List<Widget> _overlays(BuildContext context) {
    final top = MediaQuery.of(context).padding.top, bottom = MediaQuery.of(context).padding.bottom;
    final selS = sel == null ? null : doc.byId(sel!);
    final status = pending != null
        ? 'اختر الطرف الثاني للسلك…'
        : _wireFrom != null
            ? 'اسحب إلى الطرف الآخر ثم اترك…'
            : running
                ? (flash.isNotEmpty ? 'قصر كهربائي! أوقف المحاكاة وصحّح التوصيل' : 'المحاكاة تعمل · اضغط على الضواغط والقواطع في الرسم')
                : _leg != null
                    ? 'حرّك السلك لمكانه ثم اترك…'
                    : '${doc.title} · اسحب من طرف رمز إلى طرف آخر لرسم سلك، واسحب السلك نفسه لتنسيقه';
    return [
      Positioned(
        top: top + 10,
        left: 12,
        right: 12,
        child: Row(children: [
          Glass(radius: 22, child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_forward_rounded, color: CC.text))),
          const SizedBox(width: 8),
          Expanded(
            child: Glass(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: running ? (flash.isNotEmpty ? CC.red : CC.green) : CC.muted, boxShadow: running ? glow(CC.green) : null)),
                const SizedBox(width: 8),
                Expanded(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
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
                  icon: const Icon(Icons.fullscreen_rounded, color: CC.text))),
        ]),
      ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        top: top + 70,
        bottom: bottom + 96,
        right: libOpen ? 12 : -340,
        width: 320,
        child: _library(),
      ),
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
                _tool(Icons.add_rounded, 'مكتبة الرموز', () => setState(() => libOpen = !libOpen), active: libOpen),
                _SimButton(on: running, onTap: _simulate),
                _tool(Icons.center_focus_strong_rounded, 'ملء الشاشة', _fit),
                _tool(Icons.undo_rounded, 'تراجع', _undo.isEmpty ? null : _undoAct),
                _tool(Icons.redo_rounded, 'إعادة', _redo.isEmpty ? null : _redoAct),
                if (selS != null) _tool(Icons.tune_rounded, 'الخصائص', () => _props(selS)),
                if (selS != null) _tool(Icons.rotate_90_degrees_cw_rounded, 'لف 90° (R)', _turn),
                if (selS != null) _tool(Icons.flip_rounded, 'قلب (F)', () => _turn(mirror: true)),
                _penTool(),
                if (selS != null || selWire != null) _tool(Icons.delete_outline_rounded, 'حذف', _delete, danger: true),
                _tool(Icons.picture_as_pdf_outlined, 'PDF', _exportPdf),
                _tool(Icons.more_horiz_rounded, 'المزيد', _more),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _penTool() {
    final w = selWire != null && selWire! < doc.wires.length ? doc.wires[selWire!] : null;
    final col = wireColor(w?.c ?? pen) ?? CC.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: w != null ? 'لون السلك وتنسيقه' : 'لون الأسلاك',
        onPressed: running ? null : _wireSheet,
        style: IconButton.styleFrom(backgroundColor: w != null ? const Color(0x333D8BFF) : null),
        icon: Icon(Icons.palette_outlined, color: running ? CC.line2 : col, size: 26),
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

  Widget _library() {
    return Glass(
      radius: 24,
      tint: const Color(0xFA0A1228),
      child: ListView(padding: const EdgeInsets.fromLTRB(8, 10, 8, 12), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text('مكتبة الرموز IEC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        for (final (name, col, keys) in kSymCategories)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(col))),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              children: [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.78,
                  children: [for (final k in keys) _libItem(kSyms[k]!)],
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _libItem(SymDef d) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _add(d.key),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Expanded(child: CustomPaint(painter: _Thumb(d), size: Size.infinite)),
            const SizedBox(height: 4),
            Text(d.nameAr, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: kInk, height: 1.25)),
          ]),
        ),
      );
}

class _Thumb extends CustomPainter {
  final SymDef d;
  _Thumb(this.d);
  @override
  void paint(Canvas c, Size size) {
    final w = (d.w + 1.6) * kG, h = (d.h + 0.4) * kG;
    final s = math.min(size.width / w, size.height / h);
    c.translate((size.width - d.w * kG * s) / 2 + 0.3 * kG * s, (size.height - d.h * kG * s) / 2);
    c.scale(s);
    paintSymbol(c, d, labels: d.role == SymRole.source);
  }

  @override
  bool shouldRepaint(covariant _Thumb old) => old.d != d;
}

class _SimButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _SimButton({required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(colors: on ? const [Color(0xFFFF7A7A), Color(0xFFD7263D)] : const [Color(0xFF4BE39A), Color(0xFF16A35B)]),
              boxShadow: glow(on ? CC.red : CC.green, 1.0),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 4),
              Text(on ? 'إيقاف' : 'محاكاة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ),
      );
}
