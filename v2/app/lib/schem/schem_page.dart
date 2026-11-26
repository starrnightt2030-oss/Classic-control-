// «محاكي الدوائر الخطية» — draw an IEC schematic from the symbol library, wire it
// pin to pin, and simulate it with the same engine as the panel lab.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lab/projects.dart';
import '../services/audio_service.dart';
import '../sim/engine.dart';
import '../sim/measure.dart';
import '../lab/machine_sprites.dart';
import '../sim/plant.dart';
import '../ui/perf.dart';
import '../ui/theme.dart';
import 'diagnose.dart';
import 'export.dart';
import 'machine3d.dart';
import 'ladder.dart';
import 'meters_ui.dart';
import 'model.dart';
import 'plant_io.dart';
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

  /// open this machine next to the drawing (a key of kPlants)
  final String? plant;
  const SchemPage({super.key, this.deliver, this.demo = 0, this.initial, this.plant});
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

  // instruments
  MeterKind? meter;
  String meterMode = 'vac';
  String? probeRed, probeBlack; // pin keys
  int? clampWire; // document wire index
  int nextProbe = 0;
  Offset meterPos = const Offset(12, 120);
  bool _beeping = false;

  // fault diagnosis
  List<SFault>? faults;
  int _diagCount = 1, _wrong = 0, _hints = 0;
  final Stopwatch _diagClock = Stopwatch();
  Timer? _diagTimer;
  bool _diagBusy = false;
  bool get diagnosing => faults != null;

  // the machine the drawing drives
  PlantDef? plantDef;
  Plant? plant;
  SchemPlantIo? _pio;
  Offset? plantPos;
  int _frame = 0;

  /// the machine in 3D (WebView) or the drawn 2D scene; 3D where the WebView runs
  bool _plant3d = !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  // running sounds: valves that are energised, machine counters already heard
  final Set<String> _valvesOn = {};
  final Map<String, int> _heard = {};
  Plant? _heardOf;
  double _sndAt = 0;

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
    plantDef = plantByKey(widget.plant);
    plant = plantDef?.make();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    AudioService.instance.stopLoops();
    _save?.cancel();
    _diagTimer?.cancel();
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
    if (diagnosing) {
      _toast('إنت في تشخيص الأعطال: الرسم مقفول. دوّر على العطل واستخدم زرار الإصلاح، أو أنهي التشخيص من زرار الأعطال.');
      return false;
    }
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
  bool get _needsProbes => meter == MeterKind.dmm || meter == MeterKind.watt || (meter == MeterKind.clamp && meterMode == 'vac');
  bool get _needsClamp => meter == MeterKind.watt || (meter == MeterKind.clamp && meterMode == 'aac');

  /// a tap while an instrument is out places its probes or its clamp; true when used
  bool _meterTap(Offset g) {
    if (meter == null) return false;
    if (_needsProbes) {
      final pn = _pinAt(g);
      if (pn != null) {
        setState(() {
          if (nextProbe == 0) {
            probeRed = pn;
          } else {
            probeBlack = pn;
          }
          if (probeRed == null) {
            nextProbe = 0;
          } else if (probeBlack == null) {
            nextProbe = 1;
          } else {
            nextProbe = 1 - nextProbe;
          }
        });
        AudioService.instance.sfx('ui_tap');
        _beepCheck();
        return true;
      }
    }
    if (_needsClamp) {
      final w = _wireAt(g);
      if (w != null) {
        setState(() => clampWire = w);
        AudioService.instance.sfx('relay_click', volume: 0.5);
        return true;
      }
    }
    return false;
  }

  void _down(PointerDownEvent e) {
    final g = e.localPosition / kG;
    if (_meterTap(g)) return;
    if (running) {
      final s = _symAt(g);
      if (s != null) _actuate(s, e.pointer, true);
      return;
    }
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downG = g;
    _moved = false;
    if (diagnosing) return; // selection only (on release)
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
    final pn = diagnosing ? null : _pinAt(g);
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
    if (diagnosing) return;
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

  // ------------------------------------------------------------ fault diagnosis
  void _diagMenu() {
    if (diagnosing) {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
              title: Text('تشخيص الأعطال شغال', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('شغّل المحاكاة ولاحظ إيه اللي مش طبيعي، وقيس بالأفوميتر والكلامب. بعدين أوقف المحاكاة، واختار المكوّن أو السلك العطلان، ودوس إصلاح.',
                  style: TextStyle(color: CC.muted, height: 1.5)),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: CC.red),
              title: const Text('استسلام وعرض الأعطال'),
              onTap: () {
                Navigator.pop(ctx);
                _finishDiag(gaveUp: true);
              },
            ),
          ]),
        ),
      );
      return;
    }
    var count = _diagCount;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('تشخيص الأعطال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('التطبيق هيحط أعطال مخفية في الدائرة اللي رسمتها: سلك مقطوع، ملف مفتوح، تلامس محروق أو ملحوم، ضاغط بايظ، فاز ناقص… مهمتك تكتشفها بالملاحظة والقياس وتصلّحها.',
                  style: TextStyle(color: CC.muted, height: 1.6)),
              const SizedBox(height: 14),
              const Text('المستوى', style: TextStyle(color: CC.text2)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final (n, t) in [(1, 'سهل: عطل واحد'), (2, 'متوسط: عطلين'), (3, 'صعب: 3 أعطال')])
                  ChoiceChip(label: Text(t), selected: count == n, onSelected: (_) => set(() => count = n)),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _startDiag(count);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('ابدأ'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _startDiag(int count) async {
    if (_diagBusy) return;
    if (running) _simulate();
    final why = readyForFaults(doc);
    if (why != null) {
      _toast('خلّص الدائرة وجرّبها الأول: $why');
      return;
    }
    _diagBusy = true;
    _toast('بجهّز الأعطال…');
    List<SFault> fs;
    try {
      fs = await pickFaultsAsync(doc, count);
    } catch (_) {
      fs = pickFaults(doc, count);
    }
    _diagBusy = false;
    if (!mounted) return;
    if (fs.isEmpty) {
      _toast('الدائرة صغيرة قوي ومفيهاش مكان لعطل يبان. كبّرها شوية وجرّب تاني.');
      return;
    }
    _diagCount = count;
    setState(() {
      faults = fs;
      _wrong = 0;
      _hints = 0;
      sel = null;
      selWire = null;
      pending = null;
    });
    _diagClock
      ..reset()
      ..start();
    _diagTimer?.cancel();
    _diagTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    AudioService.instance.sfx('stage_sting');
    _toast(fs.length == 1 ? 'اتحط عطل واحد مخفي. شغّل المحاكاة وابدأ التشخيص.' : 'اتحط ${fs.length} أعطال مخفية. شغّل المحاكاة وابدأ التشخيص.');
  }

  void _repair() {
    final fs = faults;
    if (fs == null) return;
    if (running) {
      _toast('أمان الأول: أوقف المحاكاة (افصل التغذية) قبل ما تصلّح.');
      AudioService.instance.sfx('warning_alert');
      return;
    }
    final s = sel == null ? null : doc.byId(sel!);
    final w = selWire;
    SFault? found;
    for (final f in fs) {
      if (!f.fixed && f.hit(doc, s: s, wire: w)) {
        found = f;
        break;
      }
    }
    if (found == null) {
      setState(() => _wrong++);
      AudioService.instance.sfx('error_buzz');
      _toast(w != null ? 'السلك ده سليم. قيس قبل ما تغيّر حاجة.' : 'المكوّن ده سليم. قيس قبل ما تغيّر حاجة.');
      return;
    }
    final f = found;
    setState(() => f.fixed = true);
    AudioService.instance.sfx('success_chime');
    final k = sFaultKind(f.kind);
    final left = fs.where((x) => !x.fixed).length;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: CC.green, size: 40),
        title: Text('صح! ${k.nameAr}'),
        content: Text('في ${f.where(doc)}.\n\n${k.lesson}', style: const TextStyle(height: 1.6)),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (left == 0) _finishDiag();
            },
            child: Text(left == 0 ? 'النتيجة' : 'كمّل (فاضل $left)'),
          ),
        ],
      ),
    );
  }

  void _hint() {
    final f = faults?.firstWhere((f) => !f.fixed, orElse: () => faults!.first);
    if (f == null) return;
    setState(() => _hints++);
    final k = sFaultKind(f.kind);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lightbulb_rounded, color: CC.amber, size: 36),
        title: const Text('تلميح'),
        content: Text(k.hint, style: const TextStyle(height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
      ),
    );
  }

  Future<void> _finishDiag({bool gaveUp = false}) async {
    final fs = faults;
    if (fs == null) return;
    _diagClock.stop();
    _diagTimer?.cancel();
    if (running) _simulate();
    final secs = _diagClock.elapsed.inSeconds.toDouble();
    final (score, stars) = faultScore(faults: fs.length, wrong: _wrong, hints: _hints, seconds: secs, gaveUp: gaveUp);
    AudioService.instance.sfx(gaveUp ? 'soft_fail' : (stars == 3 ? 'success_fanfare' : 'success_chime'));
    try {
      final prefs = await SharedPreferences.getInstance();
      final h = prefs.getStringList('schem_fault_history_v1') ?? [];
      h.add('${DateTime.now().toIso8601String()}|${doc.title}|${fs.length}|$score|${secs.round()}');
      await prefs.setStringList('schem_fault_history_v1', h.length > 50 ? h.sublist(h.length - 50) : h);
    } catch (_) {}
    if (!mounted) return;
    final wrong = _wrong, hints = _hints;
    setState(() => faults = null);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gaveUp ? 'الأعطال كانت هنا' : 'خلّصت التشخيص!'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++) Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, color: CC.amber, size: 38),
            ]),
            Text('$score / 100', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('الوقت ${(secs ~/ 60)}:${(secs.round() % 60).toString().padLeft(2, '0')} · محاولات غلط $wrong · تلميحات $hints',
                textAlign: TextAlign.center, style: const TextStyle(color: CC.muted)),
            const SizedBox(height: 12),
            for (final f in fs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(f.fixed ? Icons.check_circle_rounded : Icons.cancel_rounded, color: f.fixed ? CC.green : CC.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${sFaultKind(f.kind).nameAr}: ${f.where(doc)}\n${sFaultKind(f.kind).lesson}', style: const TextStyle(height: 1.5, fontSize: 13)),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('خلاص')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startDiag(_diagCount);
            },
            child: const Text('أعطال جديدة'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- machines
  List<String> _missingTags(PlantDef d) => [
        for (final t in d.tags)
          if (!t.extra && !doc.syms.any((s) => s.tag == t.tag)) t.tag
      ];

  void _pickPlant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('الماكينات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('الماكينة بتتربط بالرسم بأسماء الأجهزة (M1 وY1 وB1…). شغّل المحاكاة والماكينة هتتحرك بدايرتك، وحساساتها هتحس لوحدها.', style: TextStyle(color: CC.muted, height: 1.5)),
            ),
            for (final d in kPlants)
              ListTile(
                leading: Icon(Icons.precision_manufacturing_rounded, color: plantDef?.key == d.key ? CC.amber : CC.accentSoft),
                title: Text(d.title),
                subtitle: Text(d.desc, style: const TextStyle(color: CC.muted, height: 1.4)),
                selected: plantDef?.key == d.key,
                trailing: IconButton(
                  tooltip: 'افتح الدايرة الجاهزة',
                  icon: const Icon(Icons.description_outlined),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _loadReadyFor(d);
                  },
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _setPlant(d);
                },
              ),
            if (plant != null)
              ListTile(
                leading: const Icon(Icons.close_rounded, color: CC.muted),
                title: const Text('اقفل الماكينة'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    plant = null;
                    plantDef = null;
                    _pio = null;
                  });
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _setPlant(PlantDef d) {
    final s = sim;
    setState(() {
      plantDef = d;
      plant = d.make();
      _pio = s == null ? null : SchemPlantIo(doc, s);
    });
    AudioService.instance.sfx('part_select');
    final miss = _missingTags(d);
    if (miss.isNotEmpty) _toast('سمّي الأجهزة في رسمك: ${miss.join('، ')}، أو افتح الدايرة الجاهزة للماكينة دي.');
  }

  /// replace the sheet with the machine's ready-made circuit (undoable)
  void _loadReadyFor(PlantDef d) {
    final r = readyById(d.ready);
    if (r == null || !_editable()) return;
    if (running) _simulate();
    _snapshot();
    setState(() {
      doc = r.build();
      sel = null;
      selWire = null;
    });
    _changed();
    _setPlant(d);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  void _plantTask(PlantDef d) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.desc, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 12),
            const Text('المطلوب', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(d.task, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 12),
            const Text('أسماء الأجهزة', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final t in d.tags)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${t.tag}: ${t.nameAr}${t.extra ? ' (اختياري)' : ''}', style: const TextStyle(color: CC.text2)),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
      ),
    );
  }

  Widget _plantPanel(BuildContext context) {
    final d = plantDef!, pl = plant!;
    final mq = MediaQuery.of(context);
    final sz = mq.size;
    final w = math.min(340.0, sz.width - 24), h = w * 0.62;
    final p0 = plantPos ?? Offset(sz.width - w - 12, mq.padding.top + 70);
    final pos = Offset(p0.dx.clamp(0.0, math.max(0.0, sz.width - w)).toDouble(), p0.dy.clamp(0.0, math.max(0.0, sz.height - h - 90)).toDouble());
    final miss = _missingTags(d);
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
            onPanUpdate: (e) => setState(() => plantPos = pos + e.delta),
            child: Row(children: [
              const Icon(Icons.drag_indicator_rounded, size: 18, color: CC.muted),
              const SizedBox(width: 4),
              Expanded(child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                  tooltip: _plant3d ? 'رسم مبسط' : 'مجسم ثلاثي الأبعاد',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _plant3d = !_plant3d),
                  icon: Icon(_plant3d ? Icons.grid_view_rounded : Icons.view_in_ar_rounded, size: 20)),
              IconButton(tooltip: 'المطلوب', visualDensity: VisualDensity.compact, onPressed: () => _plantTask(d), icon: const Icon(Icons.info_outline_rounded, size: 20)),
              IconButton(
                  tooltip: 'رجّع الماكينة لأولها', visualDensity: VisualDensity.compact, onPressed: () => setState(() => plant = d.make()), icon: const Icon(Icons.restart_alt_rounded, size: 20)),
              IconButton(
                  tooltip: 'اقفل',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                        plant = null;
                        plantDef = null;
                        _pio = null;
                      }),
                  icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
          SizedBox(
            height: h,
            child: _plant3d
                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Machine3D(plant: pl, io: _pio, frame: _frame))
                : GestureDetector(
              onTapUp: (e) => setState(() => pl.tap(e.localPosition.dx / w, e.localPosition.dy / h)),
              child: CustomPaint(painter: machineFlatPainter(pl, _pio, _frame), size: Size(w - 20, h)),
            ),
          ),
          const SizedBox(height: 6),
          if (miss.isNotEmpty)
            Text('ناقص في الرسم: ${miss.join('، ')}', style: const TextStyle(color: CC.red, fontSize: 12.5))
          else if (!running)
            const Text('شغّل المحاكاة عشان الماكينة تتحرك مع دايرتك', style: TextStyle(color: CC.muted, fontSize: 12.5))
          else if (pl.count.isEmpty)
            const Text('الماكينة شغالة مع دايرتك', style: TextStyle(color: CC.green, fontSize: 12.5)),
          if (pl.count.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final e in pl.count.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0x223D8BFF), borderRadius: BorderRadius.circular(10)),
                  child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                ),
            ]),
        ]),
      ),
    );
  }

  void _pickMeter() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(alignment: AlignmentDirectional.centerStart, child: Text('أجهزة القياس', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ),
          for (final (k, icon, sub) in [
            (MeterKind.dmm, Icons.electric_meter_outlined, 'جهد متردد ومستمر، مقاومة، واستمرارية بصوت. حط المجس الأحمر والأسود على أي طرفين.'),
            (MeterKind.clamp, Icons.radio_button_unchecked_rounded, 'اقفل الفك على أي سلك واقرا التيار وإنت شغّال، من غير ما تفك حاجة.'),
            (MeterKind.watt, Icons.speed_rounded, 'ملف التيار على السلك وملف الجهد على طرفين: بيقرا القدرة الفعالة ومعامل القدرة.'),
          ])
            ListTile(
              leading: Icon(icon, color: meter == k ? CC.amber : CC.accentSoft),
              title: Text(kMeterNames[k]!),
              subtitle: Text(sub, style: const TextStyle(color: CC.muted, height: 1.4)),
              selected: meter == k,
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  meter = k;
                  meterMode = kMeterModes[k]!.first.$1;
                  probeRed = probeBlack = null;
                  clampWire = null;
                  nextProbe = 0;
                  pending = null;
                });
                AudioService.instance.sfx('part_select');
              },
            ),
          if (meter != null)
            ListTile(
              leading: const Icon(Icons.close_rounded, color: CC.muted),
              title: const Text('رجّع الجهاز'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => meter = null);
              },
            ),
        ]),
      ),
    );
  }

  Widget _meterPanel(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    final pos = Offset(meterPos.dx.clamp(0.0, math.max(0.0, sz.width - 270)).toDouble(), meterPos.dy.clamp(0.0, math.max(0.0, sz.height - 200)).toDouble());
    String where(String? pin) {
      if (pin == null) return '';
      final i = pin.indexOf('.');
      final s = doc.byId(pin.substring(0, i));
      final pn = s?.pin(pin.substring(i + 1));
      if (s == null || pn == null) return '';
      return '${s.tag} : ${pn.label.isEmpty ? pn.id : pn.label}';
    }

    final cw = clampWire;
    final clampTxt = cw != null && cw < doc.wires.length ? 'سلك رقم ${doc.wireNumbers()[cw]}' : '';
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => meterPos = pos + d.delta),
        child: MeterPanel(
          kind: meter!,
          mode: meterMode,
          reading: _reading(),
          red: where(probeRed),
          black: where(probeBlack),
          clamp: clampTxt,
          needsProbes: _needsProbes,
          needsClamp: _needsClamp,
          nextProbe: nextProbe,
          onMode: (m) {
            setState(() => meterMode = m);
            AudioService.instance.sfx('selector_detent', volume: 0.6);
            _beepCheck();
          },
          onPickProbe: (i) => setState(() => nextProbe = i),
          onClose: () => setState(() => meter = null),
          onClear: () => setState(() {
            probeRed = probeBlack = null;
            clampWire = null;
            nextProbe = 0;
          }),
        ),
      ),
    );
  }

  /// continuity mode: beep while the probes touch a closed path
  void _beepCheck() {
    if (meter != MeterKind.dmm || meterMode != 'beep') {
      _beeping = false;
      return;
    }
    final r = _reading();
    final on = r.value != 'OL' && r.value != '----' && !r.warn && (double.tryParse(r.value) ?? 1e9) < 30 && r.unit == 'Ω';
    if (on && !_beeping) AudioService.instance.sfx('meter_beep');
    _beeping = on;
  }

  MeterReading _reading() {
    final kind = meter;
    if (kind == null) return MeterReading.idle;
    // switched off: the drawing as it stands (with its hidden faults), no supply
    final s = sim ?? (diagnosing ? buildFaulted(doc, faults!) : doc.toSim());
    final l = s.lab;
    final ta = probeRed == null ? null : s.pinToTerm[probeRed!];
    final tb = probeBlack == null ? null : s.pinToTerm[probeBlack!];
    Cx? amps() {
      final cw = clampWire;
      if (cw == null || cw >= doc.wires.length) return null;
      int? eng;
      for (final e in s.wireIndex.entries) {
        if (e.value == cw) eng = e.key;
      }
      if (eng == null) return Cx.zero;
      return l.wireCurrents()[eng] ?? Cx.zero;
    }

    final pa = ta == null ? null : l.potential(ta), pb = tb == null ? null : l.potential(tb);
    final mode = meterMode;
    if (kind == MeterKind.watt) {
      final i = amps();
      if (i == null || ta == null || tb == null) return const MeterReading('----', 'W', note: 'اقفل ملف التيار على سلك، وحط مجسات الجهد على طرفين', needle: 0, scale: '');
      final v = (pa != null && pb != null && pa.$2 == pb.$2) ? pa.$1 - pb.$1 : Cx.zero;
      final p = v.dotRe(i);
      final sVA = v.abs * i.abs;
      var fs = 10.0;
      for (final f in [10.0, 50, 100, 500, 1000, 2000, 5000, 10000, 20000]) {
        fs = f.toDouble();
        if (p.abs() * 1.1 <= fs) break;
      }
      return MeterReading(p.abs() >= 1000 ? (p.abs() / 1000).toStringAsFixed(2) : p.abs().toStringAsFixed(1), p.abs() >= 1000 ? 'kW' : 'W',
          needle: p.abs() / fs,
          scale: '100 = ${fs >= 1000 ? '${(fs / 1000).toStringAsFixed(0)} kW' : '${fs.toStringAsFixed(0)} W'}',
          note: p < -0.5 ? 'القراءة بالسالب: اعكس اتجاه ملف التيار أو المجسات' : (sVA < 0.01 ? 'مفيش قدرة: يا إما مفيش جهد يا إما مفيش تيار' : ''),
          warn: p < -0.5,
          extra: [('V', v.abs.toStringAsFixed(1)), ('A', i.abs.toStringAsFixed(2)), ('cosφ', sVA < 0.01 ? '-' : (p.abs() / sVA).clamp(0.0, 1.0).toStringAsFixed(2))]);
    }
    if (kind == MeterKind.clamp && mode == 'aac') {
      final i = amps();
      if (i == null) return const MeterReading('----', 'A', note: 'المس أي سلك عشان تقفل الفك عليه');
      return MeterReading(meterDigits(i.abs), 'A', note: sim == null ? 'التغذية مفصولة' : '');
    }
    if (ta == null || tb == null) return MeterReading('----', mode == 'ohm' || mode == 'beep' ? 'Ω' : 'V', note: 'حط المجس الأحمر والأسود على طرفين');
    if (mode == 'ohm' || mode == 'beep') {
      if (pa != null || pb != null) {
        return const MeterReading('----', 'Ω', note: 'افصل التغذية الأول! قياس المقاومة على دائرة فيها جهد بيبوّظ الجهاز', warn: true);
      }
      final r = l.ohms(ta, tb);
      final (v, u) = ohmText(r);
      final cont = r != null && r < 30;
      return MeterReading(v, u, note: mode == 'beep' ? (cont ? 'تيت… فيه استمرارية' : 'مفيش استمرارية') : (r == null ? 'OL: الدائرة مفتوحة بين النقطتين' : ''));
    }
    // voltage
    if (pa == null || pb == null || pa.$2 != pb.$2) {
      return MeterReading(mode == 'vdc' ? '0.00' : '0.0', 'V',
          note: pa == null && pb == null ? 'مفيش جهد على النقطتين' : (pa == null || pb == null ? 'نقطة من الاتنين مش واصلها جهد' : 'النقطتين من مصدرين مختلفين'));
    }
    final dc = pa.$2.startsWith('D:');
    if (mode == 'vac') {
      if (dc) return const MeterReading('0.0', 'V', note: 'الجهد هنا مستمر: حوّل المفتاح على V=', warn: true);
      return MeterReading(meterDigits((pa.$1 - pb.$1).abs), 'V');
    }
    if (!dc) return MeterReading('0.00', 'V', note: (pa.$1 - pb.$1).abs > 1 ? 'الجهد هنا متردد: حوّل المفتاح على V~' : '', warn: (pa.$1 - pb.$1).abs > 1);
    return MeterReading(meterDigits(pa.$1.re - pb.$1.re), 'V');
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
      AudioService.instance.stopLoops();
      setState(() {
        sim = null;
        _pio = null;
        _valvesOn.clear();
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
    final s = diagnosing ? buildFaulted(doc, faults!) : doc.toSim();
    AudioService.instance.sfx('mcb_on');
    s.lab.setPower(true);
    setState(() {
      sim = s;
      pending = null;
      sel = null;
      selWire = null;
    });
    final pl = plant, pd = plantDef;
    if (pl != null && pd != null) {
      pl.resync();
      _pio = SchemPlantIo(doc, s);
    }
    _handle(s.lab.drain());
    flows = _flows();
    final miss = pd == null || pl == null ? const <String>[] : _missingTags(pd);
    if (s.warnings.isNotEmpty) {
      _toast(s.warnings.first);
    } else if (miss.isNotEmpty) {
      _toast('الماكينة محتاجة في الرسم: ${miss.join('، ')}');
    }
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
    final pl = plant, io = _pio;
    if (pl != null && io != null) {
      pl.tick(dt, io);
      _frame++;
    }
    _handle(s.lab.drain());
    _sounds(s);
    // the physics steps every frame; the screen is redrawn at Perf.simFps, which is
    // smooth for this kind of motion and halves the work on big touch screens
    if (_clock - _drawnAt < Perf.simFrame * 0.9) return;
    _drawnAt = _clock;
    flows = _flows();
    setState(() {});
  }

  double _drawnAt = -1;

  /// what the running circuit sounds like: motors, coils, buzzers, horns, air valves,
  /// and the machine (belt, water, the press landing, the lift arriving)
  void _sounds(SchemSim s) {
    final a = AudioService.instance;
    final pl = plant, io = _pio;
    // the machine's moments, heard once each
    if (!identical(_heardOf, pl)) {
      _heard.clear();
      _heardOf = pl;
    }
    if (pl != null) {
      for (final e in pl.count.entries) {
        final was = _heard[e.key] ?? 0;
        if (e.value > was) {
          switch (e.key) {
            case 'قطع اتكبست':
              a.sfx('press_stamp', volume: 0.8);
            case 'وقفات':
              a.sfx('lift_ding', volume: 0.5);
              a.sfx('door_slide', volume: 0.5);
            case 'زجاجات مليانة':
              a.sfx('bottle_clink', volume: 0.6);
            case 'معدن اتفرز' || 'بلاستيك اتفرز غلط':
              a.sfx('box_drop', volume: 0.7);
          }
        }
        _heard[e.key] = e.value;
      }
    }
    // valves click in with an air rush and drop out with an exhaust blast
    final l = s.lab;
    bool lit(SPlaced p) {
      final id = s.compOf[p.id];
      final c = id == null ? null : l.byId(id);
      return c != null && !c.s.dead && c.s.fault != 'lamp_dead' && c.s.v > c.num_('V') * 0.6;
    }

    var buzz = false, horn = false;
    for (final p in doc.syms) {
      switch (p.sym) {
        case 'yv':
          final on = lit(p);
          if (on && _valvesOn.add(p.id)) a.sfx('air_extend', volume: 0.75);
          if (!on && _valvesOn.remove(p.id)) a.sfx('air_exhaust', volume: 0.7);
        case 'bz':
          buzz = buzz || lit(p);
        case 'horn':
          horn = horn || lit(p);
      }
    }
    // loops are updated a few times a second, not every frame
    if (_clock - _sndAt < 0.12) return;
    _sndAt = _clock;
    var spd = 0.0, strain = false, hum = 0;
    for (final c in l.comps) {
      if (c.type == 'motor' || c.type == 'motor1') {
        if (c.s.mode == 'star' || c.s.mode == 'delta' || c.s.mode == 'run') spd = math.max(spd, c.s.spd);
        if (c.s.mode == 'single' || c.s.mode == 'over') strain = true;
      }
      if (c.type == 'kc' && c.s.on) hum++;
    }
    final belt = pl != null && io != null && (pl is SortPlant || pl is FillPlant) && io.motor('M1').abs() > 0.05;
    a.loop('motor_run', spd > 0.04, volume: (belt ? 0.08 : 0.15) + (belt ? 0.25 : 0.55) * spd);
    a.loop('conveyor_run', belt, volume: 0.45);
    a.loop('coil_hum', hum > 0 && !strain, volume: math.min(0.35, 0.12 + 0.05 * hum));
    a.loop('coil_hum_loud', strain, volume: 0.7);
    a.loop('buzzer', buzz, volume: 0.45);
    a.loop('horn', horn, volume: 0.4);
    a.loop('water_flow', pl is FillPlant && io != null && io.on('Y1'), volume: 0.55);
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
    final id = s.d.shared ? s.tag : sm.compOf[s.id];
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
                if (doc.hostTags(kind: role == SymRole.hostPart ? 'NO' : s.d.kind).isEmpty) const Text('أضف أولًا الملف أو الأوفرلود الذي يتبعه هذا التلامس.', style: TextStyle(color: CC.muted)),
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
                  faults = null;
                  _diagTimer?.cancel();
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
                Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: SheetBgPainter(doc, date: todayText())))),
                Positioned.fill(
                  child: CustomPaint(
                    isComplex: true,
                    painter: SheetPainter(doc,
                        paper: false,
                        sim: sim,
                        flows: flows,
                        flash: flash,
                        phase: _phase,
                        selected: sel,
                        selWire: selWire,
                        pending: pending ?? _wireFrom,
                        drag: pf != null && _wireTo != null ? (pf, _wireTo!, doc.pinUp(_wireFrom!)) : null,
                        probes: meter == null ? null : (_needsProbes ? probeRed : null, _needsProbes ? probeBlack : null, _needsClamp ? clampWire : null),
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
        if (plant != null && plantDef != null) _plantPanel(context),
        if (meter != null) _meterPanel(context),
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
    final diagLeft = faults?.where((f) => !f.fixed).length ?? 0;
    final el = _diagClock.elapsed;
    final diagText = 'تشخيص الأعطال · ${el.inMinutes.toString().padLeft(2, '0')}:${(el.inSeconds % 60).toString().padLeft(2, '0')} · فاضل $diagLeft${_wrong > 0 ? ' · غلط $_wrong' : ''}';
    final status = diagnosing && pending == null && _wireFrom == null
        ? diagText
        : pending != null
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
                _tool(Icons.speed_rounded, 'أجهزة القياس', _pickMeter, active: meter != null),
                _tool(Icons.troubleshoot_rounded, 'تشخيص الأعطال', _diagMenu, active: diagnosing),
                _tool(Icons.precision_manufacturing_rounded, 'الماكينة', _pickPlant, active: plant != null),
                if (diagnosing) _tool(Icons.build_rounded, 'إصلاح المختار', sel != null || selWire != null ? _repair : null),
                if (diagnosing) _tool(Icons.lightbulb_outline_rounded, 'تلميح', _hint),
                _tool(Icons.center_focus_strong_rounded, 'ملء الشاشة', _fit),
                _tool(Icons.undo_rounded, 'تراجع', _undo.isEmpty ? null : _undoAct),
                _tool(Icons.redo_rounded, 'إعادة', _redo.isEmpty ? null : _redoAct),
                if (!diagnosing && (selS != null)) _tool(Icons.tune_rounded, 'الخصائص', () => _props(selS)),
                if (!diagnosing && (selS != null)) _tool(Icons.rotate_90_degrees_cw_rounded, 'لف 90° (R)', _turn),
                if (!diagnosing && (selS != null)) _tool(Icons.flip_rounded, 'قلب (F)', () => _turn(mirror: true)),
                if (!diagnosing) _penTool(),
                if (!diagnosing && (selS != null || selWire != null)) _tool(Icons.delete_outline_rounded, 'حذف', _delete, danger: true),
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
      // the tiles paint their ink on this, not under the glass tint
      child: Material(
        type: MaterialType.transparency,
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
      ),
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
