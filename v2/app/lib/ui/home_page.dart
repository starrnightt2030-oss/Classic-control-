import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/repository.dart';
import 'cards.dart';
import 'component_page.dart';
import 'diagrams_page.dart';
import 'icons.dart';
import 'library_page.dart';
import 'section_pages.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<int> onGo;
  const HomePage({super.key, required this.onGo});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _Section {
  final String image, title, subtitle, icon;
  final Color accent;
  final bool soon;
  final WidgetBuilder page;
  const _Section(this.image, this.title, this.subtitle, this.icon, this.accent, this.page, {this.soon = false});
}

class _HomePageState extends State<HomePage> {
  List<_Section> get _sections => [
        _Section('assets/images/cards/library.webp', 'مكتبة المكونات 3D', 'كل مكوّن بمجسم حقيقي: لفّه، فكّه بالشريط، والمس أي جزء يشرحه',
            CcIcons.library, CC.amber, (_) => const SectionScaffold(title: 'مكتبة المكونات', child: LibraryPage(embedded: true))),
        _Section('assets/images/cards/video.webp', 'فيديو لكل مكوّن', 'عرض متحرك للفك والتركيب بأسماء الأجزاء، تحفظه وتبعته',
            CcIcons.film, CC.amber, (_) => const ActionListPage(action: AutoAction.video)),
        _Section('assets/images/cards/sheet.webp', 'ورقة الدرس', 'صورة أو PDF منسّق: الشكل، والأجزاء بأرقامها، والشرح',
            CcIcons.sheet, CC.amber, (_) => const ActionListPage(action: AutoAction.sheet)),
        _Section('assets/images/cards/diagrams.webp', 'المخططات', 'مخطط القوى ومخطط التحكم بالرموز الكلاسيك IEC 60617',
            CcIcons.diagram, CC.cyan, (_) => const SectionScaffold(title: 'المخططات', child: DiagramsPage())),
        _Section('assets/images/cards/lab.webp', 'معمل اللوحة', 'ركّب المكونات على الريل ووصّل الأسلاك وشغّل الدايرة', CcIcons.lab, CC.cyan,
            (_) => const SoonPage(title: 'معمل اللوحة', image: 'assets/images/cards/lab.webp'),
            soon: true),
        _Section('assets/images/cards/quiz.webp', 'اختبر نفسك', 'أسئلة وأعطال عملية على كل مكوّن ودايرة', CcIcons.quiz, CC.red,
            (_) => const SoonPage(title: 'الاختبارات', image: 'assets/images/cards/quiz.webp'),
            soon: true),
      ];

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final last = repo.byId(repo.lastComponent ?? 'contactor') ?? repo.byId('contactor');
    final featuredIds = ['contactor', 'overload', 'mcb', 'mpcb', 'timer', 'control_relay', 'motor', 'pushbutton', 'estop', 'proximity_sensor'];
    final featured = [for (final id in featuredIds) if (repo.byId(id) != null) repo.byId(id)!];
    final sections = _sections;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final pad = w >= 900 ? 28.0 : 16.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(0, 14, 0, 28),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo_small.webp', width: 48, height: 48)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppInfo.brandEn, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: CC.amber, height: 1.2)),
                  Text(AppInfo.brandAr, style: TextStyle(fontSize: 13, color: CC.text2)),
                ]),
              ),
              SquareButton(icon: CcIcons.search, label: 'بحث في المكتبة', onTap: () => widget.onGo(1)),
            ]),
          ),
          const SizedBox(height: 18),
          CardCarousel(
            count: sections.length,
            height: carouselHeight(w),
            viewportFraction: carouselFraction(w),
            builder: (context, i) {
              final s = sections[i];
              return OpenCard(
                open: s.page,
                onClosed: () => setState(() {}),
                closed: (_) => SectionCard(image: s.image, title: s.title, subtitle: s.subtitle, icon: s.icon, accent: s.accent, soon: s.soon),
              );
            },
          ),
          const SizedBox(height: 22),
          if (last != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: SizedBox(
                height: 200,
                child: OpenCard(
                  onClosed: () => setState(() {}),
                  open: (_) => ComponentPage(componentId: last.id),
                  closed: (_) => ContinueCard(component: last, seen: repo.seenParts(last.id).length),
                ),
              ),
            ),
          const SizedBox(height: 22),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: ComponentRow(title: 'مكونات أساسية', items: featured, cardWidth: w >= 900 ? 190 : 156, onChanged: () => setState(() {})),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: const SafetyStrip(text: 'افصل، اقفل، علّق الكارت، واتأكد بالأفوميتر قبل ما تلمس.'),
          ),
        ],
      );
    });
  }
}
