import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'component_page.dart';
import 'diagrams_page.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<int> onGo;
  const HomePage({super.key, required this.onGo});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final lastId = repo.lastComponent ?? 'contactor';
    final last = repo.byId(lastId) ?? repo.byId('contactor');
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final pad = wide ? 32.0 : 18.0;
      final tiles = _tiles(context);
      return ListView(
        padding: EdgeInsets.fromLTRB(pad, 18, pad, 28),
        children: [
          Row(children: [
            if (!wide) ...[const AppMark(size: 40), const SizedBox(width: 12)],
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('معمل الكلاسيك كنترول', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
                Text('مركز التدريب · ترسانة الإسكندرية', style: TextStyle(fontSize: 12.5, color: CC.muted)),
              ]),
            ),
            SquareButton(icon: CcIcons.search, label: 'بحث', onTap: () => widget.onGo(1)),
          ]),
          const SizedBox(height: 18),
          if (last != null)
            ContinueCard(
              component: last,
              seen: repo.seenParts(last.id).length,
              onOpen: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComponentPage(componentId: last.id)));
                if (mounted) setState(() {});
              },
            ),
          const SizedBox(height: 20),
          const SectionTitle('ابدأ من هنا'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: wide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: wide ? 1.9 : 1.55,
            children: tiles,
          ),
          const SizedBox(height: 18),
          const SafetyStrip(text: 'افصل، اقفل، علّق الكارت، واتأكد بالأفوميتر قبل ما تلمس.'),
          const SizedBox(height: 20),
          const SectionTitle('دوائر أساسية'),
          const SizedBox(height: 10),
          CircuitCard(
            title: 'تشغيل مباشر بزرارين',
            subtitle: 'DOL Starter',
            tag: 'مخطط قوى + تحكم',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagramViewerPage(circuit: dolCircuit))),
          ),
        ],
      );
    });
  }

  List<Widget> _tiles(BuildContext context) => [
        ActionTile(
          icon: CcIcons.explode,
          title: 'فك وتركيب 3D',
          subtitle: 'لمس أي جزء يشرحه',
          accent: CC.amber,
          onTap: () => widget.onGo(1),
        ),
        ActionTile(
          icon: CcIcons.diagram,
          title: 'المخططات',
          subtitle: 'قوى وتحكم بالرموز',
          accent: CC.cyan,
          onTap: () => widget.onGo(2),
        ),
        ActionTile(
          icon: CcIcons.lab,
          title: 'معمل اللوحة',
          subtitle: 'المرحلة الجاية',
          accent: CC.cyan,
          soon: true,
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('معمل اللوحة والمحاكاة هو المرحلة الجاية بعد ما نجرّب ده.'))),
        ),
        ActionTile(
          icon: CcIcons.quiz,
          title: 'اختبر نفسك',
          subtitle: 'قريبًا',
          accent: CC.amber,
          soon: true,
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('الاختبارات هتيجي مع مرحلة المحاكاة.'))),
        ),
      ];
}
