// «أجهزة القياس»: the tab that explains and simulates the measuring instruments.
//
//  MetersPage       the list: analog and digital multimeter, clamp meter, megger, wattmeter
//  InstrumentPage   one instrument: «الشرح» (how it works, how to connect and read it),
//                   «الأجزاء» (the 3D model, tap a part to learn it), «تجربة حية» (the bench)
//  LiveLab          the live bench: plug the leads, turn the knob, put the probes on a real
//                   distribution board or motor terminal box, and follow a guided experiment
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'bench.dart';
import 'inst3d.dart';
import 'instruments.dart';
import 'tasks.dart';

class MetersPage extends StatelessWidget {
  const MetersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
      final cols = c.maxWidth >= 1250 ? 3 : (c.maxWidth >= 700 ? 2 : 1);
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 8),
          sliver: const SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('أجهزة القياس', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('اتعلّم كل جهاز بأجزائه وطريقة توصيله، وبعدين جرّبه بإيدك على لوحة توزيع حقيقية ومحرك 3 فاز.',
                  style: TextStyle(fontSize: 13, color: CC.muted)),
              SizedBox(height: 10),
              SafetyStrip(text: 'كل القياسات هنا محاكاة. في الحقيقة: جهاز بفئة أمان مناسبة، وكابلات سليمة، وإيدك ورا الحلقة الواقية.'),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 28),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: cols == 1 ? 200 : 184),
            delegate: SliverChildBuilderDelegate((context, i) => _InstrumentCard(inst: instruments[i]), childCount: instruments.length),
          ),
        ),
      ]);
    });
  }
}

class _InstrumentCard extends StatelessWidget {
  final Instrument inst;
  const _InstrumentCard({required this.inst});

  @override
  Widget build(BuildContext context) {
    final n = tasksFor(inst.key).length;
    return Glass(
      radius: 20,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstrumentPage(inst: inst))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 118,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const RadialGradient(colors: [Color(0xFF223566), Color(0xFF0A1226)], radius: 0.9),
              ),
              padding: const EdgeInsets.all(6),
              child: Image.asset(inst.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: CcIcon(CcIcons.meter, size: 44, color: CC.accentSoft))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(inst.nameAr, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700), maxLines: 2),
                Text(inst.nameEn, style: const TextStyle(fontSize: 11.5, color: CC.muted, fontFamily: CC.mono)),
                const SizedBox(height: 4),
                Text(inst.short, style: const TextStyle(fontSize: 12.5, color: CC.text2, height: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Wrap(runSpacing: 4, children: [
                  _Tag('${inst.parts.length} جزء'),
                  _Tag('$n تجربة حية'),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, {this.color = CC.accentSoft});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: CC.amberBg, borderRadius: BorderRadius.circular(99), border: Border.all(color: CC.amberLine)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );
}

// ======================================================================= one instrument
class InstrumentPage extends StatefulWidget {
  final Instrument inst;
  final int tab;
  const InstrumentPage({super.key, required this.inst, this.tab = 0});
  @override
  State<InstrumentPage> createState() => _InstrumentPageState();
}

class _InstrumentPageState extends State<InstrumentPage> {
  late int _tab = widget.tab;

  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final tabs = ['الشرح', 'الأجزاء', 'تجربة حية'];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(children: [
              SquareButton(icon: CcIcons.back, label: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text(inst.nameAr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (var i = 0; i < tabs.length; i++) Pill(label: tabs[i], selected: _tab == i, onTap: () => setState(() => _tab = i))]),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              0 => _GuideView(inst: inst, onLive: () => setState(() => _tab = 2), onParts: () => setState(() => _tab = 1)),
              1 => _PartsView(inst: inst),
              _ => LiveLab(inst: inst),
            },
          ),
        ]),
      ),
    );
  }
}

class _GuideView extends StatelessWidget {
  final Instrument inst;
  final VoidCallback onLive, onParts;
  const _GuideView({required this.inst, required this.onLive, required this.onParts});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 14.0;
      final wide = c.maxWidth >= 900;
      final hero = Container(
        height: wide ? 340 : 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const RadialGradient(colors: [Color(0xFF26407A), Color(0xFF081024)], radius: 0.85),
          border: Border.all(color: CC.glassBorder),
        ),
        padding: const EdgeInsets.all(14),
        child: Image.asset(inst.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: CcIcon(CcIcons.meter, size: 80, color: CC.accentSoft))),
      );
      final cards = [
        Text(inst.short, style: const TextStyle(fontSize: 15, color: CC.text2, height: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: onLive, icon: const CcIcon(CcIcons.bolt, size: 18, color: Colors.white), label: const Text('ابدأ التجربة الحية'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: onParts, icon: const CcIcon(CcIcons.tag, size: 18), label: const Text('اعرف الأجزاء'))),
        ]),
        const SizedBox(height: 14),
        for (final (t, body) in inst.guide)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              radius: 18,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: CC.accentSoft)),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(fontSize: 14, height: 1.6, color: CC.text)),
              ]),
            ),
          ),
        if (inst.jacks.isNotEmpty) ...[
          const SectionTitle('المداخل والكابلات'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final j in inst.jacks) _Tag('${j.label}: ${j.about}', color: CC.text2),
          ]),
        ],
      ];
      if (wide) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 6, pad, 28),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: hero),
            const SizedBox(width: 20),
            Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards)),
          ]),
        );
      }
      return ListView(padding: EdgeInsets.fromLTRB(pad, 6, pad, 28), children: [hero, const SizedBox(height: 12), ...cards]);
    });
  }
}

class _PartsView extends StatefulWidget {
  final Instrument inst;
  const _PartsView({required this.inst});
  @override
  State<_PartsView> createState() => _PartsViewState();
}

class _PartsViewState extends State<_PartsView> {
  int _sel = -1;

  Map<String, Object?> get _state {
    final inst = widget.inst;
    final p = _sel >= 0 ? inst.parts[_sel] : null;
    return {
      'needle': inst.analog ? 0.0 : null,
      'knob': inst.knob.isNotEmpty ? inst.knob[0].angle : 0,
      'lcd': inst.key == 'dmm' || inst.key == 'clamp' ? const Lcd('8.8.8.8', '', ac: true, dc: true, auto: true, hold: true).toJson() : null,
      'highlight': p == null ? null : {'node': p.node, 'label': p.nameAr},
      'pip': false,
    };
  }

  void _tap(String name) {
    final i = widget.inst.parts.indexWhere((p) => p.node == name);
    if (i >= 0) {
      AudioService.instance.sfx('part_select', volume: 0.5);
      setState(() => _sel = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final view = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Inst3D(instrument: inst.key, state: _state, onTap: _tap, image: inst.image),
    );
    final info = _sel < 0
        ? const Text('دوس على أي جزء في المجسم أو من القايمة يتشرحلك. لف الجهاز بصباعك، وكبّر وصغّر.', style: TextStyle(color: CC.text2, fontSize: 14, height: 1.5))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inst.parts[_sel].nameAr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: CC.accentSoft)),
            const SizedBox(height: 6),
            Text(inst.parts[_sel].about, style: const TextStyle(fontSize: 14.5, height: 1.6)),
          ]);
    final chips = Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < inst.parts.length; i++) Pill(label: '${i + 1}. ${inst.parts[i].nameAr}', selected: _sel == i, onTap: () => _tap(inst.parts[i].node)),
    ]);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: view),
            const SizedBox(width: 14),
            SizedBox(
              width: 390,
              child: Glass(radius: 20, padding: const EdgeInsets.all(14), child: ListView(children: [info, const SizedBox(height: 14), chips])),
            ),
          ]),
        );
      }
      return Column(children: [
        Expanded(flex: 6, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: view)),
        Expanded(
          flex: 5,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 20), children: [info, const SizedBox(height: 12), chips]),
        ),
      ]);
    });
  }
}

// ======================================================================= the live bench
class LiveLab extends StatefulWidget {
  final Instrument inst;
  const LiveLab({super.key, required this.inst});
  @override
  State<LiveLab> createState() => _LiveLabState();
}

class _LiveLabState extends State<LiveLab> {
  late InstState s = InstState(widget.inst);
  late Bench bench = _makeBench(widget.inst.benches.first);
  final cam = Inst3DController();
  Timer? _timer;
  final _clock = Stopwatch()..start();
  double _last = 0;
  Reading r = const Reading();
  TaskRun? run;
  String? active; // the lead the next probe tap moves
  String? _danger;
  String _dangerKey = '';
  int _sparkN = 0;
  String? _sparkAt;
  bool _wasBeep = false, _wasLed = false, _wasFinished = false;
  String _shownWords = '';

  Bench _makeBench(String k) => k == 'motor' ? MotorBench() : BoardBench();

  @override
  void initState() {
    super.initState();
    active = s.leads.first.def.id;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    _recompute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- the clock
  void _tick() {
    final now = _clock.elapsedMilliseconds / 1000;
    final dt = (now - _last).clamp(0.0, 0.2);
    _last = now;
    bench.tick(dt);
    if (s.test) s.testSince += dt;
    _recompute(fromTick: true);
  }

  void _recompute({bool fromTick = false}) {
    // the low-impedance paths the instrument puts across the bench now
    bench.bridges.clear();
    final cur = _currentBridge();
    if (cur != null) bench.bridges.add(cur);
    final nr = readInstrument(s, bench);
    final changed = nr.words != _shownWords || nr.hint != r.hint || nr.danger != r.danger;
    r = nr;
    // a mistake: once per new arrangement
    final key = '${s.knob}|${[for (final l in s.leads) '${l.jack}@${l.at}'].join(',')}|${bench.switches}|${s.test}';
    if (nr.danger != null && key != _dangerKey) {
      _dangerKey = key;
      _danger = nr.danger;
      if (nr.short) {
        _sparkN++;
        _sparkAt = s.leads.firstWhere((l) => l.at != null, orElse: () => s.leads.first).at;
        AudioService.instance.sfx('short_circuit_bang');
        if (widget.inst.key == 'avo' || widget.inst.key == 'dmm') s.fuseBlown = true;
      } else {
        AudioService.instance.sfx('error_buzz', volume: 0.6);
      }
    }
    if (nr.danger == null && key != _dangerKey) _dangerKey = '';
    if (nr.beep && !_wasBeep) AudioService.instance.sfx('meter_beep', volume: 0.7);
    _wasBeep = nr.beep;
    if (nr.led && !_wasLed) AudioService.instance.sfx('buzzer', volume: 0.35);
    _wasLed = nr.led;
    var taskChanged = false;
    if (run != null) {
      taskChanged = run!.update(Ctx(s, bench, nr));
      if (run!.finished && !_wasFinished) AudioService.instance.sfx('lift_ding', volume: 0.7);
      _wasFinished = run!.finished;
    }
    if (!fromTick || changed || taskChanged || _animating) {
      _shownWords = nr.words;
      if (mounted) setState(() {});
    }
  }

  /// state that changes every tick (needle creeping, inrush) needs the 3D page updated
  bool get _animating => s.test || (bench is BoardBench && (bench as BoardBench).motorRuns) || r.jitter > 0;

  (String, String)? _currentBridge() {
    // an ammeter (multimeter on a current jack) or the wattmeter current coil
    switch (widget.inst.key) {
      case 'avo':
      case 'dmm':
        final red = ['10a', 'ma'].map(s.inJack).whereType<LeadState>().firstOrNull;
        final com = s.inJack('com');
        final ok = widget.inst.key == 'avo' ? (s.inJack('10a') != null || s.pos?.mode == Mode.dcma) : true;
        final redAt = red?.at ?? (widget.inst.key == 'avo' && s.pos?.mode == Mode.dcma ? s.at('v') : null);
        if (ok && redAt != null && com?.at != null) return (redAt, com!.at!);
        return null;
      case 'watt':
        final a = s.at('ia'), b = s.at('i5');
        if (a != null && b != null) return (a, b);
        return null;
    }
    return null;
  }

  // ---------------------------------------------------------------- the 3D state
  Map<String, Object?> get _state3d {
    final inst = widget.inst;
    final p = s.pos;
    final pts = <Map<String, Object?>>[];
    final usesLeads = s.leads.any((l) => l.jack != null);
    if (inst.key != 'clamp' || usesLeads) {
      for (final t in bench.points) {
        pts.add({'id': t.id, 'label': t.label, 'hot': s.leads.any((l) => l.at == t.id)});
      }
    }
    if (inst.key == 'clamp') {
      for (final e in bench.clamps.entries) {
        pts.add({'id': e.key, 'label': e.value, 'hot': s.clampAt == e.key});
      }
    }
    return {
      ...bench.view3d(),
      'needle': inst.analog ? (r.needle ?? 0) : null,
      'jitter': r.jitter,
      'slow': r.slow,
      'knob': p?.angle ?? 0,
      'lcd': inst.key == 'dmm' || inst.key == 'clamp' ? (r.lcd?.toJson() ?? {'on': false}) : null,
      'led': r.led,
      'test': s.test,
      'testLock': s.testLock,
      'ohmAdj': s.ohmZeroed ? 1.0 : 0.0,
      'clampAt': s.clampAt,
      'jaw': 0.0,
      'pip': true,
      'leads': [
        for (final l in s.leads) {'id': l.def.id, 'color': l.def.color, 'kind': l.def.kind, if (l.def.cable != null) 'cable': l.def.cable, 'jack': l.jack, 'at': l.jack == null ? null : l.at}
      ],
      'points': pts,
      'run': bench is MotorBench ? ((bench as MotorBench).runs ? 1.0 : 0.0) : ((bench as BoardBench).motorRuns ? 0.0 : 0.0),
      'spark': {'n': _sparkN, 'at': _sparkAt},
    };
  }

  // ---------------------------------------------------------------- actions
  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));
  }

  String _jackColor(String jack) {
    if (widget.inst.key == 'watt') return jack;
    return const {'com': 'black', 'earth': 'black'}[jack] ?? 'red';
  }

  void _jackTap(String jack) {
    if (!widget.inst.jacks.any((j) => j.id == jack)) return;
    final there = s.inJack(jack);
    if (there != null) {
      there.jack = null;
      there.at = null;
      AudioService.instance.sfx('pushbutton_click', volume: 0.5);
    } else {
      LeadState? lead;
      if (widget.inst.key == 'watt') {
        lead = s.lead(jack);
      } else {
        final col = _jackColor(jack);
        lead = s.leads.where((l) => l.def.color == col && l.jack == null).firstOrNull ?? s.leads.where((l) => l.def.color == col).firstOrNull;
      }
      if (lead == null) return;
      lead.jack = jack;
      active = lead.def.id;
      AudioService.instance.sfx('din_rail_click', volume: 0.6);
    }
    _recompute();
  }

  void _pointTap(String id) {
    final lead = s.leads.where((l) => l.def.id == active).firstOrNull;
    if (lead == null) return;
    if (lead.jack == null) {
      _toast('ركّب ${lead.def.nameAr} في الجهاز الأول (دوس على المدخل في الجهاز أو من "التوصيل").');
      return;
    }
    if (lead.at == id) {
      lead.at = null;
    } else {
      lead.at = id;
      s.shorted = false;
      // the next tap moves the other lead
      final next = s.leads.where((l) => l != lead && l.jack != null && l.at == null).firstOrNull;
      if (next != null) active = next.def.id;
    }
    AudioService.instance.sfx('screw_tighten', volume: 0.25);
    _recompute();
  }

  void _clampTap(String id) {
    s.clampAt = s.clampAt == id ? null : id;
    AudioService.instance.sfx('assemble_snap', volume: 0.5);
    _recompute();
  }

  void _switch(String k) {
    final on = !(bench.switches[k] ?? false);
    if (bench is BoardBench) {
      (bench as BoardBench).setSwitch(k, on);
    } else {
      bench.switches[k] = on;
    }
    AudioService.instance.sfx(on ? 'mcb_on' : 'mcb_trip', volume: 0.7);
    _recompute();
  }

  void _toggleLink() {
    final b = bench;
    if (b is! BoardBench) return;
    final liveNow = b.on('Q3') && !b.bridges.contains(('pt_X2_L', 'pt_X2_Lo'));
    b.linkX2 = !b.linkX2;
    if (!b.linkX2 && liveNow) {
      _sparkN++;
      _sparkAt = 'pt_X2_Lo';
      AudioService.instance.sfx('arc_crackle');
      _danger = 'فكيت الكوبري والسخان شغال: شرارة! اقفل القاطع Q3 الأول، وبعدين فك أو ركّب الكوبري.';
    } else {
      AudioService.instance.sfx('screw_tighten', volume: 0.5);
    }
    _recompute();
  }

  void _setKnob(int i) {
    if (i == s.knob) return;
    final was = s.pos;
    s.knob = i;
    final now = s.pos;
    if (now != null && (now.mode == Mode.ohm || now.mode == Mode.buzz) && (was?.range != now.range || was?.mode != now.mode) && widget.inst.key == 'avo') s.ohmZeroed = false;
    if (now?.mode != Mode.ins) {
      s.test = false;
      s.testLock = false;
    }
    AudioService.instance.sfx('selector_detent', volume: 0.6);
    _recompute();
  }

  void _setTest(bool on, {bool lock = false}) {
    if (s.pos?.mode != Mode.ins) {
      if (on) _toast('اختار جهد الاختبار الأول (250V أو 500V أو 1000V).');
      return;
    }
    if (on && !s.test) s.testSince = 0;
    s.test = on;
    s.testLock = on && lock;
    if (on) AudioService.instance.sfx('pushbutton_click', volume: 0.6);
    _recompute();
  }

  void _onTap(String name) {
    if (name.startsWith('pt_')) return _pointTap(name);
    if (name.startsWith('clamp_')) return _clampTap(name);
    if (name.startsWith('tog_')) return _switch(name);
    if (name == 'link_X2') return _toggleLink();
    if (name.startsWith('links_') && bench is MotorBench) return _cycleLinks();
    if (name.startsWith('jack_')) return _jackTap(name.substring(5));
    if (name.startsWith('post_')) return _jackTap(name.substring(5));
    switch (name) {
      case 'knob':
        if (widget.inst.knob.isNotEmpty) _setKnob((s.knob + 1) % widget.inst.knob.length);
        return;
      case 'test':
        return _setTest(!s.test, lock: true);
      case 'hold':
      case 'buttons':
        s.hold = !s.hold;
        AudioService.instance.sfx('pushbutton_click', volume: 0.5);
        _recompute();
        return;
      case 'ohm_adj':
        return _zeroOhm();
      case 'zero_screw':
        _toast('ضبط الصفر الميكانيكي: الإبرة واقفة على الصفر بالظبط، مش محتاجة ضبط.');
        return;
    }
    final p = widget.inst.parts.where((p) => p.node == name).firstOrNull;
    if (p != null) _toast('${p.nameAr}: ${p.about}');
  }

  void _zeroOhm() {
    if (widget.inst.key != 'avo') return;
    if (!(s.pos?.mode == Mode.ohm || s.pos?.mode == Mode.buzz)) {
      _toast('ضبط صفر الأوم بيتعمل على رينجات الأوم بس.');
      return;
    }
    if (!s.shorted) {
      _toast('لمّس المجسين في بعض الأول (زرار "لمّس المجسين")، وبعدين لف 0Ω ADJ.');
      return;
    }
    s.ohmZeroed = true;
    AudioService.instance.sfx('selector_detent', volume: 0.5);
    _recompute();
  }

  void _cycleLinks() {
    final m = bench as MotorBench;
    if (m.supply) {
      _toast('اقفل المفتاح المحلي الأول! ممنوع تفك الكباري والمحرك فيه كهربا.');
      return;
    }
    m.links = switch (m.links) { 'star' => 'none', 'none' => 'delta', _ => 'star' };
    AudioService.instance.sfx('screw_tighten', volume: 0.5);
    _recompute();
  }

  void _setLinks(String v) {
    final m = bench as MotorBench;
    if (m.supply && v != m.links) {
      _toast('اقفل المفتاح المحلي الأول! ممنوع تفك الكباري والمحرك فيه كهربا.');
      return;
    }
    m.links = v;
    AudioService.instance.sfx('screw_tighten', volume: 0.5);
    _recompute();
  }

  void _useBench(String k) {
    if (bench.key == k) return;
    setState(() {
      bench = _makeBench(k);
      for (final l in s.leads) {
        l.at = null;
      }
      s.clampAt = null;
      s.test = false;
      _danger = null;
      if (run != null && run!.task.bench != k) run = null;
    });
    _recompute();
  }

  void _startTask(Task t) {
    setState(() {
      if (bench.key != t.bench) {
        bench = _makeBench(t.bench);
        for (final l in s.leads) {
          l.at = null;
        }
        s.clampAt = null;
      }
      if (bench is MotorBench) (bench as MotorBench).fault = MotorFault.none;
      t.setup?.call(s, bench);
      run = TaskRun(t);
      _wasFinished = false;
      _danger = null;
    });
    _recompute();
  }

  void _resetLeads() {
    for (final l in s.leads) {
      l.jack = null;
      l.at = null;
    }
    s.clampAt = null;
    s.test = false;
    s.shorted = false;
    active = s.leads.first.def.id;
    _recompute();
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final view = Stack(fit: StackFit.expand, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Inst3D(instrument: inst.key, bench: bench.key, mount: inst.mount, state: _state3d, onTap: _onTap, controller: cam, image: inst.image),
      ),
      Positioned(left: 10, right: 10, bottom: 10, child: _ReadoutBar(r: r, danger: _danger, onCloseDanger: () => setState(() => _danger = null))),
    ]);
    final panel = _panel();
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Row(children: [
            Expanded(child: view),
            const SizedBox(width: 12),
            SizedBox(width: 400, child: Glass(radius: 20, padding: EdgeInsets.zero, child: panel)),
          ]),
        );
      }
      return Column(children: [
        SizedBox(height: c.maxHeight * 0.56, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: view)),
        Expanded(child: panel),
      ]);
    });
  }

  Widget _panel() {
    final inst = widget.inst;
    final ts = tasksFor(inst.key);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 24), children: [
      if (inst.benches.length > 1) ...[
        const _Label('المكان'),
        Wrap(spacing: 0, children: [
          for (final b in inst.benches) Pill(label: b == 'board' ? 'لوحة التوزيع' : 'المحرك', selected: bench.key == b, onTap: () => _useBench(b)),
        ]),
        const SizedBox(height: 8),
      ],
      const _Label('الكاميرا'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, t) in bench is BoardBench
              ? const [('all', 'اللوحة كلها'), ('top', 'المفاتيح'), ('terminals', 'الترامل'), ('cable', 'كابل المحرك'), ('meter', 'الجهاز')]
              : const [('all', 'الكل'), ('tbox', 'علبة الترامل'), ('iso', 'المفتاح المحلي'), ('meter', 'الجهاز')])
            Pill(label: t, selected: false, onTap: () => cam.focus(k)),
        ]),
      ),
      const SizedBox(height: 10),
      _taskCard(ts),
      const SizedBox(height: 10),
      if (inst.knob.isNotEmpty) ...[
        _Label(inst.key == 'megger' ? 'مفتاح الوظيفة وجهد الاختبار' : 'مفتاح الوظيفة والرينج'),
        Wrap(spacing: 0, runSpacing: 6, children: [
          for (var i = 0; i < inst.knob.length; i++) Pill(label: inst.knob[i].label, selected: s.knob == i, onTap: () => _setKnob(i)),
        ]),
        const SizedBox(height: 10),
      ],
      _instrumentButtons(),
      const _Label('التوصيل (دوس على المدخل في الجهاز أو هنا)'),
      for (final l in s.leads) _leadRow(l),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: _resetLeads, icon: const CcIcon(CcIcons.reset, size: 18), label: const Text('فك كل الكابلات')),
      ),
      const SizedBox(height: 6),
      _benchControls(),
    ]);
  }

  Widget _taskCard(List<Task> ts) {
    final avail = ts;
    return Container(
      decoration: BoxDecoration(color: const Color(0x140F2150), borderRadius: BorderRadius.circular(16), border: Border.all(color: CC.amberLine)),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CcIcon(CcIcons.list, size: 18, color: CC.accentSoft),
          const SizedBox(width: 6),
          const Expanded(child: Text('تجارب موجَّهة', style: TextStyle(fontWeight: FontWeight.w700, color: CC.accentSoft))),
          if (run != null) TextButton(onPressed: () => setState(() => run = null), child: const Text('تجربة حرة')),
        ]),
        if (run == null) ...[
          const Text('اختار تجربة وامشي على خطواتها، أو جرّب بحرية.', style: TextStyle(fontSize: 12.5, color: CC.muted)),
          const SizedBox(height: 6),
          for (final t in avail)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _startTask(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(children: [
                  CcIcon(t.bench == 'motor' ? CcIcons.spark : CcIcons.bolt, size: 18, color: CC.cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(t.bench == 'motor' ? 'على المحرك' : 'على لوحة التوزيع', style: const TextStyle(fontSize: 11.5, color: CC.muted)),
                    ]),
                  ),
                  const CcIcon(CcIcons.back, size: 16, color: CC.muted),
                ]),
              ),
            ),
        ] else ...[
          Text(run!.task.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(run!.task.intro, style: const TextStyle(fontSize: 13, color: CC.text2, height: 1.45)),
          const SizedBox(height: 6),
          for (var i = 0; i < run!.task.steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: run!.done[i] ? CC.green : Colors.transparent, border: Border.all(color: run!.done[i] ? CC.green : CC.line2, width: 1.5)),
                  child: run!.done[i] ? const Icon(Icons.check, size: 14, color: CC.bg) : Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 10.5, color: CC.muted))),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(run!.task.steps[i].text, style: TextStyle(fontSize: 13.5, height: 1.4, color: run!.done[i] ? CC.text : CC.text2))),
              ]),
            ),
          if (run!.finished)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0x2235E08A), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x8835E08A))),
              child: Text('✓ ممتاز! ${run!.task.success}', style: const TextStyle(fontSize: 13.5, height: 1.5)),
            ),
        ],
      ]),
    );
  }

  Widget _instrumentButtons() {
    final inst = widget.inst;
    final btns = <Widget>[];
    if (inst.key == 'megger') {
      btns.add(GestureDetector(
        onTapDown: (_) => _setTest(true),
        onTapUp: (_) {
          if (!s.testLock) _setTest(false);
        },
        onTapCancel: () {
          if (!s.testLock) _setTest(false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: s.test ? CC.red : const Color(0x33FF5A64), borderRadius: BorderRadius.circular(99), border: Border.all(color: CC.red)),
          child: Text(s.test ? 'TEST شغال… ${s.testSince.toStringAsFixed(0)} ث' : 'دوس مطوّل: TEST', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ));
      btns.add(Pill(label: s.testLock ? 'فك القفل' : 'TEST مقفول', selected: s.testLock, onTap: () => _setTest(!s.testLock, lock: true)));
    }
    if (inst.key == 'avo') {
      btns.add(Pill(label: s.shorted ? 'المجسين ملموسين ✓' : 'لمّس المجسين', selected: s.shorted, onTap: () {
        setState(() => s.shorted = !s.shorted);
        _recompute();
      }));
      btns.add(Pill(label: 'لف 0Ω ADJ', selected: s.ohmZeroed, onTap: _zeroOhm));
    }
    if (inst.key == 'dmm' || inst.key == 'clamp') {
      btns.add(Pill(label: 'HOLD', selected: s.hold, onTap: () {
        s.hold = !s.hold;
        _recompute();
      }));
    }
    if (inst.key == 'dmm') {
      btns.add(Pill(label: s.shorted ? 'المجسين ملموسين ✓' : 'لمّس المجسين', selected: s.shorted, onTap: () {
        s.shorted = !s.shorted;
        _recompute();
      }));
    }
    if (inst.key == 'clamp' && s.clampAt != null) {
      btns.add(Pill(label: 'شيل الكلامب', selected: false, onTap: () => _clampTap(s.clampAt!)));
    }
    if (s.fuseBlown) {
      btns.add(Pill(label: 'غيّر الفيوز', selected: true, onTap: () {
        s.fuseBlown = false;
        _danger = null;
        _recompute();
      }));
    }
    if (btns.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: btns));
  }

  Widget _leadRow(LeadState l) {
    final inst = widget.inst;
    final color = l.def.color == 'red' ? const Color(0xFFE5484D) : (l.def.cable == 'blue' ? const Color(0xFF3D6BFF) : const Color(0xFF9AA4B8));
    final isActive = active == l.def.id;
    final jacks = inst.key == 'watt' ? inst.jacks.where((j) => j.id == l.def.id) : inst.jacks.where((j) => _jackColor(j.id) == l.def.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: isActive ? const Color(0x223D8BFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? CC.amber : CC.line),
      ),
      child: InkWell(
        onTap: () => setState(() => active = l.def.id),
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.def.nameAr + (isActive ? '  ← الضغطة الجاية على نقطة' : ''), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                  l.jack == null
                      ? 'مش متركب'
                      : 'في ${inst.jacks.firstWhere((j) => j.id == l.jack).label}${l.at != null ? ' · على ${bench.label(l.at!)}' : ' · مش على حاجة'}',
                  style: const TextStyle(fontSize: 11.5, color: CC.muted)),
            ]),
          ),
          for (final j in jacks)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (l.jack == j.id) {
                    _jackTap(j.id);
                  } else {
                    final other = s.inJack(j.id);
                    if (other != null) {
                      other.jack = null;
                      other.at = null;
                    }
                    l.jack = j.id;
                    active = l.def.id;
                    AudioService.instance.sfx('din_rail_click', volume: 0.6);
                    _recompute();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: l.jack == j.id ? CC.amber : CC.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: CC.line2)),
                  child: Text(j.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: l.jack == j.id ? Colors.white : CC.text2, fontFamily: CC.mono)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _benchControls() {
    final b = bench;
    if (b is BoardBench) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('اللوحة (أو دوس على ذراع القاطع في المجسم)'),
        Wrap(spacing: 0, runSpacing: 6, children: [
          for (final (k, t) in const [('tog_main', 'الرئيسي'), ('tog_Q1', 'Q1 المحرك'), ('tog_Q2', 'Q2 الإنارة'), ('tog_Q3', 'Q3 السخان')])
            Pill(label: '$t: ${(b.switches[k] ?? false) ? 'شغال' : 'مقفول'}', selected: b.switches[k] ?? false, onTap: () => _switch(k)),
          Pill(label: b.linkX2 ? 'كوبري X2: متركب' : 'كوبري X2: متفكوك', selected: !b.linkX2, onTap: _toggleLink),
        ]),
        const SizedBox(height: 8),
        Text('حمل المحرك: ${(b.motorLoad * 100).round()}%  ·  تيار الخط ≈ ${b.motorRuns ? b.motorAmps.toStringAsFixed(1) : '0'} أمبير', style: const TextStyle(fontSize: 12.5, color: CC.text2)),
        Slider(value: b.motorLoad, onChanged: (v) {
          b.motorLoad = v;
          _recompute();
        }),
        const _Label('حمل الدائرة X2'),
        Wrap(children: [
          for (final h in HeaterLoad.values)
            Pill(label: h.nameAr, selected: b.heater == h, onTap: () {
              b.heater = h;
              _recompute();
            }),
        ]),
      ]);
    }
    final m = b as MotorBench;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Label('المحرك'),
      Wrap(spacing: 0, runSpacing: 6, children: [
        Pill(label: 'المفتاح المحلي: ${m.supply ? 'شغال' : 'مقفول'}', selected: m.supply, onTap: () => _switch('tog_iso')),
      ]),
      const SizedBox(height: 8),
      const _Label('الكباري في علبة الترامل'),
      Wrap(children: [
        for (final (k, t) in const [('star', 'نجمة Y'), ('delta', 'دلتا Δ'), ('none', 'متفكوكة')]) Pill(label: t, selected: m.links == k, onTap: () => _setLinks(k)),
      ]),
      const SizedBox(height: 8),
      const _Label('حالة المحرك (للتدريب على اكتشاف الأعطال)'),
      Wrap(spacing: 0, runSpacing: 6, children: [
        for (final f in MotorFault.values)
          Pill(label: f.nameAr, selected: m.fault == f, onTap: () {
            m.fault = f;
            _recompute();
          }),
      ]),
    ]);
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 6, top: 2), child: Text(text, style: const TextStyle(fontSize: 12.5, color: CC.muted, fontWeight: FontWeight.w600)));
}

class _ReadoutBar extends StatelessWidget {
  final Reading r;
  final String? danger;
  final VoidCallback onCloseDanger;
  const _ReadoutBar({required this.r, required this.danger, required this.onCloseDanger});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (danger != null)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: const Color(0xE6501018), borderRadius: BorderRadius.circular(14), border: Border.all(color: CC.red)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: CcIcon(CcIcons.warning, size: 20, color: CC.gold)),
            const SizedBox(width: 8),
            Expanded(child: Text(danger!, style: const TextStyle(fontSize: 13, height: 1.45))),
            IconButton(onPressed: onCloseDanger, icon: const Icon(Icons.close, size: 18), visualDensity: VisualDensity.compact),
          ]),
        ),
      IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(color: const Color(0xD90A1226), borderRadius: BorderRadius.circular(14), border: Border.all(color: CC.glassBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(r.words.isEmpty ? '—' : r.words, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (r.hint != null) Text(r.hint!, style: const TextStyle(fontSize: 12.5, color: CC.gold, height: 1.4)),
          ]),
        ),
      ),
    ]);
  }
}
