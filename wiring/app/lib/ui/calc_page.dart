import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'viewer3d.dart';

const _breakers = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100];
// copper PVC in conduit, two loaded conductors (approximate, IEC 60364-5-52 method B2)
final _cables = <double, double>{1.5: 16.5, 2.5: 23, 4: 30, 6: 38, 10: 52, 16: 69, 25: 90, 35: 111};
const _rho = 0.0175; // Ω·mm²/m copper at ~20 °C
const _v = 220.0;

int breakerFor(double amps) => _breakers.firstWhere((b) => b >= amps, orElse: () => _breakers.last);
double cableFor(double amps) => _cables.entries.firstWhere((e) => e.value >= amps, orElse: () => _cables.entries.last).key;
String _f(num x, [int d = 1]) => x % 1 == 0 && d <= 1 ? x.toInt().toString() : x.toStringAsFixed(d);
String _mm(double a) => a % 1 == 0 ? a.toInt().toString() : a.toString();

class CalcPage extends StatelessWidget {
  const CalcPage();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('kwh_meter', 'حساب الأحمال', 'الشقة كلها: الدواير والقواطع والكابل الرئيسي بالقوانين', const LoadCalc()),
      ('coil_brown', 'مقاس الكابل', 'من التيار والطول وهبوط الجهد', const CableCalc()),
      ('conduit', 'مقاس الماسورة', 'عدد الأسلاك ومقاسها ونسبة الملء', const ConduitCalc()),
      ('mcb_1p', 'اختيار القاطع', 'من قدرة الجهاز ونوع الحمل', const BreakerCalc()),
      ('earth_rod', 'مقاومة الأرضي', 'عمود تأريض في التربة', const EarthCalc()),
      ('multimeter', 'هبوط الجهد', 'نسبة الفقد في الخط', const DropCalc()),
    ];
    return PageFrame(
      title: 'الحاسبات الهندسية',
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, mainAxisExtent: 210, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return GlowCard(
            padding: const EdgeInsets.all(8),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageFrame(title: it.$2, body: it.$4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  // same blue as the studio renders, so the picture has no visible edge
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: kRenderBg),
                  child: ModelPicture(it.$1),
                ),
              ),
              const SizedBox(height: 6),
              Text(it.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(it.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.dim)),
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers
class _Field extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final int div;
  final String unit;
  final ValueChanged<double> onChanged;
  const _Field(this.label, this.value, this.min, this.max, this.unit, this.onChanged, {this.div = 100});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(label), const Spacer(), Text('${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(2)} $unit', style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700))]),
          Slider(value: value.clamp(min, max), min: min, max: max, divisions: div, onChanged: onChanged),
        ]),
      );
}

class _Result extends StatelessWidget {
  final List<(String, String)> rows;
  const _Result(this.rows);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: glowCard(r: 16, border: C.gold),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('النتيجة', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [Expanded(child: Text(r.$1, style: const TextStyle(color: C.dim))), Text(r.$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.goldHi))]),
            ),
        ]),
      );
}

/// One step of a worked solution: the rule, the numbers put in, and why.
class CalcStep {
  final String title;
  final String formula; // Latin only, shown LTR
  final String sub; // the same formula with the numbers
  final String why;
  final bool ok;
  const CalcStep(this.title, this.formula, this.sub, this.why, {this.ok = true});
}

class _Steps extends StatelessWidget {
  final List<CalcStep> steps;
  const _Steps(this.steps);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: glowCard(r: 16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.functions, color: C.gold),
            title: const Text('الحل خطوة بخطوة', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('القانون، والتعويض بالأرقام، وليه اخترنا كده', style: TextStyle(fontSize: 12, color: C.dim)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [for (var i = 0; i < steps.length; i++) _step(i + 1, steps[i])],
          ),
        ),
      );

  Widget _step(int n, CalcStep s) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.navy0.withValues(alpha: .55), borderRadius: BorderRadius.circular(12), border: Border.all(color: s.ok ? Colors.white12 : C.bad)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 12, backgroundColor: s.ok ? C.gold : C.bad, child: Text('$n', style: const TextStyle(color: C.navy0, fontWeight: FontWeight.w800, fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF041029), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.formula, style: const TextStyle(color: C.goldHi, fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                if (s.sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(s.sub, style: const TextStyle(color: C.text, fontSize: 13.5, fontFamily: 'monospace', height: 1.4)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(s.ok ? Icons.lightbulb_outline : Icons.error_outline, size: 16, color: s.ok ? C.glow : C.bad),
            const SizedBox(width: 6),
            Expanded(child: Text(s.why, style: const TextStyle(fontSize: 12.5, height: 1.55, color: C.dim))),
          ]),
        ]),
      );
}

Widget _wrap(List<Widget> c) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.all(16), children: c)));

Widget _h(String t) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.gold)));

// -------------------------------------------------------------- load calc
enum LoadCat { light, socket, fixed, ac }

const _catName = {LoadCat.light: 'إنارة', LoadCat.socket: 'برايز عامة', LoadCat.fixed: 'أجهزة ثابتة', LoadCat.ac: 'تكييف'};
// demand factors used for the whole flat (teaching values, close to common Egyptian practice)
const _kd = {LoadCat.light: .9, LoadCat.socket: .5, LoadCat.fixed: .75, LoadCat.ac: 1.0};
const _kdWhy = {
  LoadCat.light: 'الإنارة بالليل بتكون مولعة أغلبها مع بعض، فبناخد 90%.',
  LoadCat.socket: 'البرايز كتير بس مش كلها شغالة: شاحن هنا وتلفزيون هناك، فبناخد 50%.',
  LoadCat.fixed: 'السخان والغسالة والفرن نادر يشتغلوا كلهم في نفس اللحظة، فبناخد 75%.',
  LoadCat.ac: 'في الصيف كل التكييفات بتشتغل مع بعض، فمفيش تخفيض: 100%.',
};

class LoadItem {
  final String name;
  final int watts;
  final LoadCat cat;
  final bool motor;
  int qty;
  LoadItem(this.name, this.watts, this.cat, this.qty, {this.motor = false});
}

class LoadCircuit {
  final String name;
  final double watts;
  final bool motor;
  final double cosPhi;
  LoadCircuit(this.name, this.watts, {this.motor = false, this.cosPhi = 1});
  double get ib => watts / (_v * cosPhi);
  int get inA => math.max(minBreaker, breakerFor(ib));
  int get minBreaker => name.startsWith('إنارة') ? 10 : 16;
  double get cable => cableFor(inA.toDouble());
}

/// Everything the load page shows, computed in one place so tests can check it.
class LoadResult {
  final double installed, demand, ib, cosPhi, feederDrop, feederLen;
  final Map<LoadCat, double> byCat;
  final List<LoadCircuit> circuits;
  final int mainBreaker, rccb;
  final double feeder;
  final bool threePhase;
  LoadResult(this.installed, this.demand, this.ib, this.cosPhi, this.byCat, this.circuits, this.mainBreaker, this.feeder, this.feederDrop, this.feederLen, this.rccb, this.threePhase);
}

LoadResult computeLoad(List<LoadItem> items, {double cosPhi = .9, double feederLen = 15}) {
  final byCat = {for (final c in LoadCat.values) c: 0.0};
  for (final it in items) {
    byCat[it.cat] = byCat[it.cat]! + it.watts * it.qty;
  }
  final installed = byCat.values.fold(0.0, (a, b) => a + b);
  final demand = LoadCat.values.fold(0.0, (a, c) => a + byCat[c]! * _kd[c]!);
  final ib = demand / (_v * cosPhi);

  // circuits: lighting up to 1500 W each, sockets up to 3000 W each, every big load on its own
  final circuits = <LoadCircuit>[];
  final light = byCat[LoadCat.light]!;
  final nl = math.max(1, (light / 1500).ceil());
  for (var i = 0; i < nl && light > 0; i++) {
    circuits.add(LoadCircuit('إنارة ${i + 1}', light / nl));
  }
  final sock = byCat[LoadCat.socket]!;
  final ns = math.max(1, (sock / 3000).ceil());
  for (var i = 0; i < ns && sock > 0; i++) {
    circuits.add(LoadCircuit('برايز ${i + 1}', sock / ns, cosPhi: .9));
  }
  for (final it in items.where((e) => e.cat == LoadCat.fixed || e.cat == LoadCat.ac)) {
    for (var k = 0; k < it.qty; k++) {
      circuits.add(LoadCircuit(it.qty > 1 ? '${it.name} ${k + 1}' : it.name, it.watts.toDouble(), motor: it.motor, cosPhi: it.motor ? .85 : 1));
    }
  }

  // main breaker: Ib × 1.25 for future loads, then the next standard size
  final main = breakerFor(ib * 1.25);
  // feeder: Iz ≥ In, then check the drop (keep the feeder under 1% so circuits get the rest of the 4%)
  var feeder = cableFor(main.toDouble());
  double drop(double a) => 2 * feederLen * ib * _rho / a / _v * 100;
  while (drop(feeder) > 1 && feeder < _cables.keys.last) {
    feeder = _cables.keys.firstWhere((a) => a > feeder);
  }
  final rccb = main <= 25 ? 25 : main <= 40 ? 40 : 63;
  return LoadResult(installed, demand, ib, cosPhi, byCat, circuits, main, feeder, drop(feeder), feederLen, rccb, demand > 11000);
}

class LoadCalc extends StatefulWidget {
  const LoadCalc();
  @override
  State<LoadCalc> createState() => _LoadCalcState();
}

class _LoadCalcState extends State<LoadCalc> {
  final items = <LoadItem>[
    LoadItem('لمبات LED', 12, LoadCat.light, 20),
    LoadItem('نجفة / سبوتات', 60, LoadCat.light, 2),
    LoadItem('بريزة عامة (تلفزيون، شاحن، كمبيوتر)', 200, LoadCat.socket, 10),
    LoadItem('تلاجة', 250, LoadCat.socket, 1, motor: true),
    LoadItem('مكواة', 1200, LoadCat.socket, 1),
    LoadItem('ميكروويف', 1200, LoadCat.socket, 1),
    LoadItem('سخان كهربي', 3000, LoadCat.fixed, 1),
    LoadItem('غسالة أوتوماتيك', 2000, LoadCat.fixed, 1, motor: true),
    LoadItem('فرن كهربي', 2500, LoadCat.fixed, 0),
    LoadItem('تكييف 1.5 حصان', 1500, LoadCat.ac, 1, motor: true),
    LoadItem('تكييف 2.25 حصان', 2200, LoadCat.ac, 0, motor: true),
    LoadItem('تكييف 3 حصان', 3000, LoadCat.ac, 0, motor: true),
  ];
  double cosPhi = .9, len = 15;

  @override
  Widget build(BuildContext context) {
    final r = computeLoad(items, cosPhi: cosPhi, feederLen: len);
    final cats = LoadCat.values.where((c) => r.byCat[c]! > 0).toList();
    String sumOf(LoadCat c) => items.where((e) => e.cat == c && e.qty > 0).map((e) => '${e.qty}×${e.watts}').join(' + ');
    final steps = <CalcStep>[
      CalcStep(
        'القدرة المركبة: مجموع كل الأجهزة',
        'P = Σ n × P_device',
        '${[for (final c in cats) '${sumOf(c)} = ${_f(r.byCat[c]!)} W'].join('\n')}\nP = ${_f(r.installed)} W = ${_f(r.installed / 1000, 2)} kW',
        'ده الحمل لو كل حاجة اشتغلت في نفس الوقت. مش هنصمم عليه مباشرة لأنه مبالغ فيه وهيكبّر القاطع والكابل من غير داعي.',
      ),
      CalcStep(
        'القدرة المطلوبة: نضرب كل نوع في معامل الطلب Kd',
        'Pd = Σ Kd × P',
        '${[for (final c in cats) '${_kd[c]} × ${_f(r.byCat[c]!)} = ${_f(_kd[c]! * r.byCat[c]!)} W'].join('\n')}\nPd = ${_f(r.demand)} W',
        [for (final c in cats) '${_catName[c]}: ${_kdWhy[c]}'].join('\n'),
      ),
      CalcStep(
        'تيار الحمل الكلي Ib',
        'Ib = Pd ÷ (V × cosφ)',
        'Ib = ${_f(r.demand)} ÷ (220 × $cosPhi) = ${_f(r.ib)} A',
        'الجهد في مصر 220 V بين الفاز والنيوترال. معامل القدرة cosφ أقل من 1 لأن الموتورات (تكييف، تلاجة، غسالة) بتسحب تيار زيادة عن القدرة الفعلية، فبناخد 0.9 للشقة.',
      ),
      CalcStep(
        'القاطع الرئيسي In',
        'In ≥ 1.25 × Ib',
        '1.25 × ${_f(r.ib)} = ${_f(r.ib * 1.25)} A  →  In = ${r.mainBreaker} A',
        'بنزود 25% احتياطي لأي جهاز هيدخل الشقة بعدين، وبعدين بناخد أقرب مقاس قياسي أكبر (6، 10، 16، 20، 25، 32، 40، 50، 63 A). القاطع الرئيسي منحنى C عشان تيار بدء الموتورات ميفصلوش.',
      ),
      CalcStep(
        'كابل التغذية من العداد للوحة',
        'Iz ≥ In',
        'In = ${r.mainBreaker} A  →  ${_mm(r.feeder)} mm²  (Iz = ${_f(_cables[r.feeder]!)} A)',
        'سعة الكابل Iz لازم تكون أكبر من أو تساوي القاطع اللي بيحميه. لو القاطع أكبر من الكابل، الكابل هيسخن ويحترق قبل ما القاطع يفصل.',
      ),
      CalcStep(
        'مراجعة هبوط الجهد في كابل التغذية',
        'ΔV% = 2 × L × Ib × ρ ÷ (A × V) × 100',
        '2 × ${_f(len)} × ${_f(r.ib)} × 0.0175 ÷ (${_mm(r.feeder)} × 220) × 100 = ${_f(r.feederDrop, 2)} %',
        'الكود بيسمح بحوالي 4% من العداد لآخر جهاز. بنخلي كابل التغذية تحت 1% عشان يفضل الباقي للدواير الفرعية. لو زاد، البرنامج بيكبّر المقطع تلقائي.',
        ok: r.feederDrop <= 1,
      ),
      CalcStep(
        'مفتاح التسريب RCCB',
        'IΔn = 30 mA ,  In(RCCB) ≥ In(main)',
        'In(main) = ${r.mainBreaker} A  →  RCCB 2P ${r.rccb} A / 30 mA',
        '30 mA هي الحساسية اللي بتحمي الإنسان من الصعق. تيار المفتاح لازم يكون أكبر من أو يساوي القاطع اللي قبله، لأن المفتاح نفسه مش بيحمي من الحمل الزيادة.',
      ),
      CalcStep(
        'نوع العداد',
        'Pd ≤ 11 kW → 1-phase',
        'Pd = ${_f(r.demand / 1000, 2)} kW  →  ${r.threePhase ? '3-phase' : '1-phase'}',
        r.threePhase ? 'الحمل كبير على وجه واحد، اطلب عداد 3 فاز ووزع الدواير على الوجوه التلاتة بالتساوي.' : 'عداد وجه واحد كفاية. لو الحمل زاد عن حوالي 11 kW يبقى عداد 3 فاز أحسن.',
      ),
    ];
    return _wrap([
      const Text('حدد عدد كل جهاز في الشقة. هنقسم الأحمال لدواير، ونختار قاطع وسلك كل دايرة، وبعدين القاطع الرئيسي وكابل التغذية، وكل خطوة بقانونها وسببها.', style: TextStyle(color: C.dim, height: 1.5)),
      for (final c in LoadCat.values) ...[
        _h(_catName[c]!),
        for (final it in items.where((e) => e.cat == c))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: glowCard(r: 12),
            child: Row(children: [
              Expanded(child: Text('${it.name}  (${it.watts} W)')),
              IconButton(onPressed: () => setState(() => it.qty = math.max(0, it.qty - 1)), icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(width: 28, child: Text('${it.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => setState(() => it.qty++), icon: const Icon(Icons.add_circle_outline, color: C.gold)),
            ]),
          ),
      ],
      const SizedBox(height: 8),
      _Field('معامل القدرة cosφ', cosPhi, .8, 1, '', (v) => setState(() => cosPhi = (v * 100).round() / 100), div: 20),
      _Field('طول كابل التغذية (عداد ← لوحة)', len, 3, 60, 'م', (v) => setState(() => len = v.roundToDouble()), div: 57),
      _Result([
        ('القدرة المركبة', '${_f(r.installed / 1000, 2)} kW'),
        ('القدرة المطلوبة', '${_f(r.demand / 1000, 2)} kW'),
        ('تيار الحمل Ib', '${_f(r.ib)} A'),
        ('القاطع الرئيسي', '${r.mainBreaker} A  C'),
        ('كابل التغذية', '${_mm(r.feeder)} مم²'),
        ('مفتاح التسريب', '${r.rccb} A / 30 mA'),
        ('عدد الدواير', '${r.circuits.length}'),
      ]),
      _Steps(steps),
      _h('جدول الدواير (اللوحة)'),
      _circuitTable(r),
      const SizedBox(height: 8),
      const Text(
        'ليه الدواير كده؟ الإنارة دايرة 10 A بسلك 1.5 مم² (لحد حوالي 1500 W). البرايز العامة 16 A بسلك 2.5 مم² (لحد حوالي 3000 W). السخان والغسالة والفرن وكل تكييف ليهم دايرة لوحدهم عشان دول أحمال كبيرة وبتشتغل وقت طويل، ولو فصلت دايرة متقطعش النور عن البيت كله.',
        style: TextStyle(fontSize: 12.5, height: 1.6, color: C.dim),
      ),
    ]);
  }

  Widget _circuitTable(LoadResult r) {
    const hs = TextStyle(fontWeight: FontWeight.w800, color: C.gold, fontSize: 12.5);
    const cs = TextStyle(fontSize: 12.5);
    return Container(
      decoration: glowCard(r: 14),
      padding: const EdgeInsets.all(8),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1.2), 4: FlexColumnWidth(1)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          const TableRow(children: [Text('الدايرة', style: hs), Text('P (W)', style: hs), Text('Ib (A)', style: hs), Text('القاطع', style: hs), Text('السلك', style: hs)]),
          for (final c in r.circuits)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(c.name, style: cs)),
              Text(_f(c.watts.round()), style: cs),
              Text(_f(c.ib), style: cs),
              Text('${c.inA} A ${c.motor ? 'C' : 'B'}', style: cs.copyWith(color: C.goldHi, fontWeight: FontWeight.w700)),
              Text('${_mm(c.cable)} مم²', style: cs),
            ]),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- cable calc
class CableCalc extends StatefulWidget {
  const CableCalc();
  @override
  State<CableCalc> createState() => _CableCalcState();
}

class _CableCalcState extends State<CableCalc> {
  double watts = 3000, length = 20, maxDrop = 3;
  @override
  Widget build(BuildContext context) {
    final amps = watts / _v;
    final inA = breakerFor(amps);
    final byCurrent = cableFor(inA.toDouble());
    final needA = 2 * length * amps * _rho / (_v * maxDrop / 100);
    final byDrop = _cables.keys.firstWhere((a) => a >= needA, orElse: () => 35);
    final size = math.max(byCurrent, byDrop);
    final drop = 2 * length * amps * _rho / size;
    return _wrap([
      _Field('قدرة الحمل', watts, 100, 12000, 'W', (v) => setState(() => watts = (v / 100).round() * 100.0), div: 119),
      _Field('طول الخط (ذهاب)', length, 1, 100, 'م', (v) => setState(() => length = v.roundToDouble()), div: 99),
      _Field('أقصى هبوط جهد', maxDrop, 1, 5, '%', (v) => setState(() => maxDrop = v), div: 8),
      _Result([
        ('التيار Ib', '${_f(amps)} A'),
        ('القاطع In', '$inA A'),
        ('المقاس حسب التيار', '${_mm(byCurrent)} مم²'),
        ('المقاس حسب هبوط الجهد', '${_mm(byDrop)} مم²'),
        ('المقاس المختار', '${_mm(size)} مم²'),
        ('هبوط الجهد الفعلي', '${drop.toStringAsFixed(1)} V (${(drop / 2.2).toStringAsFixed(1)}%)'),
      ]),
      _Steps([
        CalcStep('تيار الحمل', 'Ib = P ÷ V', 'Ib = ${_f(watts)} ÷ 220 = ${_f(amps)} A', 'أول حاجة بنعرف السلك هيشيل كام أمبير.'),
        CalcStep('القاطع', 'In ≥ Ib', '${_f(amps)} A  →  In = $inA A', 'أقرب مقاس قياسي أكبر من تيار الحمل، عشان القاطع ميفصلش في التشغيل العادي.'),
        CalcStep('الشرط الأول: سعة السلك', 'Iz ≥ In', 'In = $inA A  →  ${_mm(byCurrent)} mm² (Iz = ${_f(_cables[byCurrent]!)} A)', 'السلك لازم يستحمل تيار أكبر من القاطع، وإلا هيسخن قبل ما القاطع يحس بالمشكلة.'),
        CalcStep('الشرط التاني: هبوط الجهد', 'A ≥ 2 × L × Ib × ρ ÷ ΔV', 'A ≥ 2 × ${_f(length)} × ${_f(amps)} × 0.0175 ÷ ${_f(_v * maxDrop / 100, 1)} = ${needA.toStringAsFixed(2)} mm²  →  ${_mm(byDrop)} mm²', 'الرقم 2 لأن التيار رايح في الفاز وراجع في النيوترال. كل ما الخط يطول السلك لازم يتخن عشان الجهاز يوصله جهد كفاية.'),
        CalcStep('نختار الأكبر', 'A = max(A_current, A_drop)', 'max(${_mm(byCurrent)}, ${_mm(byDrop)}) = ${_mm(size)} mm²', 'لازم السلك يحقق الشرطين مع بعض، فبناخد الأكبر منهم.'),
      ]),
      const Text('الأرقام تقريبية لنحاس معزول PVC جوه ماسورة في الحيطة، وفيه سلكين محملين (فاز ونيوترال).', style: TextStyle(fontSize: 12, color: C.dim)),
    ]);
  }
}

// ------------------------------------------------------------ conduit calc
class ConduitCalc extends StatefulWidget {
  const ConduitCalc();
  @override
  State<ConduitCalc> createState() => _ConduitCalcState();
}

class _ConduitCalcState extends State<ConduitCalc> {
  double n = 3;
  double size = 2.5;
  static final _od = <double, double>{1.5: 3.0, 2.5: 3.6, 4: 4.2, 6: 4.8, 10: 6.1, 16: 7.2};
  static const _conduits = <int, double>{16: 13.0, 20: 16.9, 25: 21.4, 32: 27.8, 40: 35.4};
  @override
  Widget build(BuildContext context) {
    final d = _od[size]!;
    final one = math.pi * d * d / 4;
    final area = n * one;
    final pick = _conduits.entries.firstWhere((e) => math.pi * e.value * e.value / 4 * .4 >= area, orElse: () => _conduits.entries.last);
    final inner = math.pi * pick.value * pick.value / 4;
    final fill = area / inner * 100;
    return _wrap([
      _Field('عدد الأسلاك', n, 1, 12, 'سلك', (v) => setState(() => n = v.roundToDouble()), div: 11),
      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('مقاس السلك: '),
        for (final s in _od.keys) ChoiceChip(label: Text(_mm(s)), selected: size == s, onSelected: (_) => setState(() => size = s)),
      ]),
      _Result([
        ('مساحة الأسلاك', '${area.toStringAsFixed(0)} مم²'),
        ('الماسورة المقترحة', '${pick.key} مم'),
        ('نسبة الملء', '${fill.toStringAsFixed(0)}%'),
      ]),
      _Steps([
        CalcStep('مساحة السلك الواحد بالعزل', 'a = π × d² ÷ 4', 'a = 3.14 × ${_f(d)}² ÷ 4 = ${one.toStringAsFixed(1)} mm²', 'بنحسب بالقطر الخارجي للسلك (النحاس + العزل)، مش بالمقطع ${_mm(size)} مم² المكتوب عليه.'),
        CalcStep('مساحة كل الأسلاك', 'A = n × a', 'A = ${_f(n)} × ${one.toStringAsFixed(1)} = ${area.toStringAsFixed(0)} mm²', 'كل الأسلاك اللي هتعدي في نفس الماسورة، شامل الأرضي.'),
        CalcStep('الماسورة', 'A ≤ 40% × A_conduit', '${area.toStringAsFixed(0)} ≤ 0.4 × ${inner.toStringAsFixed(0)}  →  ${pick.key} mm', 'الـ 60% الفاضية عشان السلك يتسحب من غير ما العزل يتقشر، وعشان الحرارة تطلع، وعشان تقدر تزود أو تغير سلك بعدين. القطر الداخلي للماسورة ${pick.key} مم حوالي ${_f(pick.value)} مم.', ok: fill <= 40),
      ]),
    ]);
  }
}

// ------------------------------------------------------------ breaker calc
class BreakerCalc extends StatefulWidget {
  const BreakerCalc();
  @override
  State<BreakerCalc> createState() => _BreakerCalcState();
}

class _BreakerCalcState extends State<BreakerCalc> {
  double watts = 2000;
  bool motor = false;
  @override
  Widget build(BuildContext context) {
    final cos = motor ? .85 : 1.0;
    final amps = watts / (_v * cos);
    final b = breakerFor(amps);
    final cable = cableFor(b.toDouble());
    return _wrap([
      _Field('قدرة الجهاز / الدايرة', watts, 100, 10000, 'W', (v) => setState(() => watts = (v / 100).round() * 100.0), div: 99),
      SwitchListTile(value: motor, onChanged: (v) => setState(() => motor = v), title: const Text('حمل فيه موتور (تكييف، طلمبة، غسالة)')),
      _Result([
        ('تيار التشغيل Ib', '${_f(amps)} A'),
        ('القاطع In', '$b A  منحنى ${motor ? 'C' : 'B'}'),
        ('أقل مقاس سلك', '${_mm(cable)} مم²'),
      ]),
      _Steps([
        CalcStep('تيار التشغيل', 'Ib = P ÷ (V × cosφ)', 'Ib = ${_f(watts)} ÷ (220 × $cos) = ${_f(amps)} A', motor ? 'الموتور معامل قدرته حوالي 0.85، فبيسحب تيار أكبر من القدرة ÷ الجهد.' : 'الأحمال المقاومة (سخان، مكواة، لمبة) معامل قدرتها 1.'),
        CalcStep('القاعدة الذهبية', 'Ib ≤ In ≤ Iz', '${_f(amps)} ≤ $b ≤ ${_f(_cables[cable]!)}', 'القاطع أكبر من تيار الحمل عشان ميفصلش وهو شغال عادي، وأصغر من سعة السلك عشان يفصل قبل ما السلك يسخن.'),
        CalcStep('منحنى الفصل', motor ? 'Istart ≈ 6 × Ib → C (5–10 In)' : 'B (3–5 In)', motor ? '6 × ${_f(amps)} = ${_f(amps * 6)} A < 10 × $b = ${b * 10} A' : '', motor ? 'الموتور بيسحب تيار بدء 5 لـ 7 أضعاف لحظة التشغيل. منحنى C بيستحمل لحد 10 أضعاف لحظياً فمش هيفصل مع كل تشغيلة.' : 'منحنى B بيفصل أسرع مع القصر، ومناسب للإنارة والسخانات والبرايز العادية.'),
      ]),
    ]);
  }
}

// --------------------------------------------------------------- earth calc
class EarthCalc extends StatefulWidget {
  const EarthCalc();
  @override
  State<EarthCalc> createState() => _EarthCalcState();
}

class _EarthCalcState extends State<EarthCalc> {
  double rho = 100, len = 3, rods = 1;
  static const soils = {'طين رطب': 30.0, 'طمي زراعي': 100.0, 'رمل رطب': 300.0, 'رمل ناشف': 1000.0};
  @override
  Widget build(BuildContext context) {
    const d = .016;
    final r1 = rho / (2 * math.pi * len) * math.log(4 * len / d);
    final rn = rods <= 1 ? r1 : r1 / rods * 1.25;
    final touch = rn * .03;
    return _wrap([
      Wrap(spacing: 6, children: [for (final s in soils.entries) ChoiceChip(label: Text(s.key), selected: rho == s.value, onSelected: (_) => setState(() => rho = s.value))]),
      _Field('مقاومية التربة ρ', rho, 10, 1000, 'Ω·م', (v) => setState(() => rho = v.roundToDouble()), div: 99),
      _Field('طول العمود L', len, 1, 6, 'م', (v) => setState(() => len = v), div: 10),
      _Field('عدد الأعمدة', rods, 1, 6, '', (v) => setState(() => rods = v.roundToDouble()), div: 5),
      _Result([
        ('مقاومة عمود واحد', '${r1.toStringAsFixed(1)} Ω'),
        ('المقاومة الكلية', '${rn.toStringAsFixed(1)} Ω'),
        ('الحالة', rn <= 5 ? 'مناسب للمنازل ✓' : 'محتاج تحسين'),
      ]),
      _Steps([
        CalcStep('مقاومة عمود رأسي واحد', 'R1 = ρ ÷ (2πL) × ln(4L ÷ d)', 'R1 = ${_f(rho)} ÷ (2π × ${_f(len)}) × ln(4 × ${_f(len)} ÷ 0.016) = ${r1.toStringAsFixed(1)} Ω', 'd قطر العمود (16 مم). التربة الرطبة والطينية بتوصل الكهربا أحسن فمقاومتها أقل. تطويل العمود بيقلل المقاومة بس بنسبة أقل كل ما تطول.'),
        if (rods > 1) CalcStep('أعمدة على التوازي', 'Rn ≈ R1 ÷ n × 1.25', 'Rn = ${r1.toStringAsFixed(1)} ÷ ${_f(rods)} × 1.25 = ${rn.toStringAsFixed(1)} Ω', 'الأعمدة القريبة من بعض بتأثر على بعض، فالـ 1.25 معامل تقريبي للتداخل. خلي بين كل عمودين مسافة ضعف طول العمود على الأقل.'),
        CalcStep('الشرط مع مفتاح التسريب', 'Ra × IΔn ≤ 50 V', '${rn.toStringAsFixed(1)} × 0.03 = ${touch.toStringAsFixed(2)} V', 'مع مفتاح تسريب 30 mA، أي أرضي تحت 1666 Ω بيحقق الشرط نظرياً، بس الممارسة في المنازل إننا نوصل لـ 5 Ω أو أقل عشان الأرضي يفضل كويس لما التربة تنشف.', ok: rn <= 5),
      ]),
      const Text('تحسين التربة بالبنتونيت أو الفحم والملح حوالين العمود بيقلل المقاومة.', style: TextStyle(fontSize: 12, color: C.dim)),
    ]);
  }
}

// ---------------------------------------------------------------- drop calc
class DropCalc extends StatefulWidget {
  const DropCalc();
  @override
  State<DropCalc> createState() => _DropCalcState();
}

class _DropCalcState extends State<DropCalc> {
  double amps = 16, len = 25, size = 2.5;
  @override
  Widget build(BuildContext context) {
    final r = 2 * len * _rho / size;
    final dv = r * amps;
    final pct = dv / _v * 100;
    return _wrap([
      _Field('التيار', amps, 1, 63, 'A', (v) => setState(() => amps = v.roundToDouble()), div: 62),
      _Field('الطول (ذهاب)', len, 1, 150, 'م', (v) => setState(() => len = v.roundToDouble()), div: 149),
      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('المقطع: '),
        for (final s in _cables.keys) ChoiceChip(label: Text(_mm(s)), selected: size == s, onSelected: (_) => setState(() => size = s)),
      ]),
      _Result([
        ('هبوط الجهد', '${dv.toStringAsFixed(2)} V'),
        ('النسبة', '${pct.toStringAsFixed(2)}%'),
        ('الجهد عند الحمل', '${(_v - dv).toStringAsFixed(1)} V'),
        ('الحكم', pct <= 3 ? 'ممتاز ✓' : pct <= 5 ? 'مقبول للبرايز والأحمال' : 'كبّر المقطع ✗'),
      ]),
      _Steps([
        CalcStep('مقاومة السلك ذهاب وعودة', 'R = 2 × L × ρ ÷ A', 'R = 2 × ${_f(len)} × 0.0175 ÷ ${_mm(size)} = ${r.toStringAsFixed(3)} Ω', 'ρ مقاومية النحاس 0.0175 Ω·mm²/m. الـ 2 لأن الدايرة فيها سلكين: فاز رايح ونيوترال راجع.'),
        CalcStep('هبوط الجهد', 'ΔV = I × R', 'ΔV = ${_f(amps)} × ${r.toStringAsFixed(3)} = ${dv.toStringAsFixed(2)} V', 'قانون أوم: الفرق ده بيضيع حرارة في السلك وميوصلش للجهاز.'),
        CalcStep('النسبة المئوية', 'ΔV% = ΔV ÷ V × 100 ≤ 3–5 %', '${dv.toStringAsFixed(2)} ÷ 220 × 100 = ${pct.toStringAsFixed(2)} %', 'الإنارة حساسة فبنخليها تحت 3%. البرايز والأحمال لحد 5%. لو زادت: كبّر المقطع أو قصّر المسافة أو قسّم الحمل على دايرتين.', ok: pct <= 5),
      ]),
    ]);
  }
}
