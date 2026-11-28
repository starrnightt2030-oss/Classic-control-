import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

const _breakers = [6, 10, 16, 20, 25, 32, 40, 50, 63];
// copper PVC in conduit, two loaded conductors (approximate, IEC 60364-5-52 method B)
final _cables = <double, double>{1.5: 17.5, 2.5: 24, 4: 32, 6: 41, 10: 57, 16: 76, 25: 101, 35: 125};
const _rho = 0.0175; // Ω·mm²/m copper

int breakerFor(double amps) => _breakers.firstWhere((b) => b >= amps, orElse: () => 63);
double cableFor(double amps) => _cables.entries.firstWhere((e) => e.value >= amps, orElse: () => _cables.entries.last).key;

class CalcPage extends StatelessWidget {
  const CalcPage();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('assets/images/calc1.webp', 'حساب الأحمال', 'الشقة كلها: قدرة وتيار وقاطع رئيسي', const LoadCalc()),
      ('assets/images/calc2.webp', 'مقاس الكابل', 'من التيار والطول وهبوط الجهد', const CableCalc()),
      ('assets/images/calc3.webp', 'مقاس الماسورة', 'عدد الأسلاك ومقاسها', const ConduitCalc()),
      ('assets/images/calc4.webp', 'اختيار القاطع', 'من قدرة الجهاز', const BreakerCalc()),
      ('assets/images/calc5.webp', 'مقاومة الأرضي', 'عمود تأريض في التربة', const EarthCalc()),
      ('assets/images/calc6.webp', 'هبوط الجهد', 'نسبة الفقد في الخط', const DropCalc()),
    ];
    return PageFrame(
      title: 'الحاسبات الهندسية',
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, mainAxisExtent: 200, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return GlowCard(
            padding: const EdgeInsets.all(8),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageFrame(title: it.$2, body: it.$4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(it.$1, fit: BoxFit.cover, width: double.infinity))),
              const SizedBox(height: 6),
              Text(it.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(it.$3, style: const TextStyle(fontSize: 11.5, color: C.dim)),
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
          Row(children: [Text(label), const Spacer(), Text('${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(1)} $unit', style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700))]),
          Slider(value: value.clamp(min, max), min: min, max: max, divisions: div, onChanged: onChanged),
        ]),
      );
}

class _Result extends StatelessWidget {
  final List<(String, String)> rows;
  final String? note;
  const _Result(this.rows, {this.note});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: glowCard(r: 16, border: C.gold),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [Expanded(child: Text(r.$1, style: const TextStyle(color: C.dim))), Text(r.$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.goldHi))]),
            ),
          if (note != null) ...[const Divider(color: Colors.white24), Text(note!, style: const TextStyle(fontSize: 12.5, height: 1.5))],
        ]),
      );
}

Widget _wrap(List<Widget> c) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: ListView(padding: const EdgeInsets.all(16), children: c)));

// -------------------------------------------------------------- load calc
class LoadCalc extends StatefulWidget {
  const LoadCalc();
  @override
  State<LoadCalc> createState() => _LoadCalcState();
}

class _LoadCalcState extends State<LoadCalc> {
  final items = <(String, int, int)>[
    ('لمبات LED', 12, 0),
    ('تلاجة', 250, 1),
    ('غسالة', 2000, 1),
    ('سخان كهربي', 3000, 1),
    ('تكييف 1.5 حصان', 1500, 1),
    ('تكييف 2.25 حصان', 2200, 0),
    ('تلفزيون', 150, 2),
    ('مكواة', 1200, 1),
    ('ميكروويف', 1200, 1),
    ('كمبيوتر', 300, 1),
    ('مروحة', 75, 2),
    ('شفاط', 60, 1),
  ];
  final qty = <int>[];
  double diversity = .7;

  @override
  void initState() {
    super.initState();
    qty.addAll(items.map((e) => e.$3));
    qty[0] = 20;
  }

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    for (var i = 0; i < items.length; i++) {
      total += items[i].$2 * qty[i];
    }
    final demand = total * diversity;
    final amps = demand / 220;
    return _wrap([
      const Text('حدد عدد كل جهاز. معامل الطلب بيمثل إن مش كل الأجهزة بتشتغل في نفس الوقت.', style: TextStyle(color: C.dim, height: 1.5)),
      const SizedBox(height: 8),
      for (var i = 0; i < items.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: glowCard(r: 12),
          child: Row(children: [
            Expanded(child: Text('${items[i].$1}  (${items[i].$2} W)')),
            IconButton(onPressed: () => setState(() => qty[i] = math.max(0, qty[i] - 1)), icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(width: 28, child: Text('${qty[i]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => setState(() => qty[i]++), icon: const Icon(Icons.add_circle_outline, color: C.gold)),
          ]),
        ),
      _Field('معامل الطلب', diversity, .4, 1, '', (v) => setState(() => diversity = v), div: 12),
      _Result([
        ('إجمالي القدرة المركبة', '${(total / 1000).toStringAsFixed(2)} kW'),
        ('القدرة المتوقعة', '${(demand / 1000).toStringAsFixed(2)} kW'),
        ('التيار', '${amps.toStringAsFixed(1)} A'),
        ('القاطع الرئيسي المقترح', '${breakerFor(amps * 1.25)} A'),
        ('كابل التغذية المقترح', '${cableFor(amps * 1.25)} مم²'),
      ], note: 'القاطع الرئيسي متختار بهامش 25%. اعمل دايرة مستقلة لكل تكييف وسخان وغسالة.'),
    ]);
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
    final amps = watts / 220;
    final byCurrent = cableFor(amps * 1.25);
    final needA = 2 * length * amps * _rho / (220 * maxDrop / 100);
    final byDrop = _cables.keys.firstWhere((a) => a >= needA, orElse: () => 35);
    final size = math.max(byCurrent, byDrop);
    final drop = 2 * length * amps * _rho / size;
    return _wrap([
      _Field('قدرة الحمل', watts, 100, 12000, 'W', (v) => setState(() => watts = (v / 100).round() * 100.0), div: 119),
      _Field('طول الخط (ذهاب)', length, 1, 100, 'م', (v) => setState(() => length = v.roundToDouble()), div: 99),
      _Field('أقصى هبوط جهد', maxDrop, 1, 5, '%', (v) => setState(() => maxDrop = v), div: 8),
      _Result([
        ('التيار', '${amps.toStringAsFixed(1)} A'),
        ('المقاس حسب التيار', '$byCurrent مم²'),
        ('المقاس حسب هبوط الجهد', '$byDrop مم²'),
        ('المقاس المختار', '$size مم²'),
        ('القاطع', '${breakerFor(amps * 1.1)} A'),
        ('هبوط الجهد الفعلي', '${drop.toStringAsFixed(1)} V (${(drop / 2.2).toStringAsFixed(1)}%)'),
      ], note: 'المقاس الأكبر من الاتنين هو الصح. الأرقام تقريبية لنحاس معزول PVC جوه ماسورة.'),
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
    final area = n * math.pi * d * d / 4;
    final pick = _conduits.entries.firstWhere((e) => math.pi * e.value * e.value / 4 * .4 >= area, orElse: () => _conduits.entries.last);
    final fill = area / (math.pi * pick.value * pick.value / 4) * 100;
    return _wrap([
      _Field('عدد الأسلاك', n, 1, 12, 'سلك', (v) => setState(() => n = v.roundToDouble()), div: 11),
      Wrap(spacing: 6, children: [
        const Text('مقاس السلك: '),
        for (final s in _od.keys) ChoiceChip(label: Text('$s'), selected: size == s, onSelected: (_) => setState(() => size = s)),
      ]),
      _Result([
        ('مساحة الأسلاك', '${area.toStringAsFixed(0)} مم²'),
        ('الماسورة المقترحة', '${pick.key} مم'),
        ('نسبة الملء', '${fill.toStringAsFixed(0)}%'),
      ], note: 'القاعدة: الأسلاك متملاش أكتر من 40% من مساحة الماسورة عشان السحب والتغيير بعدين.'),
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
    final amps = watts / 220;
    final b = breakerFor(amps * 1.15);
    final cable = cableFor(b.toDouble());
    return _wrap([
      _Field('قدرة الجهاز / الدايرة', watts, 100, 10000, 'W', (v) => setState(() => watts = (v / 100).round() * 100.0), div: 99),
      SwitchListTile(value: motor, onChanged: (v) => setState(() => motor = v), title: const Text('حمل فيه موتور (تكييف، طلمبة، غسالة)')),
      _Result([
        ('تيار التشغيل', '${amps.toStringAsFixed(1)} A'),
        ('القاطع', '$b A  منحنى ${motor ? 'C' : 'B أو C'}'),
        ('أقل مقاس سلك', '$cable مم²'),
      ], note: 'القاعدة: تيار الحمل ≤ تيار القاطع ≤ سعة السلك. الموتور بيسحب تيار بدء عالي فبنختار منحنى C.'),
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
    return _wrap([
      Wrap(spacing: 6, children: [for (final s in soils.entries) ChoiceChip(label: Text(s.key), selected: rho == s.value, onSelected: (_) => setState(() => rho = s.value))]),
      _Field('مقاومية التربة', rho, 10, 1000, 'Ω·م', (v) => setState(() => rho = v.roundToDouble()), div: 99),
      _Field('طول العمود', len, 1, 6, 'م', (v) => setState(() => len = v), div: 10),
      _Field('عدد الأعمدة', rods, 1, 6, '', (v) => setState(() => rods = v.roundToDouble()), div: 5),
      _Result([
        ('مقاومة عمود واحد', '${r1.toStringAsFixed(1)} Ω'),
        ('المقاومة الكلية', '${rn.toStringAsFixed(1)} Ω'),
        ('الحالة', rn <= 5 ? 'مناسب للمنازل ✓' : 'محتاج تحسين'),
      ], note: 'المعادلة: R = ρ/(2πL)·ln(4L/d). الأعمدة بينها مسافة ضعف طولها على الأقل. تحسين التربة بالبنتونيت أو الفحم والملح بيقلل المقاومة.'),
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
    final dv = 2 * len * amps * _rho / size;
    final pct = dv / 220 * 100;
    return _wrap([
      _Field('التيار', amps, 1, 63, 'A', (v) => setState(() => amps = v.roundToDouble()), div: 62),
      _Field('الطول (ذهاب)', len, 1, 150, 'م', (v) => setState(() => len = v.roundToDouble()), div: 149),
      Wrap(spacing: 6, children: [
        const Text('المقطع: '),
        for (final s in _cables.keys) ChoiceChip(label: Text('$s'), selected: size == s, onSelected: (_) => setState(() => size = s)),
      ]),
      _Result([
        ('هبوط الجهد', '${dv.toStringAsFixed(2)} V'),
        ('النسبة', '${pct.toStringAsFixed(2)}%'),
        ('الجهد عند الحمل', '${(220 - dv).toStringAsFixed(1)} V'),
        ('الحكم', pct <= 3 ? 'ممتاز ✓' : pct <= 5 ? 'مقبول للبرايز والأحمال' : 'كبّر المقطع ✗'),
      ], note: 'ΔV = 2 × L × I × ρ ÷ A ، و ρ للنحاس = 0.0175 Ω·مم²/م.'),
    ]);
  }
}
