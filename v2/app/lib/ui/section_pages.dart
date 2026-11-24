import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/repository.dart';
import 'cards.dart';
import 'component_page.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full-screen frame for a section opened from a card.
class SectionScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const SectionScaffold({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              SquareButton(icon: CcIcons.back, label: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
            ]),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}

/// «فيديو لكل مكوّن» / «ورقة الدرس»: pick a component, the page opens and starts the action.
class ActionListPage extends StatefulWidget {
  final AutoAction action;
  const ActionListPage({super.key, required this.action});

  @override
  State<ActionListPage> createState() => _ActionListPageState();
}

class _ActionListPageState extends State<ActionListPage> {
  @override
  Widget build(BuildContext context) {
    final video = widget.action == AutoAction.video;
    final repo = Repository.instance;
    return SectionScaffold(
      title: video ? 'فيديو لكل مكوّن' : 'ورقة الدرس',
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
        final cw = c.maxWidth >= 900 ? 184.0 : 152.0;
        return ListView(padding: EdgeInsets.fromLTRB(pad, 6, pad, 28), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: panelBox(color: CC.amberBg, border: CC.amberLine, radius: 14),
            child: Row(children: [
              CcIcon(video ? CcIcons.film : CcIcons.sheet, color: CC.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  video
                      ? 'اختار المكوّن، والعرض هيشتغل لوحده: لفّة، وبعدها فك بأسماء الأجزاء، وبعدها تركيب. وفي الآخر تحفظ الفيديو أو تبعته.'
                      : 'اختار المكوّن، وهتطلع ورقة منسّقة فيها الشكل، والأجزاء بأرقامها، والشرح. تحفظها صورة أو PDF.',
                  style: const TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFF3E3BE)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          for (final cat in categories) ...[
            ComponentRow(
              title: cat.nameAr,
              items: [for (final id in cat.components) if (repo.byId(id) != null) repo.byId(id)!],
              action: widget.action,
              cardWidth: cw,
            ),
            const SizedBox(height: 18),
          ],
        ]);
      }),
    );
  }
}

class SoonPage extends StatelessWidget {
  final String title;
  final String image;
  const SoonPage({super.key, required this.title, required this.image});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: title,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        ClipRRect(borderRadius: BorderRadius.circular(22), child: AspectRatio(aspectRatio: 1.25, child: Image.asset(image, fit: BoxFit.cover))),
        const SizedBox(height: 18),
        const Text('المرحلة الجاية', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: CC.amber)),
        const SizedBox(height: 6),
        const Text(
          'القسم ده هيتبني في مرحلة المحاكاة: لوحة حقيقية تركّب فيها المكونات على الريل، وتوصّل الأسلاك بألوانها، وتشغّل الدايرة وتقيس بالأفوميتر، والمخطط بيتلوّن معاك وهو شغّال.',
          style: TextStyle(fontSize: 15, height: 1.8, color: CC.text2),
        ),
      ]),
    );
  }
}
