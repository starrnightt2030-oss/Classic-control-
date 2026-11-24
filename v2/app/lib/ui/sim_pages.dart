import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/audio_service.dart';
import '../sim/circuits.dart';
import '../sim/engine.dart';
import 'icons.dart';
import 'section_pages.dart';
import 'theme.dart';
import 'widgets.dart';

/// «محاكي الدوائر»: the 17 circuits grouped, each opens a live simulation.
class CircuitListPage extends StatelessWidget {
  const CircuitListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Circuit>>{};
    for (final c in kCircuits) {
      (groups[c.group] ??= []).add(c);
    }
    var n = 0;
    return SectionScaffold(
      title: 'محاكي الدوائر',
      child: LayoutBuilder(builder: (context, box) {
        final pad = box.maxWidth >= 900 ? 28.0 : 16.0;
        final cols = box.maxWidth >= 1100 ? 3 : box.maxWidth >= 700 ? 2 : 1;
        return ListView(padding: EdgeInsets.fromLTRB(pad, 6, pad, 28), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: panelBox(color: CC.cyanBg, border: CC.cyanLine, radius: 14),
            child: const Text(
              'كل دائرة موصّلة توصيلًا صحيحًا وجاهزة للتشغيل: ارفع التغذية، واضغط الضواغط، وراقب الكونتاكتورات والمؤقتات والمحرك، ونفّذ المهام بالترتيب. '
              'وفي المرحلة التالية يظهر المخطط الكلاسيكي حيًّا بجانب المحاكي، ثم معمل اللوحة لتوصيل الأسلاك بنفسك.',
              style: TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFCDF3F8)),
            ),
          ),
          for (final g in groups.entries) ...[
            const SizedBox(height: 18),
            SectionTitle(g.key),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cols == 1 ? 3.4 : 2.6,
              children: [
                for (final c in g.value)
                  _CircuitTile(
                    number: ++n,
                    circuit: c,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircuitSimPage(circuit: c))),
                  ),
              ],
            ),
          ],
        ]);
      }),
    );
  }
}

class _CircuitTile extends StatelessWidget {
  final int number;
  final Circuit circuit;
  final VoidCallback onTap;
  const _CircuitTile({required this.number, required this.circuit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x12FFFFFF),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: CC.glassBorder)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: panelBox(color: CC.amberBg, border: CC.amberLine, radius: 10),
              child: Text('$number', style: const TextStyle(fontFamily: CC.mono, fontWeight: FontWeight.w700, color: CC.amber)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(circuit.short, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(circuit.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: CC.muted, height: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class CircuitSimPage extends StatefulWidget {
  final Circuit circuit;
  const CircuitSimPage({super.key, required this.circuit});

  @override
  State<CircuitSimPage> createState() => _CircuitSimPageState();
}

class _CircuitSimPageState extends State<CircuitSimPage> with SingleTickerProviderStateMixin {
  late Lab lab;
  late List<bool> done;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _running = true;

  Circuit get c => widget.circuit;

  @override
  void initState() {
    super.initState();
    _reset();
    _ticker = createTicker(_onTick)..start();
  }

  void _reset() {
    lab = c.build();
    done = List.filled(c.tasks.length, false);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = now;
    if (!_running || !mounted) return;
    lab.step(dt);
    _afterChange();
  }

  void _afterChange() {
    _handleEvents(lab.drain());
    final i = done.indexOf(false);
    if (i >= 0 && c.tasks[i].done(lab)) {
      done[i] = true;
      AudioService.instance.sfx(done.every((d) => d) ? 'success_fanfare' : 'success_chime');
    }
    if (mounted) setState(() {});
  }

  void _handleEvents(List<SimEvent> evs) {
    final a = AudioService.instance;
    for (final e in evs) {
      switch (e.t) {
        case 'kon':
          a.sfx(e.data['type'] == 'kc' ? 'contactor_pull_in' : 'relay_click');
        case 'koff':
          a.sfx(e.data['type'] == 'kc' ? 'contactor_drop_out' : 'relay_click');
        case 'tsw':
          a.sfx('timer_tick');
        case 'trip':
          a.sfx('mcb_trip');
          _toast('فصل القاطع ${e.id}${e.data['why'] == 'short' ? ' بسبب قصر' : ''}.');
        case 'short':
          a.sfx('short_circuit_bang');
        case 'mainTrip':
          _toast('قصر لم يفصله أي قاطع، فانقطعت التغذية الرئيسية.');
        case 'oltrip':
          a.sfx('overload_trip');
          _toast('فصل الأوفرلود ${e.id}. ابحث عن السبب قبل إعادة الضبط.');
        case 'olhot':
          a.sfx('soft_fail');
          _toast('الأوفرلود ما زال ساخنًا. انتظر قليلًا ثم أعد الضبط.');
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
            _toast('فقد فاز: المحرك يطنّ ولا يدور.');
          }
        case 'chatter':
          _toast('الدائرة غير مستقرة: الكونتاكتور يفتح ويغلق باستمرار.');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  void _act(String id, String what, [bool val = true]) {
    lab.actuate(id, what, val);
    _afterChange();
  }

  void _power() {
    AudioService.instance.sfx('mcb_on');
    lab.setPower(!lab.power);
    _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: c.short,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 980;
        final pad = wide ? 24.0 : 14.0;
        final left = [
          _panelHeader(),
          const SizedBox(height: 12),
          _stations(),
          const SizedBox(height: 12),
          _motors(),
          if (lab.track != null) ...[const SizedBox(height: 12), _track()],
        ];
        final right = [
          _devices(),
          const SizedBox(height: 12),
          _tasks(),
          const SizedBox(height: 12),
          _about(),
        ];
        if (wide) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 6, pad, 28),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 6, child: Column(children: left)),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: Column(children: right)),
            ]),
          );
        }
        return ListView(padding: EdgeInsets.fromLTRB(pad, 6, pad, 28), children: [...left, const SizedBox(height: 12), ...right]);
      }),
    );
  }

  // --------------------------------------------------------------- sections
  Widget _box({required String title, required Widget child, Widget? trailing}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: panelBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: SectionTitle(title)), if (trailing != null) trailing]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _panelHeader() {
    final on = lab.power;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: panelBox(color: on ? CC.amberBg : CC.surface, border: on ? CC.amberLine : CC.line),
      child: Row(children: [
        CcIcon(CcIcons.bolt, color: on ? CC.amber : CC.muted, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? 'التغذية موصولة' : 'التغذية مفصولة', style: TextStyle(fontWeight: FontWeight.w700, color: on ? CC.amber : CC.text2)),
            const Text('ثلاثي الأطوار 380 فولت، ودائرة التحكم 220 فولت', style: TextStyle(fontSize: 12, color: CC.muted)),
          ]),
        ),
        for (final id in ['Q1', 'F1'])
          if (lab.byId(id) != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: _Breaker(comp: lab[id], onTap: () {
                AudioService.instance.sfx('mcb_on');
                _act(id, 'mcb');
              }),
            ),
        const SizedBox(width: 10),
        Switch(value: on, onChanged: (_) => _power()),
      ]),
    );
  }

  Widget _stations() {
    final st = lab.comps.where((x) => x.t.station).toList();
    return _box(
      title: 'الضواغط ولمبات البيان',
      trailing: IconButton(
        tooltip: 'إعادة الدائرة',
        onPressed: () => setState(_reset),
        icon: const CcIcon(CcIcons.reset, color: CC.muted, size: 22),
      ),
      child: Wrap(spacing: 14, runSpacing: 14, children: [
        for (final s in st)
          if (s.type == 'lamp') _Lamp(comp: s) else _PushButton(comp: s, onPress: (v) => _act(s.id, s.type == 'estop' ? 'estop' : 'press', v)),
      ]),
    );
  }

  Widget _motors() {
    final ms = lab.comps.where((x) => x.type == 'motor').toList();
    return _box(
      title: ms.length > 1 ? 'المحركات' : 'المحرك',
      child: Wrap(spacing: 12, runSpacing: 12, children: [for (final m in ms) _MotorView(comp: m)]),
    );
  }

  Widget _track() {
    final tr = lab.track!;
    return _box(
      title: 'مسار العربة',
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(builder: (context, b) {
          final w = b.maxWidth;
          final x = 8 + (w - 76) * tr.x; // LTR track drawn left→right regardless of text direction
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 40, child: Container(height: 4, color: CC.line2)),
              for (final (id, at) in [(tr.left, 0.0), (tr.right, 1.0)])
                Positioned(
                  left: at == 0 ? 0 : null,
                  right: at == 1 ? 0 : null,
                  top: 6,
                  child: GestureDetector(
                    onTapDown: (_) => _act(id, 'ls', true),
                    onTapUp: (_) => _act(id, 'ls', false),
                    onTapCancel: () => _act(id, 'ls', false),
                    child: Column(children: [
                      Text(id, style: TextStyle(fontFamily: CC.mono, fontSize: 11, color: lab[id].s.act ? CC.amber : CC.muted)),
                      Container(width: 10, height: 26, color: lab[id].s.act ? CC.amber : CC.line2),
                    ]),
                  ),
                ),
              Positioned(
                left: x,
                top: 18,
                child: Container(
                  width: 60,
                  height: 22,
                  decoration: BoxDecoration(color: CC.cyan.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: const Text('العربة', style: TextStyle(fontSize: 11, color: CC.bg, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _devices() {
    final ks = lab.comps.where((x) => x.type == 'kc' || x.type == 'relay' || x.type == 'timer').toList();
    final ols = lab.comps.where((x) => x.type == 'ol').toList();
    return _box(
      title: 'الكونتاكتورات والمؤقتات والحماية',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [for (final k in ks) _CoilChip(comp: k, onTime: (d) => setState(() => k.p['T'] = (k.num_('T') + d).clamp(1.0, 30.0)))]),
        if (ols.isNotEmpty) const SizedBox(height: 12),
        for (final o in ols) _OverloadRow(comp: o, onTest: () => _act(o.id, 'oltest'), onReset: () => _act(o.id, 'olreset')),
      ]),
    );
  }

  Widget _tasks() {
    final cur = done.indexOf(false);
    return _box(
      title: 'المهام',
      trailing: Text('${done.where((d) => d).length}/${done.length}', style: const TextStyle(fontFamily: CC.mono, color: CC.amber)),
      child: Column(children: [
        for (var i = 0; i < c.tasks.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done[i] ? CC.green : (i == cur ? CC.amberBg : CC.surface2),
                  border: Border.all(color: done[i] ? CC.green : (i == cur ? CC.amber : CC.line)),
                ),
                child: done[i]
                    ? const Icon(Icons.check, size: 16, color: CC.bg)
                    : Text('${i + 1}', style: TextStyle(fontSize: 11, fontFamily: CC.mono, color: i == cur ? CC.amber : CC.muted)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c.tasks[i].text,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: done[i] ? CC.muted : (i == cur ? CC.text : CC.text2),
                        fontWeight: i == cur ? FontWeight.w700 : FontWeight.w400)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _about() => _box(
        title: c.title,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c.desc, style: const TextStyle(fontSize: 14, height: 1.75, color: CC.text2)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: panelBox(color: CC.goldBg, border: CC.goldLine, radius: 12),
            child: Text(c.tip, style: const TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFFFE2A8))),
          ),
        ]),
      );
}

// --------------------------------------------------------------- widgets
Color _lampColor(String? col) => switch (col) {
      'r' => const Color(0xFFFF4B3E),
      'y' => const Color(0xFFFFC21A),
      'b' => const Color(0xFF3D8BFF),
      'w' => const Color(0xFFF2F4F6),
      _ => const Color(0xFF2FE07A),
    };

class _Lamp extends StatelessWidget {
  final Comp comp;
  const _Lamp({required this.comp});
  @override
  Widget build(BuildContext context) {
    final lit = comp.s.v > 150 && !comp.s.dead;
    final col = _lampColor(comp.p['col'] as String?);
    return SizedBox(
      width: 74,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? col : Color.lerp(col, Colors.black, 0.72),
            border: Border.all(color: const Color(0xFF0B0F14), width: 4),
            boxShadow: lit ? [BoxShadow(color: col.withValues(alpha: 0.65), blurRadius: 22, spreadRadius: 2)] : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(comp.id, style: const TextStyle(fontFamily: CC.mono, fontSize: 11, color: CC.muted)),
        Text(comp.label ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: CC.text2)),
      ]),
    );
  }
}

class _PushButton extends StatelessWidget {
  final Comp comp;
  final ValueChanged<bool> onPress;
  const _PushButton({required this.comp, required this.onPress});
  @override
  Widget build(BuildContext context) {
    final estop = comp.type == 'estop';
    final down = estop ? comp.s.lat : comp.s.pr;
    final col = estop ? const Color(0xFFD22B2B) : _lampColor(comp.p['col'] as String?);
    final size = estop ? 58.0 : 50.0;
    return SizedBox(
      width: 78,
      child: Column(children: [
        Listener(
          onPointerDown: (_) {
            AudioService.instance.sfx(estop ? 'estop_latch' : 'pushbutton_click');
            onPress(true);
          },
          onPointerUp: (_) {
            if (!estop) onPress(false);
          },
          onPointerCancel: (_) {
            if (!estop) onPress(false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: down ? Color.lerp(col, Colors.black, 0.25) : col,
              border: Border.all(color: estop ? const Color(0xFFF2C200) : const Color(0xFF9AA4AC), width: estop ? 6 : 4),
              boxShadow: down ? null : const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(comp.id, style: const TextStyle(fontFamily: CC.mono, fontSize: 11, color: CC.muted)),
        Text(comp.label ?? (estop ? 'طوارئ' : ''), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: CC.text2)),
      ]),
    );
  }
}

class _Breaker extends StatelessWidget {
  final Comp comp;
  final VoidCallback onTap;
  const _Breaker({required this.comp, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final on = comp.s.on;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: panelBox(color: on ? CC.surface2 : const Color(0xFF2A1414), border: on ? CC.line2 : CC.red, radius: 8),
        child: Column(children: [
          Text(comp.id, style: const TextStyle(fontFamily: CC.mono, fontSize: 12, fontWeight: FontWeight.w700)),
          Text(comp.s.trip ? 'فصل' : (on ? 'I' : 'O'), style: TextStyle(fontSize: 11, color: on ? CC.green : CC.red)),
        ]),
      ),
    );
  }
}

class _CoilChip extends StatelessWidget {
  final Comp comp;
  final ValueChanged<double> onTime;
  const _CoilChip({required this.comp, required this.onTime});
  @override
  Widget build(BuildContext context) {
    final s = comp.s;
    final timer = comp.type == 'timer';
    final on = s.on;
    final active = timer ? s.sw : on;
    final border = s.dead ? CC.red : (active ? CC.green : (on ? CC.amber : CC.line));
    String state;
    if (s.dead) {
      state = 'محترق';
    } else if (s.blocked) {
      state = 'ممنوع بالتداخل';
    } else if (s.hum) {
      state = 'يطنّ';
    } else if (timer) {
      state = on ? (s.sw ? 'انتهى الزمن' : 'يعدّ') : (s.sw ? 'يعدّ للفصل' : 'مفصول');
    } else {
      state = on ? 'جاذب' : 'مفصول';
    }
    final tm = timer ? comp.num_('T') : 0.0;
    final frac = timer && tm > 0 ? (s.el / tm).clamp(0.0, 1.0).toDouble() : 0.0;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: panelBox(color: active ? const Color(0xFF0F2A1B) : CC.surface2, border: border, radius: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(comp.id, style: const TextStyle(fontFamily: CC.mono, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? CC.green : (on ? CC.amber : CC.line2))),
        ]),
        Text(comp.t.nameAr + (timer ? (comp.p['mode'] == 'off' ? ' (تأخير الفصل)' : ' (تأخير التوصيل)') : ''),
            style: const TextStyle(fontSize: 11.5, color: CC.muted)),
        Text(state, style: TextStyle(fontSize: 12.5, color: s.dead || s.hum ? CC.red : CC.text2, fontWeight: FontWeight.w600)),
        if (timer) ...[
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: frac, minHeight: 5, color: CC.amber, backgroundColor: CC.line)),
          Row(children: [
            _mini('−', () => onTime(-1)),
            Expanded(child: Text('${tm.toStringAsFixed(0)} ث', textAlign: TextAlign.center, style: const TextStyle(fontFamily: CC.mono, fontSize: 12))),
            _mini('+', () => onTime(1)),
          ]),
        ],
      ]),
    );
  }

  Widget _mini(String t, VoidCallback f) => InkWell(
        onTap: f,
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Text(t, style: const TextStyle(fontSize: 18, color: CC.amber))),
      );
}

class _OverloadRow extends StatelessWidget {
  final Comp comp;
  final VoidCallback onTest, onReset;
  const _OverloadRow({required this.comp, required this.onTest, required this.onReset});
  @override
  Widget build(BuildContext context) {
    final s = comp.s;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: panelBox(color: s.trip ? const Color(0xFF2A1414) : CC.surface2, border: s.trip ? CC.red : CC.line, radius: 12),
        child: Row(children: [
          SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${comp.id} أوفرلود', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(s.trip ? 'فاصل' : 'جاهز', style: TextStyle(fontSize: 12, color: s.trip ? CC.red : CC.green)),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('الحرارة ${(s.heat / 1.5).round()}٪ · الضبط ${comp.num_('set')} أمبير',
                  style: const TextStyle(fontSize: 11.5, color: CC.muted)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: (s.heat / 150).clamp(0.0, 1.0).toDouble(), minHeight: 6, color: s.heat > 100 ? CC.red : CC.amber, backgroundColor: CC.line),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onTest, child: const Text('TEST')),
          TextButton(onPressed: onReset, child: const Text('RESET')),
        ]),
      ),
    );
  }
}

class _MotorView extends StatelessWidget {
  final Comp comp;
  const _MotorView({required this.comp});

  static const _modes = {
    'off': 'متوقف',
    'star': 'يعمل بتوصيلة ستار',
    'delta': 'يعمل بتوصيلة دلتا',
    'single': 'فقد فاز',
    'over': 'جهد زائد على الملفات',
    'dead': 'محترق',
  };

  @override
  Widget build(BuildContext context) {
    final s = comp.s;
    final running = s.mode == 'star' || s.mode == 'delta';
    final bad = s.mode == 'single' || s.mode == 'over' || s.mode == 'dead';
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: panelBox(color: CC.surface2, border: bad ? CC.red : (running ? CC.green : CC.line), radius: 12),
      child: Row(children: [
        Transform.rotate(
          angle: s.ang * 3.14159265 / 180,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF26323E), border: Border.all(color: CC.line2, width: 3)),
            child: CustomPaint(painter: _FanPainter(running ? CC.cyan : CC.muted)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(comp.id, style: const TextStyle(fontFamily: CC.mono, fontWeight: FontWeight.w700)),
            Text(_modes[s.mode] ?? s.mode, style: TextStyle(fontSize: 12.5, color: bad ? CC.red : (running ? CC.green : CC.text2), fontWeight: FontWeight.w600)),
            if (running) Text(s.dir == 1 ? 'مع عقارب الساعة ↻' : 'عكس عقارب الساعة ↺', style: const TextStyle(fontSize: 11.5, color: CC.muted)),
            Text('السرعة ${(s.spd * 100).round()}٪ · التيار ${s.current.toStringAsFixed(1)} أمبير',
                style: const TextStyle(fontSize: 11.5, color: CC.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _FanPainter extends CustomPainter {
  final Color color;
  _FanPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final a = i * 2.0943951;
      canvas.drawLine(c, c + Offset.fromDirection(a, size.width * 0.36), p);
    }
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFFDDE3E8));
  }

  @override
  bool shouldRepaint(covariant _FanPainter old) => old.color != color;
}
