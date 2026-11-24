import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

class Circuit {
  final String id;
  final String title;
  final String subtitle;
  final String powerSvg;
  final String controlSvg;
  final List<(String, String)> legend;
  const Circuit({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.powerSvg,
    required this.controlSvg,
    required this.legend,
  });
}

const dolCircuit = Circuit(
  id: 'dol',
  title: 'تشغيل مباشر بزرارين',
  subtitle: 'DOL Starter · Start / Stop',
  powerSvg: 'assets/diagrams/dol_power.svg',
  controlSvg: 'assets/diagrams/dol_control.svg',
  legend: [
    ('-Q1', 'قاطع حماية الموتور'),
    ('-KM1', 'الكونتاكتور'),
    ('-F2', 'الأوفرلود الحراري'),
    ('-S0', 'زرار الإيقاف (NC)'),
    ('-S1', 'زرار التشغيل (NO)'),
    ('-H1', 'لمبة التشغيل'),
    ('-H2', 'لمبة الفصل الحراري'),
    ('-M1', 'موتور 3 فاز'),
  ],
);

const circuits = [dolCircuit];

class DiagramsPage extends StatelessWidget {
  const DiagramsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 18, pad, 24), children: [
        const Text('المخططات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const Text('مخطط القوى ومخطط التحكم بالرموز الكلاسيك (IEC 60617)', style: TextStyle(fontSize: 13.5, color: CC.muted)),
        const SizedBox(height: 16),
        for (final ci in circuits) ...[
          CircuitCard(
            title: ci.title,
            subtitle: ci.subtitle,
            tag: 'مخطط قوى + تحكم',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagramViewerPage(circuit: ci))),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: panelBox(color: CC.cyanBg, border: CC.cyanLine, radius: 14),
          child: const Text(
            'باقي الدواير (عكس الاتجاه، ستار دلتا، التايمر) والمحاكاة اللي بتشغّل المخطط وتلوّن الجهد هتيجي في المرحلة الجاية.',
            style: TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFCDF3F8)),
          ),
        ),
      ]);
    });
  }
}

class DiagramViewerPage extends StatefulWidget {
  final Circuit circuit;
  const DiagramViewerPage({super.key, required this.circuit});

  @override
  State<DiagramViewerPage> createState() => _DiagramViewerPageState();
}

class _DiagramViewerPageState extends State<DiagramViewerPage> {
  bool _power = false;

  @override
  Widget build(BuildContext context) {
    final ci = widget.circuit;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 1000;
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(children: [
              SquareButton(icon: CcIcons.back, label: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ci.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(ci.subtitle,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11.5, color: CC.muted, fontFamily: CC.mono)),
                ]),
              ),
              if (!wide)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: panelBox(radius: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _seg('القوى', _power, () => setState(() => _power = true)),
                    _seg('التحكم', !_power, () => setState(() => _power = false)),
                  ]),
                ),
            ]),
          );
          final note = Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(spacing: 14, runSpacing: 6, children: [
              for (final (tag, name) in ci.legend)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$tag ', style: const TextStyle(fontFamily: CC.mono, color: CC.cyan, fontWeight: FontWeight.w700)),
                  TextSpan(text: name),
                ]), style: const TextStyle(fontSize: 12.5, color: CC.text2)),
            ]),
          );
          if (wide) {
            return Column(children: [
              header,
              Expanded(
                child: Row(children: [
                  Expanded(child: _sheet('مخطط القوى', ci.powerSvg)),
                  Expanded(child: _sheet('مخطط التحكم', ci.controlSvg)),
                ]),
              ),
              note,
            ]);
          }
          return Column(children: [
            header,
            Expanded(child: _sheet(_power ? 'مخطط القوى' : 'مخطط التحكم', _power ? ci.powerSvg : ci.controlSvg)),
            note,
          ]);
        }),
      ),
    );
  }

  Widget _sheet(String title, String asset) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: panelBox(color: CC.stage, radius: 18, border: const Color(0xFF222C35)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 44, 8, 8),
              child: SvgPicture.asset(asset, fit: BoxFit.contain),
            ),
          ),
        ),
        PositionedDirectional(
          top: 10,
          start: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: panelBox(color: CC.bg, radius: 8),
            child: Text('$title · IEC 60617', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
        const PositionedDirectional(
          bottom: 10,
          end: 10,
          child: Text('قرّب بإصبعين أو بعجلة الماوس', style: TextStyle(fontSize: 11, color: CC.muted)),
        ),
      ]),
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) {
    return Material(
      color: on ? CC.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? CC.text : CC.muted)),
        ),
      ),
    );
  }
}
