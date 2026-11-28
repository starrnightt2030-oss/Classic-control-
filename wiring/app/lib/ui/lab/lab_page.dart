import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/scheduler.dart';

import '../../data/circuits.dart';
import '../../services/progress.dart';
import '../../services/sound.dart';
import '../../sim/diagnose.dart';
import '../../sim/model.dart';
import '../../sim/solver.dart';
import '../../theme.dart';
import 'fx.dart';
import 'meter.dart';
import 'painters.dart';

enum LabMode { demo, guide, challenge, faults, free }

const modeNames = {
  LabMode.demo: 'التوصيل الجاهز',
  LabMode.guide: 'دليل خطوة بخطوة',
  LabMode.challenge: 'تحدي التوصيل',
  LabMode.faults: 'اكتشاف الأعطال',
  LabMode.free: 'المعمل الحر',
};

enum Tool { hand, meter }

class LabPage extends StatefulWidget {
  final CircuitDef? circuit;
  final LabMode mode;
  final Skin skin;
  const LabPage({this.circuit, this.mode = LabMode.free, this.skin = Skin.board});
  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with SingleTickerProviderStateMixin {
  late Sim sim;
  SimResult res = SimResult();
  late Skin skin = widget.skin;
  final fx = Fx();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double t = 0;
  final _tc = TransformationController();
  Size? _fitFor;

  Tool tool = Tool.hand;
  MeterMode meterMode = MeterMode.volt;
  final List<String> probes = [];
  WireColor color = WireColor.brown;
  String? selTerm;
  int? selWire;
  String? selPart;
  final List<List<Wire>> _undo = [];

  // guide
  int step = 0;
  // faults
  Fault? fault;
  int tries = 0;
  double faultT0 = 0;
  bool solved = false;
  // demo autoplay
  int? autoplay;
  String? banner;
  // drags on the board (parts, wire bends and legs, new wires from a terminal)
  _Drag? _drag;
  bool get _ivPan => _drag == null;
  Offset? _dragTo;
  // live wiring check
  List<Issue> issues = const [];
  bool mono = false; // every wire black, as on a printed drawing
  String? hint;

  CircuitDef? get c => widget.circuit;
  LabMode get mode => widget.mode;
  bool get canWire => mode == LabMode.guide || mode == LabMode.challenge || mode == LabMode.free;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
    if (c != null) Progress.i.setLast(c!.id);
  }

  void _load() {
    if (c == null) {
      sim = Sim(parts: head(rating: 16), wires: headWires(head()));
      tidyWires(sim);
    } else if (mode == LabMode.demo || mode == LabMode.faults) {
      sim = c!.buildDone();
    } else {
      sim = c!.buildEmpty();
    }
    if (mode == LabMode.faults) _newFault();
    step = 0;
    _run(quiet: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    Sound.loop(null);
    super.dispose();
  }

  void _onTick(Duration d) {
    final dt = math.min(.05, (d - _last).inMicroseconds / 1e6);
    _last = d;
    t += dt;
    fx.step(dt);
    if (sim.stairLeft.isNotEmpty) {
      final before = sim.stairLeft.values.map((v) => v.ceil()).join();
      sim.tick(dt);
      final after = sim.stairLeft.values.map((v) => v.ceil()).join();
      if (before != after || sim.stairLeft.isEmpty) _run(quiet: true);
    }
    setState(() {});
  }

  // ------------------------------------------------------------- simulation
  void _run({bool quiet = false}) {
    res = simulate(sim);
    issues = mode == LabMode.faults || mode == LabMode.demo ? const [] : diagnose(sim, checkColours: !mono);
    if (res.event != SimEvent.none) {
      final p = res.eventAt == null ? null : sim.part(res.eventAt!);
      final at = p == null ? const Offset(500, 300) : p.center;
      switch (res.event) {
        case SimEvent.shortCircuit:
        case SimEvent.fuse:
          fx.sparks(at, n: 55);
          fx.smoke(at, seconds: 2.5);
          Sound.play(Sfx.zap);
          Future.delayed(const Duration(milliseconds: 180), () => Sound.play(Sfx.trip));
        case SimEvent.overload:
          fx.smoke(at, seconds: 3.5);
          Sound.play(Sfx.sizzle);
          Future.delayed(const Duration(milliseconds: 700), () => Sound.play(Sfx.trip));
        case SimEvent.leakage:
          fx.sparks(at, n: 12);
          Sound.play(Sfx.trip);
        case SimEvent.noBallast:
          fx.sparks(at, n: 30);
          fx.smoke(at, seconds: 2);
          Sound.play(Sfx.zap);
        case SimEvent.none:
          break;
      }
      _snack(eventText(res.event), reset: res.event != SimEvent.noBallast);
    } else if (res.newlyTripped.isNotEmpty) {
      Sound.play(Sfx.trip);
    }
    for (final n in res.notes) {
      if (!quiet) _snack(n);
    }
    if (res.bells.isNotEmpty) {
      Sound.loop(Sfx.bell, volume: .6);
    } else if (res.tubes.isNotEmpty) {
      Sound.loop(Sfx.hum, volume: .12);
    } else {
      Sound.loop(null);
    }
    if (mounted) setState(() {});
  }

  void _snack(String msg, {bool reset = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 4),
      action: reset ? SnackBarAction(label: 'ارفع القاطع', textColor: C.goldHi, onPressed: _resetProtection) : null,
    ));
  }

  void _resetProtection() {
    sim.resetProtection();
    Sound.play(Sfx.click);
    _run();
  }

  void _power(bool v) {
    sim.power = v;
    Sound.play(Sfx.click);
    if (!v) sim.stairLeft.clear();
    _run();
  }

  // ------------------------------------------------------------------ input
  void _tapDown(Offset p) {
    if (tool != Tool.hand) return;
    if (hitTerm(sim, p) != null) return;
    final part = hitPart(sim, p);
    if (part != null && part.kind == Kind.pb) {
      part.on = true;
      Sound.play(Sfx.click, volume: .6);
      _run();
    }
  }

  void _tapUp(Offset p) {
    for (final q in sim.parts.where((q) => q.kind == Kind.pb && q.on)) {
      q.on = false;
      _run(quiet: true);
    }
    final term = hitTerm(sim, p);
    if (tool == Tool.meter) {
      if (term != null) _probe(term);
      return;
    }
    if (term != null && canWire) {
      _wireTap(term);
      return;
    }
    final w = hitWire(sim, p);
    final part = hitPart(sim, p);
    if (part != null && (w == null || _isControl(part))) {
      _partTap(part, p);
      return;
    }
    if (w != null && (canWire || mode == LabMode.demo)) {
      setState(() {
        selWire = selWire == w ? null : w;
        selTerm = null;
        selPart = null;
      });
      Sound.play(Sfx.tap, volume: .5);
      return;
    }
    setState(() {
      selTerm = null;
      selWire = null;
      selPart = null;
    });
  }

  bool _isControl(Part p) => const {Kind.sw1, Kind.sw2, Kind.swi, Kind.swd, Kind.pb, Kind.dimmer, Kind.mcb, Kind.rcd, Kind.socket, Kind.supply}.contains(p.kind);

  void _partTap(Part part, Offset at) {
    switch (part.kind) {
      case Kind.sw1:
      case Kind.sw2:
      case Kind.swi:
        part.on = !part.on;
        Sound.play(Sfx.click);
      case Kind.swd:
        if (part.toLocal(at).dx < part.type.size.width / 2) {
          part.on = !part.on;
        } else {
          part.on2 = !part.on2;
        }
        Sound.play(Sfx.click);
      case Kind.dimmer:
        part.level = part.level >= .99 ? .25 : math.min(1, part.level + .25);
        Sound.play(Sfx.tap);
      case Kind.mcb:
      case Kind.rcd:
        if (sim.tripped.contains(part.id)) {
          sim.tripped.remove(part.id);
        } else {
          sim.tripped.add(part.id);
        }
        Sound.play(Sfx.trip, volume: .7);
      case Kind.socket:
        part.plug = !part.plug;
        Sound.play(Sfx.tap);
      case Kind.supply:
        if (sim.fuseBlown) {
          sim.fuseBlown = false;
          _snack('تم تغيير الفيوز الرئيسي');
        } else {
          _power(!sim.power);
          return;
        }
      default:
        break;
    }
    if (mode == LabMode.free) selPart = part.id;
    selWire = null;
    _run();
  }

  void _wireTap(String term) {
    if (selTerm == null) {
      setState(() {
        selTerm = term;
        selWire = null;
      });
      Sound.play(Sfx.tap, volume: .6);
      return;
    }
    if (selTerm == term) {
      setState(() => selTerm = null);
      return;
    }
    final a = selTerm!;
    selTerm = null;
    if (a.split('.').first == term.split('.').first && sim.part(a.split('.').first)!.kind != Kind.jbox) {
      _snack('الطرفين في نفس الجهاز: ده قصر مش توصيلة');
    }
    if (sim.wires.any((w) => w.joins(a, term))) {
      setState(() {});
      return;
    }
    if (mode == LabMode.guide) {
      final st = c!.steps[step];
      final right = Wire(st.a, st.b, st.c).joins(a, term);
      if (!right) {
        Sound.play(Sfx.buzzer, volume: .5);
        _snack('مش دي التوصيلة المطلوبة. وصّل الطرفين اللي بينوروا.');
        setState(() {});
        return;
      }
      _addWire(a, term, st.c);
      step++;
      Sound.play(Sfx.wire);
      if (step >= c!.steps.length) {
        Sound.play(Sfx.success);
        banner = 'خلصت التوصيل! شغّل الكهرباء وجرّب المفاتيح.';
      }
      return;
    }
    _addWire(a, term, color);
    Sound.play(Sfx.wire);
  }

  void _addWire(String a, String b, WireColor col) {
    _undo.add(sim.wires.map((w) => w.copy()).toList());
    sim.wires.add(Wire(a, b, col));
    tidyWires(sim, only: {sim.wires.length - 1});
    hint = null;
    _run(quiet: true);
  }

  void _undoWire() {
    if (_undo.isEmpty) return;
    sim.wires
      ..clear()
      ..addAll(_undo.removeLast());
    if (mode == LabMode.guide && step > 0) step--;
    selWire = null;
    _run(quiet: true);
  }

  void _deleteWire(int i) {
    _undo.add(sim.wires.map((w) => w.copy()).toList());
    sim.wires.removeAt(i);
    sim.faults.removeWhere((f) => f.kind == FaultKind.wireCut);
    selWire = null;
    Sound.play(Sfx.tap);
    _run(quiet: true);
  }

  void _clearWires() {
    _undo.add(sim.wires.map((w) => w.copy()).toList());
    final keep = c == null ? <Wire>[] : headWires(sim.parts);
    sim.wires
      ..clear()
      ..addAll(keep);
    step = 0;
    banner = null;
    _run(quiet: true);
  }

  // ---------------------------------------------------------------- meter
  void _probe(String term) {
    Sound.play(Sfx.tap, volume: .5);
    setState(() {
      if (meterMode == MeterMode.neon) {
        probes
          ..clear()
          ..add(term);
      } else {
        if (probes.length >= 2) probes.clear();
        probes.add(term);
      }
    });
    final reading = meterReading();
    if (reading.beep) Sound.play(Sfx.beep, volume: .6);
  }

  MeterReading meterReading() => readMeter(sim, res, meterMode, probes);

  // ---------------------------------------------------------------- faults
  void _newFault() {
    final list = c!.faults;
    if (list.isEmpty) return;
    sim = c!.buildDone();
    final f = list[math.Random().nextInt(list.length)];
    sim.faults.add(f);
    fault = f;
    tries = 0;
    solved = false;
    faultT0 = t;
    probes.clear();
    sim.power = true;
    // show the symptom: put the switches where the fault shows up
    final rep = checkCircuit(c!, sim, keepFaults: true);
    _complaint = rep.failed.isNotEmpty ? rep.failed.first : 'الدايرة شغالة بس فيه حاجة غلط: اعمل قياس عزل (أوم) بين الأطراف والأرضي';
    final bad = c!.tests.where((t) => _complaint.startsWith(t.label)).firstOrNull;
    if (bad != null && bad.wait == 0) applyScenario(sim, bad);
    sim.resetProtection();
    _run(quiet: true);
    setState(() {});
  }

  String _complaint = '';

  String faultText(Fault f) {
    switch (f.kind) {
      case FaultKind.wireCut:
        final i = int.parse(f.target.substring(1));
        final w = i < sim.wires.length ? sim.wires[i] : null;
        if (w == null) return faultNames[f.kind]!;
        return 'سلك مقطوع بين ${termName(w.a)} و${termName(w.b)}';
      case FaultKind.looseTerm:
      case FaultKind.leakToEarth:
        return '${faultNames[f.kind]}: ${termName(f.target)}';
      default:
        final p = sim.part(f.target);
        return '${faultNames[f.kind]} (${p?.type.name ?? ''} ${f.target})';
    }
  }

  String termName(String key) {
    final i = key.indexOf('.');
    final p = sim.part(key.substring(0, i));
    if (p == null) return key;
    final tl = p.type.term(key.substring(i + 1)).label;
    return '${p.id} طرف $tl';
  }

  String complaint() => _complaint;

  Future<void> _guessFault() async {
    if (fault == null || solved) return;
    final opts = c!.faults.toList()..shuffle(math.Random(c!.id.hashCode + tries));
    final pick = await showDialog<Fault>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('إيه العطل اللي لقيته؟'),
        children: [
          for (final f in opts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f),
              child: Row(children: [const Icon(Icons.build_circle_outlined, color: C.gold, size: 20), const SizedBox(width: 8), Expanded(child: Text(faultText(f)))]),
            ),
        ],
      ),
    );
    if (pick == null) return;
    if (pick.kind == fault!.kind && pick.target == fault!.target) {
      solved = true;
      Sound.play(Sfx.success);
      Progress.i.foundFault(c!.id);
      final secs = (t - faultT0).round();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('برافو! لقيت العطل'),
          content: Text('${faultText(fault!)}\nالوقت: $secs ثانية • المحاولات: ${tries + 1}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                sim.faults.clear();
                sim.resetProtection();
                Sound.play(Sfx.click);
                _run();
              },
              child: const Text('صلّح العطل'),
            ),
          ],
        ),
      );
    } else {
      tries++;
      Sound.play(Sfx.fail);
      _snack('لأ، مش ده العطل. قيس تاني بالآفوميتر أو مفك الاختبار.');
    }
    setState(() {});
  }

  // -------------------------------------------------------------- challenge
  Future<void> _check() async {
    final rep = checkCircuit(c!, sim);
    Sound.play(rep.ok ? Sfx.success : Sfx.fail);
    if (rep.ok) Progress.i.setStars(c!.id, rep.stars);
    // show the result on the board too
    sim.power = true;
    _run(quiet: true);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(rep.ok ? 'توصيل صح' : 'لسه فيه غلط'),
          const Spacer(),
          for (var i = 0; i < 3; i++) Icon(i < rep.stars ? Icons.star_rounded : Icons.star_outline_rounded, color: C.gold),
        ]),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final s in rep.passed) _line(Icons.check_circle, C.ok, s),
            for (final s in rep.failed) _line(Icons.cancel, C.bad, s),
            for (final s in rep.warnings) _line(Icons.warning_amber_rounded, C.warn, s),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
      ),
    );
  }

  Widget _line(IconData i, Color col, String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, color: col, size: 20), const SizedBox(width: 8), Expanded(child: Text(s))]),
      );

  void _showSolution() {
    _undo.add(sim.wires.map((w) => w.copy()).toList());
    sim.wires
      ..clear()
      ..addAll(c!.referenceWires());
    step = c!.steps.length;
    _run(quiet: true);
  }

  // ------------------------------------------------------------- demo play
  Future<void> _autoplay() async {
    if (autoplay != null) {
      setState(() => autoplay = null);
      return;
    }
    sim.power = true;
    for (var i = 0; i < c!.tests.length; i++) {
      if (!mounted) return;
      setState(() => autoplay = i);
      final sc = c!.tests[i];
      applyScenario(sim, sc);
      Sound.play(Sfx.click);
      _run(quiet: true);
      await Future.delayed(const Duration(milliseconds: 1600));
      if (sc.wait > 0) {
        for (final p in sim.parts.where((p) => p.kind == Kind.pb)) {
          p.on = false;
        }
        _run(quiet: true);
        await Future.delayed(Duration(milliseconds: (sc.wait * 1000).round()));
      }
      if (autoplay == null) return;
    }
    if (mounted) setState(() => autoplay = null);
  }

  // ------------------------------------------------------------- free lab
  static const _prefix = {
    Kind.supply: 'G', Kind.mcb: 'Q', Kind.rcd: 'F', Kind.meter: 'M', Kind.nbar: 'NB', Kind.ebar: 'EB', Kind.jbox: 'J', Kind.jbox6: 'J', Kind.jbox8: 'J', Kind.jbox10: 'J',
    Kind.sw1: 'S', Kind.sw2: 'S', Kind.swi: 'S', Kind.swd: 'S', Kind.pb: 'P', Kind.dimmer: 'D', Kind.lamp: 'E', Kind.socket: 'X',
    Kind.bell: 'H', Kind.lock: 'Y', Kind.tube: 'T', Kind.ballast: 'BL', Kind.starter: 'ST', Kind.stair: 'K', Kind.driver: 'DR', Kind.ledpanel: 'LP',
  };

  void _addPart(Kind k) {
    final pre = _prefix[k]!;
    var n = 1;
    while (sim.part('$pre$n') != null) {
      n++;
    }
    final id = '$pre$n';
    final m = _tc.value.clone()..invert();
    final center = MatrixUtils.transformPoint(m, Offset(_viewSize.width / 2, _viewSize.height / 2));
    final sz = partTypes[k]!.size;
    final pos = Offset((center.dx - sz.width / 2).clamp(0, boardSize.width - sz.width), (center.dy - sz.height / 2).clamp(0, boardSize.height - sz.height));
    sim.parts.add(Part(id, k, pos, watts: k == Kind.lamp ? 60 : (k == Kind.tube || k == Kind.ballast) ? 40 : 0, rating: 10));
    selPart = id;
    Sound.play(Sfx.tap);
    _run(quiet: true);
  }

  void _deletePart(String id) {
    sim.parts.removeWhere((p) => p.id == id);
    sim.wires.removeWhere((w) => w.a.startsWith('$id.') || w.b.startsWith('$id.'));
    sim.faults.clear();
    selPart = null;
    _run(quiet: true);
  }

  Size _viewSize = const Size(800, 500);

  Future<void> _saveBoard() async {
    final ctl = TextEditingController(text: 'لوحة ${Progress.i.boards().length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ اللوحة'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('حفظ'))],
      ),
    );
    if (name == null || name.isEmpty) return;
    await Progress.i.saveBoard(name, jsonEncode(sim.toJson()));
    _snack('اتحفظت: $name');
  }

  Future<void> _openBoard() async {
    final names = Progress.i.boards();
    if (names.isEmpty) {
      _snack('مفيش لوحات محفوظة لسه');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اللوحات المحفوظة'),
        children: [
          for (final n in names)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, n),
              child: Row(children: [
                const Icon(Icons.dashboard_customize_outlined, color: C.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(n)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: C.bad),
                  onPressed: () {
                    Progress.i.deleteBoard(n);
                    Navigator.pop(ctx);
                  },
                ),
              ]),
            ),
        ],
      ),
    );
    final j = name == null ? null : Progress.i.board(name);
    if (j == null) return;
    sim = Sim.fromJson(jsonDecode(j));
    _run(quiet: true);
  }

  void _randomFault() {
    if (sim.wires.length < 2) return;
    final r = math.Random();
    sim.faults.clear();
    if (r.nextBool()) {
      sim.faults.add(Fault(FaultKind.wireCut, 'w${r.nextInt(sim.wires.length)}'));
    } else {
      final w = sim.wires[r.nextInt(sim.wires.length)];
      sim.faults.add(Fault(FaultKind.looseTerm, r.nextBool() ? w.a : w.b));
    }
    Sound.play(Sfx.tap);
    _snack('اتحط عطل مخفي في اللوحة. دوّر عليه بالآفوميتر.');
    _run(quiet: true);
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final title = c == null ? 'المعمل الحر' : '${c!.no}. ${c!.title}';
    return Scaffold(
      backgroundColor: C.navy0,
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.navy1, C.navy2]))),
        title: Column(children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          Text(modeNames[mode]!, style: const TextStyle(fontSize: 11, color: C.goldHi)),
        ]),
        actions: [
          IconButton(
            tooltip: skin == Skin.board ? 'عرض المخطط' : 'عرض اللوحة',
            icon: Icon(skin == Skin.board ? Icons.schema_outlined : Icons.view_in_ar_outlined),
            onPressed: () {
              Sound.play(Sfx.tap);
              setState(() => skin = skin == Skin.board ? Skin.schematic : Skin.board);
            },
          ),
          _PowerSwitch(on: sim.power, onChanged: _power),
          const SizedBox(width: 8),
        ],
      ),
      body: NavyBackground(
        child: wide
            ? Row(children: [Expanded(child: _viewer()), SizedBox(width: 380, child: Align(alignment: Alignment.topCenter, child: _panel(wide: true)))])
            : Column(children: [Expanded(child: _viewer()), _panel(wide: false)]),
      ),
    );
  }

  Widget _viewer() => LayoutBuilder(builder: (context, box) {
        _viewSize = box.biggest;
        if (_fitFor != box.biggest) {
          _fitFor = box.biggest;
          // fit the used part of the board (parts + margin), not the whole plywood
          var bb = Offset.zero & boardSize;
          if (sim.parts.isNotEmpty) {
            bb = sim.parts.map((p) => p.rect).reduce((a, b) => a.expandToInclude(b)).inflate(24).intersect(Offset.zero & boardSize);
          }
          final k = math.min(box.maxWidth / bb.width, box.maxHeight / bb.height) * .98;
          final dx = (box.maxWidth - bb.width * k) / 2 - bb.left * k, dy = (box.maxHeight - bb.height * k) / 2 - bb.top * k;
          _tc.value = Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..scaleByDouble(k, k, 1, 1);
        }
        final st = BoardState(
          sim: sim, res: res, skin: skin, t: t, selTerm: selTerm, selWire: selWire, selPart: solved ? '#reveal' : selPart, fx: fx,
          glowTerms: mode == LabMode.guide && step < (c?.steps.length ?? 0) ? {c!.steps[step].a, c!.steps[step].b} : (hint != null && _hintStep != null ? {_hintStep!.a, _hintStep!.b} : const {}),
          probes: tool == Tool.meter ? probes : const [],
          mono: mono, issues: issues,
          dragFrom: _drag?.kind == _DK.term ? termPos(sim, _drag!.term!) : null, dragTo: _dragTo,
        );
        return Stack(children: [
          ClipRect(
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              minScale: .2,
              maxScale: 8,
              panEnabled: _ivPan,
              scaleEnabled: _ivPan,
              boundaryMargin: const EdgeInsets.all(400),
              child: Listener(
               onPointerDown: (e) => _down(e.localPosition),
               onPointerMove: (e) => _move(e.localPosition),
               onPointerUp: (e) => _up(e.localPosition),
               onPointerCancel: (_) => setState(() {
                 _drag = null;
                 _dragTo = null;
               }),
               child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _tapDown(d.localPosition),
                onTapUp: (d) => _tapUp(d.localPosition),
                onTapCancel: () {
                  for (final q in sim.parts.where((q) => q.kind == Kind.pb && q.on)) {
                    q.on = false;
                  }
                  _run(quiet: true);
                },
                onLongPressStart: canWire
                    ? (d) {
                        final p = hitPart(sim, d.localPosition);
                        if (p == null) return;
                        setState(() {
                          selPart = p.id;
                          selWire = null;
                        });
                        Sound.play(Sfx.tap);
                      }
                    : null,
                child: SizedBox.fromSize(size: boardSize, child: CustomPaint(painter: BoardPainter(st))),
              ),
              ),
            ),
          ),
          if (tool == Tool.meter)
            Positioned(
              top: 8,
              left: 8,
              child: MeterWidget(
                mode: meterMode,
                reading: meterReading(),
                onMode: (m) => setState(() {
                  meterMode = m;
                  probes.clear();
                  Sound.play(Sfx.click, volume: .5);
                }),
                onClose: () => setState(() {
                  tool = Tool.hand;
                  probes.clear();
                }),
              ),
            ),
          if (banner != null)
            Positioned(
              top: 8,
              right: 8,
              left: tool == Tool.meter ? 200 : 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: glowCard(r: 12, border: C.gold),
                child: Row(children: [
                  const Icon(Icons.emoji_events_rounded, color: C.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text(banner!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  InkWell(onTap: () => setState(() => banner = null), child: const Icon(Icons.close, size: 18)),
                ]),
              ),
            ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Column(children: [
              _zoomBtn(Icons.add, () => _zoom(1.25)),
              const SizedBox(height: 6),
              _zoomBtn(Icons.remove, () => _zoom(.8)),
              const SizedBox(height: 6),
              _zoomBtn(Icons.fit_screen_outlined, () => setState(() => _fitFor = null)),
            ]),
          ),
        ]);
      });

  // ------------------------------------------------------------- board drags
  Offset _snap(Offset o, [double g = 2.5]) => Offset((o.dx / g).round() * g, (o.dy / g).round() * g);

  void _down(Offset p) {
    if (tool == Tool.meter || !(canWire || mode == LabMode.demo)) return;
    _Drag? d;
    final sw = selWire;
    if (sw != null && sw < sim.wires.length && canWire) {
      final w = sim.wires[sw];
      for (var k = 0; k < w.pts.length; k++) {
        if ((w.pts[k] - p).distance < 4.5) d = _Drag(_DK.bend, p, wire: sw, idx: k);
      }
      if (d == null) {
        final leg = hitLeg(sim, sw, p);
        if (leg != null) d = _Drag(_DK.leg, p, wire: sw, idx: leg);
      }
    }
    if (d == null && canWire) {
      final t = hitTerm(sim, p);
      if (t != null) d = _Drag(_DK.term, p, term: t);
    }
    if (d == null && mode == LabMode.free) {
      final part = hitPart(sim, p);
      if (part != null) d = _Drag(_DK.part, p, part: part.id, orig: part.pos);
    }
    if (d != null) setState(() => _drag = d);
  }

  void _move(Offset p) {
    final d = _drag;
    if (d == null) return;
    if (!d.moved && (p - d.start).distance < 3) return;
    if (!d.moved && (d.kind == _DK.bend || d.kind == _DK.leg)) _undo.add(sim.wires.map((w) => w.copy()).toList());
    d.moved = true;
    switch (d.kind) {
      case _DK.part:
        final part = sim.part(d.part!);
        if (part == null) return;
        final n = _snap(d.orig! + p - d.start, 5);
        part.pos = Offset(n.dx.clamp(0, boardSize.width - part.box.width), n.dy.clamp(0, boardSize.height - part.box.height));
        for (final w in sim.wires) {
          if (w.a.startsWith('${part.id}.') || w.b.startsWith('${part.id}.')) w.pts = [];
        }
      case _DK.bend:
        final w = sim.wires[d.wire!];
        w.pts[d.idx!] = _snap(p);
      case _DK.leg:
        _dragLeg(d, p);
      case _DK.term:
        _dragTo = p;
    }
    setState(() {});
  }

  /// slide one leg of a wire sideways, keeping its corners square
  void _dragLeg(_Drag d, Offset p) {
    final w = sim.wires[d.wire!];
    final full = wirePoints(sim, d.wire!)!;
    var k = d.idx!;
    if (!d.prepared) {
      // a leg that starts or ends on a terminal gets its own corner first, so the
      // wire still leaves the screw straight
      if (k == full.length - 2) full.insert(full.length - 1, full.last);
      if (k == 0) {
        full.insert(1, full.first);
        k = 1;
      }
      d.idx = k;
      d.base = List.of(full);
      d.prepared = true;
    }
    final base = d.base!;
    final a = base[k], b = base[k + 1];
    final delta = p - d.start;
    final horiz = (a.dy - b.dy).abs() < (a.dx - b.dx).abs();
    final mv = horiz ? Offset(0, delta.dy) : Offset(delta.dx, 0);
    final out = List.of(base);
    out[k] = _snap(a + mv);
    out[k + 1] = _snap(b + mv);
    w.pts = out.sublist(1, out.length - 1);
  }

  void _up(Offset p) {
    final d = _drag;
    if (d == null) return;
    _drag = null;
    _dragTo = null;
    if (d.moved) {
      switch (d.kind) {
        case _DK.part:
          final id = d.part!;
          tidyWires(sim, only: {
            for (var i = 0; i < sim.wires.length; i++)
              if (sim.wires[i].a.startsWith('$id.') || sim.wires[i].b.startsWith('$id.')) i
          });
          _run(quiet: true);
        case _DK.bend:
        case _DK.leg:
          final w = sim.wires[d.wire!];
          w.pts = _clean([termPos(sim, w.a)!, ...w.pts, termPos(sim, w.b)!]);
        case _DK.term:
          final t = hitTerm(sim, p);
          if (t != null && t != d.term) {
            selTerm = d.term;
            _wireTap(t);
          }
      }
    }
    setState(() {});
  }

  /// drop repeated and in-line points
  List<Offset> _clean(List<Offset> f) {
    final o = <Offset>[f.first];
    for (var i = 1; i < f.length; i++) {
      if ((f[i] - o.last).distance > .5) o.add(f[i]);
    }
    if (o.length < 2) return const [];
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 1; i + 1 < o.length; i++) {
        final a = o[i - 1], b = o[i], c = o[i + 1];
        final cross = (b - a).dx * (c - b).dy - (b - a).dy * (c - b).dx;
        if (cross.abs() < .5) {
          o.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    return o.length <= 2 ? [Offset((o.first.dx + o.last.dx) / 2, (o.first.dy + o.last.dy) / 2)] : o.sublist(1, o.length - 1);
  }

  void _tidy() {
    _undo.add(sim.wires.map((w) => w.copy()).toList());
    final n = tidyWires(sim);
    Sound.play(Sfx.wire, volume: .6);
    _snack('اتنظّمت $n سلك: مسارات مستقيمة بزوايا قايمة، ماشية جنب بعض ومش بتعدّي من ورا المكونات');
    setState(() {});
  }

  void _rotate(Part p, int dir) {
    final c0 = p.center;
    p.rot = (p.rot + dir) & 3;
    final n = c0 - Offset(p.box.width / 2, p.box.height / 2);
    p.pos = Offset(n.dx.clamp(0, boardSize.width - p.box.width), n.dy.clamp(0, boardSize.height - p.box.height));
    tidyWires(sim, only: {
      for (var i = 0; i < sim.wires.length; i++)
        if (sim.wires[i].a.startsWith('${p.id}.') || sim.wires[i].b.startsWith('${p.id}.')) i
    });
    Sound.play(Sfx.tap);
    _run(quiet: true);
  }

  void _hint() {
    final h = c == null ? null : nextHint(c!, sim);
    setState(() => hint = h == null ? 'كل التوصيلات المطلوبة موجودة. شغّل الكهرباء وجرّب، أو اضغط «افحص».' : h.text);
    if (h != null) _hintStep = h;
    Sound.play(Sfx.tap);
  }

  Step? _hintStep;

  Widget _zoomBtn(IconData i, VoidCallback f) => Material(
        color: C.navy1.withValues(alpha: .85),
        shape: const CircleBorder(side: BorderSide(color: C.glow, width: .8)),
        child: InkWell(customBorder: const CircleBorder(), onTap: f, child: Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 20, color: C.text))),
      );

  void _zoom(double k) {
    final cx = _viewSize.width / 2, cy = _viewSize.height / 2;
    final m = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(k, k, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
    setState(() => _tc.value = m * _tc.value);
  }

  // ---------------------------------------------------------- bottom panel
  Widget _panel({required bool wide}) {
    final items = <Widget>[];
    if (canWire) items.add(_card(_boardTools()));
    if (issues.isNotEmpty) items.add(_card(_issuesCard()));
    if (hint != null) {
      items.add(_card(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lightbulb_outline, color: C.goldHi),
        const SizedBox(width: 8),
        Expanded(child: Text(hint!, style: const TextStyle(height: 1.5))),
        InkWell(onTap: () => setState(() => hint = null), child: const Icon(Icons.close, size: 18)),
      ])));
    }
    // selected wire tools
    if (selWire != null && selWire! < sim.wires.length) {
      final w = sim.wires[selWire!];
      items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('سلك: ${termName(w.a)} ← ${termName(w.b)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(wireColorNames[w.color]!, style: const TextStyle(color: C.dim, fontSize: 12)),
        if (canWire)
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final col in WireColor.values)
              _colorDot(col, w.color == col, () => setState(() {
                    w.color = col;
                    Sound.play(Sfx.tap);
                  })),
            TextButton.icon(onPressed: () => _deleteWire(selWire!), icon: const Icon(Icons.content_cut, color: C.bad), label: const Text('شيل السلك')),
          ]),
      ])));
    }
    switch (mode) {
      case LabMode.demo:
        items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c!.brief, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < c!.tests.length; i++)
              ChoiceChip(
                label: Text(c!.tests[i].label),
                selected: autoplay == i,
                onSelected: (_) {
                  sim.power = true;
                  applyScenario(sim, c!.tests[i]);
                  Sound.play(Sfx.click);
                  _run();
                },
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: _autoplay, icon: Icon(autoplay == null ? Icons.play_arrow_rounded : Icons.stop_rounded), label: Text(autoplay == null ? 'تشغيل تلقائي للحالات' : 'إيقاف')),
            _meterBtn(),
          ]),
        ])));
      case LabMode.guide:
        final n = c!.steps.length;
        final done = step >= n;
        items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(done ? 'تم التوصيل' : 'الخطوة ${step + 1} من $n', style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text(done ? '' : 'لون السلك: ${wireColorNames[c!.steps[step].c]}', textAlign: TextAlign.end, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.dim))),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: step / n, color: C.gold, backgroundColor: Colors.white12, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 8),
          Text(done ? 'شغّل الكهرباء من الزرار فوق وجرّب المفاتيح. ولو عايز تتأكد، افحص من وضع التحدي.' : c!.steps[step].text, style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (!done)
              FilledButton.icon(
                onPressed: () {
                  final st = c!.steps[step];
                  _addWire(st.a, st.b, st.c);
                  step++;
                  Sound.play(Sfx.wire);
                  if (step >= n) banner = 'خلصت التوصيل! شغّل الكهرباء وجرّب المفاتيح.';
                },
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('وصّلها لي'),
              ),
            OutlinedButton.icon(onPressed: _undoWire, icon: const Icon(Icons.undo), label: const Text('رجوع')),
            OutlinedButton.icon(
                onPressed: () => setState(() {
                      _clearWires();
                    }),
                icon: const Icon(Icons.restart_alt),
                label: const Text('من الأول')),
          ]),
        ])));
      case LabMode.challenge:
        items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('وصّل الدايرة لوحدك من غير دليل، وبعدين اضغط «افحص».', style: const TextStyle(color: C.dim)),
          const SizedBox(height: 6),
          _colorPicker(),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: _check, icon: const Icon(Icons.fact_check_outlined), label: const Text('افحص التوصيل')),
            OutlinedButton.icon(onPressed: _undoWire, icon: const Icon(Icons.undo), label: const Text('رجوع')),
            OutlinedButton.icon(onPressed: _clearWires, icon: const Icon(Icons.delete_sweep_outlined), label: const Text('امسح')),
            _meterBtn(),
            OutlinedButton.icon(onPressed: _hint, icon: const Icon(Icons.lightbulb_outline), label: const Text('تلميح')),
            TextButton(onPressed: _showSolution, child: const Text('اعرض الحل')),
          ]),
        ])));
      case LabMode.faults:
        items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.report_problem_outlined, color: C.warn),
            const SizedBox(width: 6),
            Expanded(child: Text(solved ? 'اتصلح العطل' : 'الشكوى: ${complaint()}', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
          ]),
          const SizedBox(height: 4),
          Text('الوقت: ${(t - faultT0).floor()} ث • محاولات غلط: $tries', style: const TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('افتح الآفوميتر: قيس الفولت والكهرباء شغالة، والأوم والكهرباء مفصولة، أو جرّب مفك الاختبار على الأطراف.', style: TextStyle(fontSize: 12, color: C.dim, height: 1.4)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _meterBtn(),
            FilledButton.icon(onPressed: solved ? null : _guessFault, icon: const Icon(Icons.search), label: const Text('حدد العطل')),
            OutlinedButton.icon(onPressed: _newFault, icon: const Icon(Icons.casino_outlined), label: const Text('عطل جديد')),
          ]),
        ])));
      case LabMode.free:
        final sp = selPart == null ? null : sim.part(selPart!);
        if (sp != null) items.add(_card(_partProps(sp)));
        items.add(_card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _colorPicker(),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: _palette, icon: const Icon(Icons.add_box_outlined), label: const Text('مكون')),
            _meterBtn(),
            OutlinedButton.icon(onPressed: _undoWire, icon: const Icon(Icons.undo), label: const Text('رجوع')),
            OutlinedButton.icon(onPressed: _saveBoard, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
            OutlinedButton.icon(onPressed: _openBoard, icon: const Icon(Icons.folder_open_outlined), label: const Text('فتح')),
            OutlinedButton.icon(onPressed: _randomFault, icon: const Icon(Icons.bug_report_outlined), label: const Text('عطل')),
            if (sim.faults.isNotEmpty)
              TextButton(
                  onPressed: () {
                    final f = sim.faults.first;
                    _snack('العطل: ${faultText(f)}');
                    sim.faults.clear();
                    _run(quiet: true);
                  },
                  child: const Text('اكشف العطل')),
            TextButton(
                onPressed: () {
                  sim = Sim(parts: head(rating: 16), wires: headWires(head()));
                  tidyWires(sim);
                  selPart = null;
                  _run(quiet: true);
                },
                child: const Text('لوحة جديدة')),
          ]),
          const SizedBox(height: 4),
          const Text('اسحب من طرف لطرف (أو اضغط على الطرفين) لتوصيل سلك • اسحب المكون لتحريكه • اختار السلك واسحب أي جزء منه أو أي ركن لتعديل مساره', style: TextStyle(fontSize: 11, color: C.dim, height: 1.4)),
        ])));
    }
    final col = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
    if (wide) return SingleChildScrollView(padding: const EdgeInsets.all(8), child: col);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .42),
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: SafeArea(top: false, child: col)),
    );
  }

  Widget _boardTools() {
    final sp = selPart == null || mode == LabMode.free ? null : sim.part(selPart!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.tonalIcon(onPressed: _tidy, icon: const Icon(Icons.auto_awesome_mosaic_outlined), label: const Text('نظّم الأسلاك')),
        FilterChip(
          label: const Text('أسلاك سودا'),
          selected: mono,
          onSelected: (v) {
            mono = v;
            _run(quiet: true);
          },
        ),
        if (sp != null) ...[
          Text('${sp.id}:', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(tooltip: 'لف', onPressed: () => _rotate(sp, -1), icon: const Icon(Icons.rotate_left)),
          IconButton(tooltip: 'لف', onPressed: () => _rotate(sp, 1), icon: const Icon(Icons.rotate_right)),
        ],
      ]),
      if (selWire != null) const Text('اسحب أي جزء من السلك المختار أو النقط البيضا اللي عليه عشان تغيّر مساره.', style: TextStyle(fontSize: 11, color: C.dim)),
    ]);
  }

  Widget _issuesCard() {
    final errs = issues.where((i) => i.error).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(errs > 0 ? Icons.error_outline : Icons.warning_amber_rounded, color: errs > 0 ? C.bad : C.warn),
        const SizedBox(width: 6),
        Expanded(child: Text(errs > 0 ? 'فيه $errs غلطة في التوصيل' : 'ملاحظات على التوصيل', style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
      for (final i in issues.take(4))
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(i.error ? Icons.close_rounded : Icons.priority_high_rounded, color: i.error ? C.bad : C.warn, size: 20),
            title: Text(i.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.only(bottom: 6),
            children: [Text('ليه غلط؟ ${i.why}', style: const TextStyle(fontSize: 12.5, color: C.dim, height: 1.5))],
          ),
        ),
      if (issues.length > 4) Text('و${issues.length - 4} ملاحظات تانية', style: const TextStyle(fontSize: 12, color: C.dim)),
    ]);
  }

  Widget _card(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(padding: const EdgeInsets.all(12), decoration: glowCard(r: 14), child: child));

  Widget _meterBtn() => OutlinedButton.icon(
        style: tool == Tool.meter ? OutlinedButton.styleFrom(backgroundColor: C.gold.withValues(alpha: .2)) : null,
        onPressed: () => setState(() {
          tool = tool == Tool.meter ? Tool.hand : Tool.meter;
          probes.clear();
          selTerm = null;
          Sound.play(Sfx.click, volume: .5);
        }),
        icon: const Icon(Icons.speed),
        label: const Text('آفوميتر'),
      );

  Widget _colorDot(WireColor col, bool sel, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: col == WireColor.earth ? const SweepGradient(colors: [Color(0xFF2FA84F), Color(0xFFF3D21F), Color(0xFF2FA84F), Color(0xFFF3D21F), Color(0xFF2FA84F)]) : null,
            color: col == WireColor.earth ? null : wireColor(col),
            border: Border.all(color: sel ? C.goldHi : Colors.white30, width: sel ? 3 : 1),
          ),
        ),
      );

  Widget _colorPicker() => Row(children: [
        const Text('لون السلك: ', style: TextStyle(fontSize: 13)),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final col in WireColor.values) Tooltip(message: wireColorNames[col]!, child: _colorDot(col, color == col, () => setState(() => color = col))),
          ]),
        ),
      ]);

  Widget _partProps(Part p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PartIcon(p.kind, size: 34),
          const SizedBox(width: 8),
          Expanded(child: Text('${p.id} • ${p.type.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'لف عكس عقارب الساعة', onPressed: () => _rotate(p, -1), icon: const Icon(Icons.rotate_left)),
          IconButton(tooltip: 'لف مع عقارب الساعة', onPressed: () => _rotate(p, 1), icon: const Icon(Icons.rotate_right)),
          if (mode == LabMode.free) IconButton(onPressed: () => _deletePart(p.id), icon: const Icon(Icons.delete_outline, color: C.bad)),
        ]),
        if (p.kind == Kind.lamp || p.kind == Kind.tube || p.kind == Kind.ballast)
          Row(children: [
            const Text('القدرة: '),
            for (final w in p.kind == Kind.lamp ? [15, 25, 40, 60, 100, 200] : [18, 20, 36, 40])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(label: Text('$w'), selected: p.watts == w, onSelected: (_) => setState(() {
                      p.watts = w;
                      _run(quiet: true);
                    })),
              ),
          ]),
        if (p.kind == Kind.lamp)
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('لمبة LED'), value: p.led, onChanged: (v) => setState(() => p.led = v)),
        if (p.kind == Kind.mcb)
          Wrap(spacing: 4, children: [
            const Text('التيار: '),
            for (final a in [6, 10, 16, 20, 25, 32, 40]) ChoiceChip(label: Text('${a}A'), selected: p.rating == a, onSelected: (_) => setState(() => p.rating = a)),
          ]),
        if (p.kind == Kind.dimmer)
          Slider(value: p.level, onChanged: (v) {
            p.level = v;
            _run(quiet: true);
          }),
      ]);

  Future<void> _palette() async {
    const groups = {
      'التغذية والحماية': [Kind.supply, Kind.mcb, Kind.rcd, Kind.meter, Kind.nbar, Kind.ebar],
      'علب التجميع (البواط)': [Kind.jbox, Kind.jbox6, Kind.jbox8, Kind.jbox10],
      'المفاتيح': [Kind.sw1, Kind.sw2, Kind.swi, Kind.swd, Kind.pb, Kind.dimmer],
      'الأحمال': [Kind.lamp, Kind.socket, Kind.bell, Kind.lock],
      'الفلورسنت والـLED والسلم': [Kind.tube, Kind.ballast, Kind.starter, Kind.driver, Kind.ledpanel, Kind.stair],
    };
    final k = await showModalBottomSheet<Kind>(
      context: context,
      backgroundColor: C.navy1,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final g in groups.entries) ...[
              SectionTitle(g.key),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final kind in g.value)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, kind),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 96,
                      padding: const EdgeInsets.all(6),
                      decoration: glowCard(r: 12),
                      child: Column(children: [
                        Container(decoration: BoxDecoration(color: skin == Skin.board ? const Color(0xFFDDE2E8) : Colors.white, borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.all(4), child: PartIcon(kind, size: 60, skin: skin)),
                        const SizedBox(height: 4),
                        Text(partTypes[kind]!.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.2)),
                      ]),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (k != null) _addPart(k);
  }
}

class _PowerSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _PowerSwitch({required this.on, required this.onChanged});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!on),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: on ? const Color(0xFFD32F2F) : Colors.white10,
            border: Border.all(color: on ? const Color(0xFFFF8A80) : Colors.white24),
            boxShadow: on ? [const BoxShadow(color: Color(0x88FF1744), blurRadius: 12)] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.power_settings_new_rounded, size: 18, color: on ? Colors.white : C.dim),
            const SizedBox(width: 4),
            Text(on ? 'الكهرباء شغالة' : 'الكهرباء مفصولة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : C.dim)),
          ]),
        ),
      );
}

enum _DK { part, bend, leg, term }

class _Drag {
  final _DK kind;
  final Offset start;
  final int? wire;
  int? idx;
  final String? term;
  final String? part;
  final Offset? orig;
  bool moved = false;
  bool prepared = false;
  List<Offset>? base;
  _Drag(this.kind, this.start, {this.wire, this.idx, this.term, this.part, this.orig});
}
