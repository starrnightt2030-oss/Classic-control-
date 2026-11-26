// «معمل اللوحة» — full-screen panel builder + live simulation.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_service.dart';
import '../sim/engine.dart';
import '../sim/plant.dart';
import '../ui/icons.dart';
import '../ui/perf.dart';
import '../ui/theme.dart';
import '../schem/ladder.dart';
import '../schem/machine3d.dart';
import '../schem/sheet_paint.dart';
import '../schem/symbols.dart' show kG;
import '../sim/circuits.dart';
import 'catalog.dart';
import 'machine_sprites.dart';
import 'exercise.dart';
import 'faults.dart';
import 'model.dart';
import 'paint.dart';
import 'projects.dart';
import 'templates.dart';

const _prefKey = 'lab_doc_v3';
const showUiBottom = 100.0;

class LabPage extends StatefulWidget {
  /// 0 normal · 1 DOL demo running · 2 library open · 3 short circuit · 4 burnt lamp · 5 bench
  /// · 7 all the machines running (CI screenshots)
  final int demo;

  /// open one of the classic circuits as a wiring exercise (devices mounted, schematic beside)
  final String? exercise;
  const LabPage({super.key, this.demo = 0, this.exercise});
  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with SingleTickerProviderStateMixin {
  LabDoc doc = LabDoc();
  bool ready = false;
  final tc = TransformationController();
  final List<String> _undo = [], _redo = [];

  // exercise mode
  LabExercise? ex;
  bool schemOpen = false;
  final Set<int> tasksDone = {};

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

  // clip-on parts (overload / aux block): the contactor it would snap onto, where it came from
  Placed? _snapHost;
  String? _clipFrom;

  // hand wiring by dragging from a terminal
  String? _wireFrom;
  Offset? _wireTo;

  /// how the sorting belt / press / filling line look before the power is on
  final Map<String, Plant> _idlePlants = {};

  // effects: sparks at shorts, smoke from burnt parts, flashing shorted wires
  final List<LabFx> fx = [];
  double _clock = 0;
  Set<int> flash = {};
  double _flashUntil = 0;
  Map<int, int> flows = {};

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
    MachineSprites.loadAll().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    AudioService.instance.stopLoops();
    _ticker.dispose();
    _save?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    await Sprites.load();
    final prefs = await SharedPreferences.getInstance();
    final exId = widget.exercise;
    final c = exId == null ? null : circuitById(exId);
    if (c != null) ex = buildExercise(c);
    final s = widget.demo > 0 ? null : prefs.getString(_storeKey);
    LabDoc d;
    try {
      d = ex != null ? (s == null ? ex!.doc : LabDoc.fromJsonString(s)) : switch (widget.demo) {
        1 => dolTemplate(),
        3 => shortDemo(),
        4 => burnDemo(),
        5 => benchDemo(),
        7 => machinesDemo(),
        _ => s == null || widget.demo > 0 ? emptyPanel() : LabDoc.fromJsonString(s),
      };
    } catch (_) {
      d = emptyPanel();
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
      if (ex != null) setState(() => schemOpen = true);
      if (widget.demo == 6) {
        // preview: the exercise wired with its reference solution and started
        for (final w in ex!.reference) {
          doc.wires.add(LabWire(w.a, w.b, w.power ? (const {'br': 'br', 'bk': 'bk', 'gr': 'gy', 'gy': 'ge', 'bu': 'bu'}[w.col] ?? 'rd') : (w.col == 'bu' ? 'bu' : 'rd')));
        }
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          _power();
          sim?.actuate('S1', 'press', true);
          Future<void>.delayed(const Duration(milliseconds: 400), () => sim?.actuate('S1', 'press', false));
        });
      }
      if (widget.demo == 3 || widget.demo == 4 || widget.demo == 5 || widget.demo == 7) Future<void>.delayed(const Duration(milliseconds: 600), _power);
    });
  }

  String get _storeKey => widget.exercise == null ? _prefKey : 'lab_ex_${widget.exercise}';

  void _persist() {
    if (widget.demo > 0) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storeKey, doc.toJsonString());
    });
  }

  // ------------------------------------------------------------ exercise
  void _checkTasks() {
    final e = ex, l = sim;
    if (e == null || l == null) return;
    final tasks = e.circuit.tasks;
    for (var i = 0; i < tasks.length; i++) {
      if (tasksDone.contains(i)) continue;
      // tasks are done in order
      if (i > 0 && !tasksDone.contains(i - 1)) break;
      if (tasks[i].done(l)) {
        tasksDone.add(i);
        AudioService.instance.sfx(i == tasks.length - 1 ? 'success_fanfare' : 'success_chime');
        _toast(i == tasks.length - 1 ? 'ممتاز! أنهيت كل مهام التمرين.' : 'أحسنت: ${tasks[i].text}');
      }
    }
  }

  void _checkWiring() {
    final e = ex;
    if (e == null) return;
    final diff = doc.toLab().wiringDiff(e.reference);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Row(children: [
              Icon(diff.ok ? Icons.verified_rounded : Icons.rule_rounded, color: diff.ok ? CC.green : CC.gold),
              const SizedBox(width: 8),
              Text(diff.ok ? 'التوصيل مطابق للمخطط' : 'نتيجة فحص التوصيل', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            if (diff.ok)
              const Text('كل الأسلاك في مكانها الصحيح. شغّل التغذية ونفّذ مهام التمرين.', style: TextStyle(height: 1.6))
            else ...[
              Text('ناقص ${diff.missing.length} توصيلة، وزائد ${diff.extra.length}.', style: const TextStyle(color: CC.text2)),
              const SizedBox(height: 10),
              if (diff.missing.isNotEmpty) const Text('توصيلات ناقصة', style: TextStyle(fontWeight: FontWeight.w700, color: CC.gold)),
              for (final w in diff.missing.take(30))
                ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_link_rounded, color: CC.gold),
                    title: Text('${prettyTerm(w.a)}   ←→   ${prettyTerm(w.b)}', textDirection: TextDirection.ltr, textAlign: TextAlign.right)),
              if (diff.extra.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('أسلاك ليست في المخطط', style: TextStyle(fontWeight: FontWeight.w700, color: CC.red)),
                for (final w in diff.extra.take(30))
                  ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link_off_rounded, color: CC.red),
                      title: Text('${prettyTerm(w.a)}   ←→   ${prettyTerm(w.b)}', textDirection: TextDirection.ltr, textAlign: TextAlign.right)),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  void _showSolution() {
    final e = ex;
    if (e == null || !_editable()) return;
    _snapshot();
    doc.wires.clear();
    for (final w in e.reference) {
      final col = w.power ? (const {'br': 'br', 'bk': 'bk', 'gr': 'gy', 'gy': 'ge', 'bu': 'bu'}[w.col] ?? 'rd') : (w.col == 'bu' ? 'bu' : 'rd');
      doc.wires.add(LabWire(w.a, w.b, col));
    }
    _toast('هذا هو التوصيل الصحيح. جرّب أن تمسحه وتوصّله بنفسك.');
    _changed();
  }

  void _resetExercise() {
    final e = ex;
    if (e == null || !_editable()) return;
    _snapshot();
    doc = buildExercise(e.circuit).doc;
    tasksDone.clear();
    _changed();
    _fit();
  }

  Widget _schemPanel(double top, double bottom) {
    final e = ex!;
    final ready = readyById(e.circuit.id);
    final sheet = ready?.build();
    final w = MediaQuery.of(context).size.width;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      top: top + 70,
      bottom: bottom + 96,
      left: schemOpen ? 12 : -(math.min(560.0, w * 0.92) + 20),
      width: math.min(560.0, w * 0.92),
      child: Glass(
        radius: 24,
        tint: const Color(0xF20A1228),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
            child: Row(children: [
              Expanded(child: Text(e.circuit.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              IconButton(onPressed: () => setState(() => schemOpen = false), icon: const Icon(Icons.close_rounded, color: CC.text2)),
            ]),
          ),
          if (sheet != null)
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: Colors.white,
                    child: LayoutBuilder(builder: (ctx, c) {
                      final sw = sheet.sheetW * kG, sh = sheet.sheetH * kG;
                      final k = math.min(c.maxWidth / sw, c.maxHeight / sh);
                      return InteractiveViewer(
                        minScale: 1,
                        maxScale: 8,
                        child: Center(child: SizedBox(width: sw * k, height: sh * k, child: FittedBox(child: SizedBox(width: sw, height: sh, child: CustomPaint(painter: SheetPainter(sheet, print: true)))))),
                      );
                    }),
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 4,
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), children: [
              Text(e.circuit.desc, style: const TextStyle(color: CC.text2, height: 1.6, fontSize: 13)),
              const SizedBox(height: 6),
              Text('نصيحة: ${e.circuit.tip}', style: const TextStyle(color: CC.gold, height: 1.6, fontSize: 12.5)),
              const SizedBox(height: 10),
              const Text('المهام', style: TextStyle(fontWeight: FontWeight.w700)),
              for (var i = 0; i < e.circuit.tasks.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(tasksDone.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 20, color: tasksDone.contains(i) ? CC.green : CC.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.circuit.tasks[i].text, style: TextStyle(fontSize: 13, color: tasksDone.contains(i) ? CC.green : CC.text))),
                  ]),
                ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: _checkWiring, icon: const Icon(Icons.fact_check_outlined), label: const Text('فحص التوصيل')),
                OutlinedButton.icon(onPressed: _showSolution, icon: const Icon(Icons.lightbulb_outline_rounded), label: const Text('عرض الحل')),
                OutlinedButton.icon(onPressed: _resetExercise, icon: const Icon(Icons.restart_alt_rounded), label: const Text('بدء من جديد')),
              ]),
            ]),
          ),
        ]),
      ),
    );
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
    final w = doc.totalW * kPx, h = doc.plateH * kPx;
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
    final t0 = _termAt(mm);
    if (t0 != null) {
      if (!meter) setState(() => _wireFrom = t0); // drag out a wire (or tap: handled on up)
      return;
    }
    final p = _partAt(mm);
    if (p != null && (p.id == selPart || !p.structural)) {
      // a clip-on part (overload / aux block) is pulled off its contactor and moved alone
      final root = (p.attach != null && p.d.attachTo == null) ? doc.byId(p.attach!) ?? p : p;
      if (p.d.attachTo != null) _clipFrom = p.attach;
      setState(() => dragId = root.id);
      _partStart = Offset(root.x, root.y);
      final partners = {for (final m in doc.mech) if (m.contains(root.id)) m[0] == root.id ? m[1] : m[0]};
      _childStart
        ..clear()
        ..addEntries([
          for (final c in doc.parts)
            if (c.attach == root.id || partners.contains(c.id) || (c.attach != null && partners.contains(c.attach))) MapEntry(c.id, Offset(c.x, c.y))
        ]);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _pointer && _wireFrom != null && _downMm != null) {
      final mm = e.localPosition / kPx;
      if (_wireTo != null || (mm - _downMm!).distance > 2.5) setState(() => _wireTo = mm);
      return;
    }
    if (e.pointer != _pointer || dragId == null || _downMm == null) return;
    final mm = e.localPosition / kPx;
    final d = mm - _downMm!;
    if (!_moved && d.distance < 1.5) return;
    if (!_moved) {
      _snapshot();
      _moved = true;
    }
    final p = doc.byId(dragId!)!;
    if (p.d.attachTo != null && p.attach != null) p.attach = null; // lifted off
    p.x = _partStart!.dx + d.dx;
    p.y = _partStart!.dy + d.dy;
    for (final c in doc.parts) {
      final s = _childStart[c.id];
      if (s != null) {
        c.x = s.dx + d.dx;
        c.y = s.dy + d.dy;
      }
    }
    _snapHost = _clipHost(p);
    _blocked = _snapHost == null && _collides(p);
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
    if (_wireFrom != null && _wireTo != null) {
      final from = _wireFrom!;
      final to = _termAt(mm);
      setState(() {
        _wireFrom = null;
        _wireTo = null;
        pending = null;
      });
      if (to != null && to != from) {
        _connect(from, to);
      } else {
        AudioService.instance.sfx('ui_whoosh');
      }
      return;
    }
    _wireFrom = null;
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
    _wireFrom = null;
    _wireTo = null;
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
    final a = pending!;
    pending = null;
    _connect(a, t);
  }

  /// a new wire between two terminals (max two wires under one screw)
  void _connect(String a, String t) {
    int count(String k) => doc.wires.where((w) => w.a == k || w.b == k).length;
    if (count(a) >= 2 || count(t) >= 2) {
      _toast('الطرف عليه سلكان بالفعل. لا يُربط أكثر من سلكين تحت مسمار واحد.');
      AudioService.instance.sfx('soft_fail');
      setState(() {});
      return;
    }
    if (doc.wires.any((w) => (w.a == t && w.b == a) || (w.b == t && w.a == a))) {
      setState(() {});
      return;
    }
    _snapshot();
    final c = color == 'auto' ? _autoColor(a, t) : color;
    doc.wires.add(LabWire(a, t, c));
    AudioService.instance.sfx('screw_tighten');
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
      if (p.d.engine == 'motor') return {'U1': 'br', 'V1': 'bk', 'W1': 'gy', 'U2': 'br', 'V2': 'bk', 'W2': 'gy'}[t] ?? '';
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

  /// reversing contactor: two contactors side by side with a mechanical interlock between them
  void _addReversing() {
    _addPart('kc');
    final a = doc.parts.last;
    if (a.def != 'kc') return;
    final b = Placed(doc.nextId('K'), 'kc', a.x + a.size.width + 4, a.y, p: {...kLabParts['kc']!.params});
    doc.parts.add(b);
    if (_collides(b)) {
      // no room on the right: try the left
      b.x = a.x - b.size.width - 4;
      if (_collides(b)) {
        doc.parts.remove(b);
        _toast('لا توجد مساحة لكونتاكتور ثانٍ بجانب ${a.id}. أفسح مكانًا على القضيب ثم حاول مرة أخرى.');
        return;
      }
    }
    doc.mech.add([a.id, b.id]);
    AudioService.instance.sfx('din_rail_click');
    _toast('كونتاكتور عاكس: ${a.id} و ${b.id} بينهما منع تداخل ميكانيكي، فلا يُغلقان معًا. أضف أيضًا منع التداخل الكهربائي بالنقاط المغلقة.');
    _changed();
  }

  // --------------------------------------------------------------- placing
  /// contactor a dragged clip-on part would plug into (its terminals line up within 18 mm)
  Placed? _clipHost(Placed p) {
    final want = p.d.attachTo;
    if (want == null) return null;
    Placed? best;
    var bd = 18.0;
    for (final q in doc.parts) {
      if (q.d.engine != want || q.id == p.id) continue;
      if (doc.parts.any((o) => o.attach == q.id && o.def == p.def && o.id != p.id)) continue;
      final ghost = Placed('${p.id}~', p.def, 0, 0);
      placeAttached(ghost, q);
      final dd = (Offset(ghost.x, ghost.y) - Offset(p.x, p.y)).distance;
      if (dd < bd) {
        bd = dd;
        best = q;
      }
    }
    return best;
  }

  bool _collides(Placed p) {
    // a contactor and everything clipped onto it count as one block
    final root = p.attach != null ? (doc.byId(p.attach!) ?? p) : p;
    final family = {p.id, root.id, for (final c in doc.parts) if (c.attach == root.id) c.id};
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
    final areas = [doc.plateRect, if (p.d.mount == Mount.free && doc.benchRect != null) doc.benchRect!];
    for (final r in mine) {
      if (!areas.any((a) => a.inflate(0.01).contains(r.topLeft) && a.inflate(0.01).contains(r.bottomRight))) return true;
    }
    return false;
  }

  void _drop(Placed p) {
    // DIN mounting: snap the part's centre line onto the nearest rail
    if (p.d.mount == Mount.din && p.attach == null && p.d.attachTo == null) {
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
    final prevHost = _clipFrom;
    if (p.d.attachTo != null) {
      final host = _clipHost(p);
      _snapHost = null;
      if (host != null) {
        p.attach = host.id;
        placeAttached(p, host);
        if (_clipFrom != host.id) _toast('تم تركيب ${p.d.nameAr} ${p.id} على الكونتاكتور ${host.id}.');
      } else {
        p.attach = null;
        if (_clipFrom != null && _clipFrom!.isNotEmpty) _toast('فُكّ ${p.id} من الكونتاكتور ${_clipFrom!}. اسحبه قريبًا من مخارج كونتاكتور ليُركَّب عليه.');
      }
      _clipFrom = null;
    }
    // door devices snap into the nearest free hole of the door
    final door = doc.doorRect;
    if (p.d.side.isNotEmpty && door != null && door.contains(p.rect.center)) {
      final taken = {
        for (final o in doc.parts)
          if (o.id != p.id && o.d.side.isNotEmpty) o.rect.center
      };
      Offset? best;
      var bd = double.infinity;
      for (final h in doc.doorHoles()) {
        if (taken.any((t) => (t - h).distance < 20)) continue;
        final dd = (h - p.rect.center).distance;
        if (dd < bd) {
          bd = dd;
          best = h;
        }
      }
      if (best != null) {
        p.x = best.dx - p.size.width / 2;
        p.y = best.dy - p.size.height / 2;
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
      if (p.d.attachTo != null && prevHost != null && prevHost.isNotEmpty) {
        // dropped on a busy spot: it goes back onto its contactor
        final h = doc.byId(prevHost);
        if (h != null) {
          p.attach = h.id;
          placeAttached(p, h);
        }
      }
      if (_undo.isNotEmpty) _undo.removeLast();
      _toast('المكان مشغول. اترك مسافة بين المكونات.');
      AudioService.instance.sfx('soft_fail');
    } else {
      AudioService.instance.sfx(p.d.mount == Mount.din ? 'din_rail_click' : 'assemble_snap');
    }
    _blocked = false;
    _changed();
  }

  void _addPart(String def) {
    if (!_editable()) return;
    if (def == 'kc_rev') {
      _addReversing();
      return;
    }
    final d = kLabParts[def]!;
    final c = _viewCenterMm();
    final id = doc.nextId(d.prefix);
    final p = Placed(id, def, 0, 0, p: {
      ...d.params,
      if (kStructural.contains(def)) 'len': 400.0,
    });
    // motors, machines and door devices start on the bench, the rest on the plate
    final bench = doc.benchRect;
    final area = (p.d.mount == Mount.free && bench != null && (p.d.machine != null || p.d.engine.startsWith('motor') || p.d.side.isNotEmpty))
        ? bench
        : doc.plateRect;
    final cc = area.contains(c) ? c : area.center;
    double cx(double v) => v.clamp(area.left, math.max(area.left, area.right - p.size.width)).toDouble();
    double cy(double v) => v.clamp(area.top, math.max(area.top, area.bottom - p.size.height)).toDouble();
    p.x = cx(cc.dx - p.size.width / 2);
    p.y = cy(cc.dy - p.size.height / 2);
    // find a free spot near the centre
    for (var i = 0; i < 240 && _collides(p); i++) {
      final a = i * 0.7, r = 6.0 + i * 3;
      p.x = cx(cc.dx - p.size.width / 2 + math.cos(a) * r);
      p.y = cy(cc.dy - p.size.height / 2 + math.sin(a) * r);
    }
    if (p.d.machine != null) {
      final m = doc.parts.where((q) => q.d.engine == 'motor' || q.d.engine == 'motor1').firstOrNull;
      if (m != null) p.p['motor'] = m.id;
    }
    _snapshot();
    doc.parts.add(p);
    _partStart = Offset(p.x, p.y);
    _childStart.clear();
    if (p.d.attachTo != null) {
      _clipFrom = '';
      _toast(p.def == 'ol'
          ? 'اسحب الأوفرلود إلى أسفل الكونتاكتور حتى يتلوّن الكونتاكتور بالأخضر، ثم اتركه ليُركَّب.'
          : 'اسحب بلوك النقاط إلى جانب الكونتاكتور حتى يتلوّن بالأخضر، ثم اتركه ليُركَّب.');
    }
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
      AudioService.instance.stopLoops();
      if (fx.isEmpty) _ticker.stop();
      setState(() {
        sim = null;
        flows = {};
        flash = {};
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
    flows = l.flowPaths();
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = now;
    _clock += dt;
    _phase = (_phase + dt * 0.8) % 1;
    fx.removeWhere((f) => _clock - f.born > f.life);
    if (flash.isNotEmpty && _clock > _flashUntil) flash = {};
    final l = sim;
    if (l != null) {
      l.step(dt);
      _handle(l.drain());
      _sounds(l);
      fault?.tick(dt);
      _checkTasks();
    } else if (fx.isEmpty) {
      _ticker.stop();
      _last = Duration.zero;
    }
    // physics every frame, the screen at Perf.simFps (see lib/ui/perf.dart)
    if (_ticker.isActive && _clock - _drawnAt < Perf.simFrame * 0.9) return;
    _drawnAt = _clock;
    if (l != null) flows = l.flowPaths();
    setState(() {});
  }

  double _drawnAt = -1;

  /// continuous sounds: running motors, humming coils / stalled motors, sirens
  void _sounds(Lab l) {
    final a = AudioService.instance;
    var spd = 0.0, strain = false, hum = false, siren = false;
    for (final c in l.comps) {
      if (c.type == 'motor' || c.type == 'motor1') {
        if (c.s.mode == 'star' || c.s.mode == 'delta' || c.s.mode == 'run') spd = math.max(spd, c.s.spd);
        if (c.s.mode == 'single' || c.s.mode == 'over') strain = true;
      }
      if (c.s.hum && !c.s.dead) hum = true;
      if (c.type == 'lamp' && c.p['snd'] == 'siren' && !c.s.dead && c.s.v > c.num_('V') * 0.6) siren = true;
    }
    a.loop('motor_run', spd > 0.04, volume: 0.15 + 0.6 * spd);
    a.loop('coil_hum_loud', strain || hum, volume: strain ? 0.7 : 0.4);
    a.loop('alarm_siren', siren, volume: 0.55);
  }

  /// sparks where the two sources met, the shorted wires flash red
  void _sparkAt(ShortInfo sh) {
    final terms = sh.terms;
    final idx = <int>{for (var i = 0; i < doc.wires.length; i++) if (terms.contains(doc.wires[i].a) || terms.contains(doc.wires[i].b)) i};
    flash = idx;
    _flashUntil = _clock + (widget.demo > 0 ? 1e9 : 1.8);
    // the newest wire in the shorted net is the most likely culprit
    final spots = <Offset>[];
    final newest = idx.isEmpty ? null : idx.reduce(math.max);
    if (newest != null) {
      final w = doc.wires[newest];
      for (final k in [w.a, w.b]) {
        final o = doc.termPos(k);
        if (o != null) spots.add(o);
      }
    }
    if (spots.isEmpty) {
      for (final k in terms.take(2)) {
        final o = doc.termPos(k);
        if (o != null) spots.add(o);
      }
    }
    for (final o in spots) {
      fx.add(LabFx('spark', o, _clock, fx.length * 31 + o.dx.round(), loop: widget.demo > 0));
    }
    HapticFeedback.heavyImpact();
    if (!_ticker.isActive) _ticker.start();
  }

  /// a part burnt out: it stays burnt (also after power off) until replaced
  void _burn(String id) {
    final p = doc.byId(id);
    if (p == null) return;
    p.p['burnt'] = true;
    final r = p.rect;
    fx.add(LabFx('spark', Offset(r.center.dx, r.top + r.height * 0.3), _clock, id.hashCode, loop: widget.demo > 0));
    fx.add(LabFx('smoke', Offset(r.center.dx, r.top + r.height * 0.25), _clock, id.hashCode + 1, loop: widget.demo > 0));
    HapticFeedback.heavyImpact();
    _persist();
    if (!_ticker.isActive) _ticker.start();
  }

  void _replace(Placed p) {
    _snapshot();
    p.p.remove('burnt');
    AudioService.instance.sfx('assemble_snap');
    _toast('تم تركيب ${p.d.nameAr} جديد مكان المحترق.');
    _changed();
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
          final sh = sim?.short;
          if (sh != null) _sparkAt(sh);
          _toast('قصر كهربائي! فصل ${e.id ?? 'المصدر الرئيسي'}. الأسلاك الحمراء الوامضة هي مسار القصر.');
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
          a.sfx('short_circuit_bang');
          if (e.id != null) _burn(e.id!);
          _toast(e.t == 'mburn'
              ? 'احترق المحرك ${e.id}: عمل على فاز ناقص بدون حماية أوفرلود.'
              : 'احترق ${e.id} لأنه وُصّل على جهد أعلى من جهده. استبدله من الخصائص.');
        case 'motor':
          final m = e.data['mode'], p = e.data['prev'];
          if ((m == 'star' || m == 'delta' || m == 'run') && p == 'off') a.sfx('motor_start');
          if (m == 'off' && (p == 'star' || p == 'delta' || p == 'run')) a.sfx('motor_stop');
          if (m == 'single') {
            a.sfx('motor_strain');
            _toast(sim?.byId(e.id ?? '')?.type == 'motor1'
                ? 'المحرك ${e.id} يطنّ ولا يدور: ملف التقويم (المكثف) Z1-Z2 غير موصّل.'
                : 'فقد فاز: المحرك ${e.id} يطنّ ولا يدور.');
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
        case 'sup':
          if (p.p['sw'] == true) {
            AudioService.instance.sfx('estop_latch');
            l.actuate(p.id, 'mcb');
            _toast(l[p.id].s.on ? 'مفتاح العزل ${p.id} على وضع التشغيل I.' : 'مفتاح العزل ${p.id} على وضع الفصل 0.');
          }
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
        case 'motor1':
          l.actuate(p.id, 'load');
          _toast(l[p.id].s.load ? 'تم تحميل المحرك بحمل زائد.' : 'رُفع الحمل الزائد عن المحرك.');
        case 'mach':
          final pl = l.plants[p.id];
          if (pl != null) pl.tap(0.25, 0.5); // put a part / box on the machine
          if (p.p['kind'] == 'tank') {
            l.actuate(p.id, 'valve');
            _toast(l[p.id].s.valve ? 'فُتح محبس التصريف: الخزان يفرغ.' : 'أُغلق محبس التصريف.');
          }
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
            if (p.p['burnt'] == true) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: panelBox(color: const Color(0xFF2A0E14), border: CC.red, radius: 14),
                child: const Text('هذا المكوّن محترق ولن يعمل. ابحث عن سبب الحريق في التوصيل أو في جهد الملف قبل الاستبدال.',
                    style: TextStyle(height: 1.6)),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _replace(p);
                },
                icon: const Icon(Icons.build_rounded),
                label: const Text('استبدال بمكوّن جديد'),
              ),
              const SizedBox(height: 14),
            ],
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
            if (e == 'mach' && p.p['kind'] != 'press') ...[
              const Text('المحرك الذي يقود الآلة', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in doc.parts.where((q) => q.d.engine == 'motor' || q.d.engine == 'motor1'))
                  ChoiceChip(label: Text(m.id, textDirection: TextDirection.ltr), selected: p.p['motor'] == m.id, onSelected: (_) => upd('motor', m.id)),
              ]),
              if (!doc.parts.any((q) => q.d.engine == 'motor' || q.d.engine == 'motor1'))
                const Text('أضف محركًا من المكتبة أولًا.', style: TextStyle(color: CC.muted)),
            ],
            if (e == 'mach') ...[
              const SizedBox(height: 10),
              Text(
                  switch (p.p['kind']) {
                    'sort' =>
                      'المحرك بيدوّر السير وعليه كراتين معدن وبلاستيك. B1 فوتوسل آخر السير، B2 حساس حثي بيشوف المعدن قدام البستم، B3 البستم راجع، B4 البستم طالع. ملف صمام البستم Y1 على A1-A2 (230 فولت). اضغط على الماكينة وهي شغالة عشان تحط كرتونة.',
                    'press' =>
                      'ملف الصمام Y1 على A1-A2 (230 فولت) بينزّل الذراع، ولما يتفصل الياي بيرجّعها. B1 الذراع فوق، B2 الذراع تحت، B3 فوتوسل القطعة موجودة. اضغط على المكبس وهو شغال عشان تحط قطعة.',
                    'fill' =>
                      'المحرك بيدوّر السير وعليه زجاجات فاضية. B1 فوتوسل الزجاجة تحت البزبوز، B2 حساس إن الزجاجة اتملت، وصمام التعبئة Y1 على A1-A2 (230 فولت).',
                    'tank' => 'الطلمبة تملأ الخزان والمحبس يفرّغه. العوامة S1 تعمل عند 20% والعوامة S2 عند 85%. اضغط على الخزان أثناء التشغيل لفتح المحبس أو غلقه.',
                    'lift' => 'المصعد يتحرك بين ثلاثة أدوار، وفي كل دور مفتاح يعمل عند وصول الكابينة. اتجاه دوران المحرك يحدد الصعود أو النزول.',
                    'hoist' => 'الونش يرفع وينزل الحمل. S1 مفتاح الحد الأسفل وS2 مفتاح الحد الأعلى.',
                    _ => 'العربة تتحرك يمينًا ويسارًا حسب اتجاه دوران المحرك. S1 عند النهاية اليسرى وS2 عند النهاية اليمنى.',
                  },
                  style: const TextStyle(color: CC.muted, height: 1.6)),
              if (p.p['kind'] == 'sort' || p.p['kind'] == 'press' || p.p['kind'] == 'fill') ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _view3d = p.id);
                  },
                  icon: const Icon(Icons.view_in_ar_rounded),
                  label: const Text('شوف الماكينة مجسمة 3D وهي شغالة'),
                ),
              ],
            ],
            if (e == 'motor1') ...[
              Text('التيار الاسمي: ${((p.p['In'] ?? 4.0) as num).toStringAsFixed(1)} أمبير', style: const TextStyle(color: CC.text2)),
              Slider(min: 1, max: 12, divisions: 22, value: ((p.p['In'] ?? 4.0) as num).toDouble(), onChanged: (v) => upd('In', v)),
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
                  max: doc.plateW,
                  value: p.len.clamp(60.0, doc.plateW).toDouble(),
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
              leading: const Icon(Icons.save_outlined, color: CC.accentSoft),
              title: const Text('حفظ وفتح المشاريع'),
              subtitle: const Text('احفظ ورقة العمل باسم وارجع لها في أي وقت', style: TextStyle(color: CC.muted)),
              onTap: () {
                Navigator.pop(ctx);
                showProjectsSheet(context, kind: 'panel', suggestedName: 'لوحة ${DateTime.now().day}/${DateTime.now().month}', current: doc.toJsonString, onOpen: (j, n) {
                  if (running) _power();
                  _snapshot();
                  doc = LabDoc.fromJsonString(j);
                  fault = null;
                  _changed();
                  _fit();
                });
              }),
          ListTile(
              leading: const CcIcon(CcIcons.lab, color: CC.accentSoft),
              title: const Text('مثال محلول: تشغيل مباشر DOL'),
              subtitle: const Text('لوحة كاملة موصّلة للمقارنة والتجربة', style: TextStyle(color: CC.muted)),
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
              title: const Text('ورقة عمل جديدة فارغة'),
              subtitle: const Text('لوحة تركيب بقضيبي أوميجا، وكل التوصيل عليك', style: TextStyle(color: CC.muted)),
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
            child: RepaintBoundary(child: CustomPaint(painter: _DotGrid(tc.value))),
          ),
        ),
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: tc,
            constrained: false,
            minScale: 0.08,
            maxScale: 6,
            panEnabled: dragId == null && _wireFrom == null,
            scaleEnabled: dragId == null && _wireFrom == null,
            boundaryMargin: const EdgeInsets.all(2400),
            onInteractionUpdate: (_) => setState(() {}),
            child: SizedBox(
              width: doc.totalW * kPx,
              height: doc.plateH * kPx,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: RepaintBoundary(child: CustomPaint(isComplex: true, painter: PlatePainter(doc, selPart)))),
                for (final p in _drawOrder())
                  if (!p.structural) _partWidget(p),
                if (doc.mech.isNotEmpty) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: InterlockPainter(doc)))),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: WirePainter(
                        doc: doc,
                        selectedWire: selWire,
                        nets: sim?.nets,
                        phase: _phase,
                        pending: pending,
                        flows: flows,
                        flash: flash,
                        drag: (_wireFrom != null && _wireTo != null && doc.termPos(_wireFrom!) != null)
                            ? (doc.termPos(_wireFrom!)!, _wireTo!, doc.termUp(_wireFrom!))
                            : null,
                        dragColor: color == 'auto' && _wireFrom != null ? _autoColor(_wireFrom!, _termAt(_wireTo ?? Offset.zero) ?? _wireFrom!) : (color == 'auto' ? 'rd' : color),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(
                            painter: TermPainter(doc, pending ?? _wireFrom, !running && !meter, _hiddenTerms(), probeRed: probeRed, probeBlack: probeBlack)))),
                if (fx.isNotEmpty) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: FxPainter(fx, _clock)))),
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
        if (_view3d != null) _machine3d(context),
      ]),
    );
  }

  /// a floating window with the machine in 3D, moving with the panel's circuit
  Widget _machine3d(BuildContext context) {
    final id = _view3d!;
    final p = doc.byId(id);
    final kind = p?.d.machine;
    if (p == null || kind == null || !kLabPlants.contains(kind)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _view3d = null);
      });
      return const SizedBox.shrink();
    }
    final pl = sim?.plants[id] ?? (_idlePlants[id] ??= plantByKey(kind)!.make());
    final mq = MediaQuery.of(context);
    final sz = mq.size;
    final w = math.min(420.0, sz.width - 24), h = w * 0.62;
    final p0 = _view3dPos ?? Offset(sz.width - w - 12, mq.padding.top + 70);
    final pos = Offset(p0.dx.clamp(0.0, math.max(0.0, sz.width - w)).toDouble(), p0.dy.clamp(0.0, math.max(0.0, sz.height - h - 60)).toDouble());
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: w,
      child: Glass(
        radius: 20,
        tint: const Color(0xEE0A1228),
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (e) => setState(() => _view3dPos = pos + e.delta),
            child: Row(children: [
              const Icon(Icons.drag_indicator_rounded, size: 18, color: CC.muted),
              const SizedBox(width: 4),
              Expanded(child: Text('${p.id} · ${plantByKey(kind)!.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                  tooltip: 'اقفل', visualDensity: VisualDensity.compact, onPressed: () => setState(() => _view3d = null), icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
          SizedBox(
            height: h,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _web3d
                    ? Machine3D(plant: pl, io: sim?.machIo(id), frame: _frame3d)
                    : CustomPaint(painter: machineFlatPainter(pl, sim?.machIo(id), _frame3d), size: Size(w - 20, h))),
          ),
          const SizedBox(height: 6),
          Text(running ? 'الماكينة شغالة مع دايرة اللوحة' : 'شغّل التغذية عشان الماكينة تتحرك مع دايرتك',
              style: TextStyle(color: running ? CC.green : CC.muted, fontSize: 12.5)),
          if (pl.count.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final e in pl.count.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x223D8BFF), borderRadius: BorderRadius.circular(10)),
                    child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  /// the 3D page runs on the platforms with a web view (Android, Windows)
  static final bool _web3d = !kIsWeb && (Platform.isAndroid || Platform.isWindows);
  String? _view3d;
  Offset? _view3dPos;
  int get _frame3d => (_clock * Perf.simFps).round();

  Widget _partWidget(Placed p) {
    final sel = p.id == selPart || p.id == dragId;
    final sz = p.size;
    final c = sim?.byId(p.id);
    final children = <Widget>[];
    final mk = p.d.machine;
    if (mk != null) {
      children.add(Positioned.fill(
          child: CustomPaint(
              painter: MachinePainter(mk,
                  x: c?.s.mx ?? (mk == 'cart' ? 0.5 : (mk == 'tank' ? 0.1 : 0.0)),
                  sw: c?.s.ms ?? const [false, false, false, false],
                  plant: kLabPlants.contains(mk) ? (sim?.plants[p.id] ?? (_idlePlants[p.id] ??= plantByKey(mk)!.make())) : null,
                  io: sim?.machIo(p.id),
                  coil: c != null && c.s.v > 230 * 0.6,
                  sprite: MachineSprites.of(mk),
                  run: () {
                    final m = c == null ? null : sim?.byId((p.p['motor'] as String?) ?? '');
                    return m != null && m.s.spd > 0.05 && (m.s.mode == 'star' || m.s.mode == 'delta' || m.s.mode == 'run');
                  }(),
                  valve: c?.s.valve ?? true,
                  motor: (p.p['motor'] as String?) ?? '',
                  phase: _phase))));
    } else if (p.d.side.isNotEmpty) {
      final lw = kLug * kPx;
      children
        ..add(Positioned.fill(child: CustomPaint(painter: SideLugPainter([p.d.printed(p.d.side[0]), p.d.printed(p.d.side[1])]))))
        ..add(Positioned(
            left: lw,
            right: lw,
            top: 0,
            bottom: 0,
            child: () {
              final img = Image.asset(p.d.info?.asset ?? '', fit: BoxFit.contain, filterQuality: FilterQuality.medium);
              // a blue pilot lamp: the green lens with green and blue swapped
              if (p.d.engine == 'lamp' && p.p['col'] == 'b') {
                return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0]), child: img);
              }
              return img;
            }()));
    } else if (p.d.engine == 'motor' || p.d.engine == 'motor1') {
      children
        ..add(Positioned.fill(child: CustomPaint(painter: MotorPlatePainter((p.p['links'] ?? 'none') as String, single: p.d.engine == 'motor1'))))
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
    if (p.p['burnt'] == true) children.addAll(_burntOverlay(p));
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
    if (_snapHost?.id == p.id) {
      children.add(Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: CC.green, width: 3),
              borderRadius: BorderRadius.circular(6),
              boxShadow: glow(CC.green, 1.0),
            ),
          ),
        ),
      ));
    }
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

  /// scorch marks and a red tag on a burnt part
  List<Widget> _burntOverlay(Placed p) => [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3 * kPx),
              gradient: RadialGradient(
                center: const Alignment(0, -0.35),
                radius: 0.9,
                colors: [const Color(0xE6120D0A), const Color(0x99201610), const Color(0x00201610)],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: -11 * kPx,
          left: -20 * kPx,
          right: -20 * kPx,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 2.6 * kPx, vertical: 0.3 * kPx),
              decoration: BoxDecoration(color: CC.red, borderRadius: BorderRadius.circular(3 * kPx), boxShadow: glow(CC.red, 0.8)),
              child: Text('محترق', style: TextStyle(fontSize: 5.4 * kPx, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
            ),
          ),
        ),
      ];

  List<Widget> _liveOverlay(Placed p, Comp c) {
    final sz = p.size;
    if (p.p['burnt'] == true && !p.d.engine.startsWith('motor')) return const [];
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
      case 'sup':
        if (p.p['sw'] != true) return const [];
        return [badge(c.s.on ? 'I · ON' : 'O · OFF', c.s.on ? const Color(0xFF1FA463) : const Color(0xFF59657A))];
      case 'lamp':
        final lit = c.s.v > (c.num_('V') * 0.6) && !c.s.dead && c.s.fault != 'lamp_dead';
        if (!lit) return const [];
        if (p.p['snd'] == 'siren') {
          final on = (_phase * 6) % 1 < 0.5;
          return [
            Positioned(
                left: -14 * kPx,
                right: -14 * kPx,
                top: -14 * kPx,
                bottom: -14 * kPx,
                child: IgnorePointer(child: CustomPaint(painter: SirenPainter(_phase)))),
            Positioned(
              left: kLug * kPx,
              right: kLug * kPx,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF3B30).withValues(alpha: on ? 0.45 : 0.1),
                    boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: on ? 0.9 : 0.2), blurRadius: 50, spreadRadius: 8)],
                  ),
                ),
              ),
            ),
          ];
        }
        final col = switch (p.p['col'] ?? p.d.params['col']) {
          'r' => const Color(0xFFFF3B30),
          'y' => const Color(0xFFFFC21A),
          'b' => const Color(0xFF3D8BFF),
          _ => const Color(0xFF2FE07A)
        };
        // face-on lens in the middle between the two lugs
        final lens = (sz.width - 2 * kLug) * 0.62 * kPx;
        return [
          Positioned(
            left: (sz.width * kPx - lens) / 2,
            top: (sz.height * kPx - lens) / 2,
            width: lens,
            height: lens,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.95), col, col.withValues(alpha: 0.85)], stops: const [0, 0.45, 1]),
                  boxShadow: [BoxShadow(color: col.withValues(alpha: 0.85), blurRadius: 60, spreadRadius: 12), BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 16)],
                ),
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
        final cap = (sz.width - 2 * kLug) * 0.7 * kPx;
        return [
          Positioned(
              left: (sz.width * kPx - cap) / 2,
              top: (sz.height * kPx - cap) / 2,
              width: cap,
              height: cap,
              child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.35), border: Border.all(color: CC.amber, width: 0.8 * kPx))),
              )),
          badge('مضغوط', CC.amber),
        ];
      case 'motor':
      case 'motor1':
        final run = c.s.mode == 'star' || c.s.mode == 'delta' || c.s.mode == 'run';
        final spin = run || c.s.spd > 0.02
            ? [
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(painter: MotorRunPainter(c.s.ang, c.s.dir == 0 ? 1 : c.s.dir, c.s.spd, const Offset(8, 122))))),
              ]
            : const <Widget>[];
        final mode = {
              'off': 'STOPPED',
              'star': 'RUN · STAR',
              'delta': 'RUN · DELTA',
              'run': 'RUN',
              'single': c.type == 'motor1' ? 'HUM · NO START' : 'PHASE LOSS',
              'over': 'OVERVOLT',
              'dead': 'BURNT'
            }[c.s.mode] ??
            c.s.mode;
        final bad = c.s.mode == 'single' || c.s.mode == 'over' || c.s.mode == 'dead';
        return [
          ...spin,
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
                            ? (flash.isNotEmpty ? 'قصر كهربائي! افصل التغذية وصحّح التوصيل' : 'اللوحة تعمل · الشرطات المضيئة في الأسلاك هي مسار التيار')
                            : _wireFrom != null
                                ? 'اسحب إلى الطرف الآخر ثم اترك…'
                                : ex != null
                                    ? 'تمرين: وصّل حسب المخطط، ثم افحص التوصيل وشغّل'
                                    : 'ورقة العمل · أضف المكونات من المكتبة، واسحب من طرف إلى طرف لتوصيل سلك',
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
      if (ex != null) _schemPanel(top, bottom),
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
                if (ex != null) _tool(Icons.schema_outlined, 'المخطط والمهام', () => setState(() => schemOpen = !schemOpen), active: schemOpen),
                if (ex != null) _tool(Icons.fact_check_outlined, 'فحص التوصيل', _checkWiring),
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
      thumb = const Icon(Icons.horizontal_rule_rounded, color: CC.text2);
    } else if (d.machine != null) {
      final f = d.frame;
      thumb = FittedBox(child: SizedBox(width: f.width * kPx, height: f.height * kPx, child: CustomPaint(painter: MachinePainter(d.machine!, sprite: MachineSprites.of(d.machine!)))));
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
  _DotGrid(this.m) : _key = Object.hashAll(m.storage);
  final int _key; // the view's pan and zoom when this was made
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
  bool shouldRepaint(covariant _DotGrid old) => old._key != _key;
}
