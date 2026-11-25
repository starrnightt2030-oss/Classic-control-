import 'package:flutter/material.dart';

import '../app_info.dart';
import 'cards.dart';
import '../schem/ready_page.dart';
import 'icons.dart';
import 'library_page.dart';
import 'section_pages.dart';
import 'sim_pages.dart';
import '../lab/lab_page.dart';
import '../schem/schem_page.dart';
import '../services/export_service.dart';
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
        _Section('assets/images/cards/diagrams.webp', 'المخططات الجاهزة', '20 دائرة كلاسيك كنترول بمخطط القوى والتحكم الصحيح، تُشغَّل بالمحاكاة وتُطبع',
            CcIcons.diagram, CC.cyan, (_) => const SectionScaffold(title: 'المخططات الجاهزة', child: ReadyDiagramsPage())),
        _Section('assets/images/cards/diagrams.webp', 'محاكي الدوائر', '17 دائرة كلاسيكية تعمل حيًّا: الضواغط والكونتاكتورات والمؤقتات والمحرك، ومهام بالترتيب',
            CcIcons.bolt, CC.green, (_) => const CircuitListPage()),
        _Section('assets/images/cards/lab.webp', 'معمل اللوحة', 'ورقة عمل فارغة: أدخل المكونات الحقيقية من المكتبة، ووصّل كل سلك بيدك، وشغّل. الخطأ يعطي شرارة أو يحرق المكوّن',
            CcIcons.lab, CC.cyan, (_) => const LabPage()),
        _Section('assets/images/cards/diagrams.webp', 'محاكي الدوائر الخطية', 'ارسم الدائرة برموز IEC من المكتبة ووصّلها وحاكِها، ثم اطبعها PDF مع قائمة المكونات',
            CcIcons.diagram, CC.green, (_) => SchemPage(deliver: (b, n, m) => ExportService.deliverBytes(b, n, mime: m))),
        _Section('assets/images/cards/quiz.webp', 'اختبر نفسك', 'أسئلة وأعطال عملية على كل مكوّن ودايرة', CcIcons.quiz, CC.red,
            (_) => const SoonPage(title: 'الاختبارات', image: 'assets/images/cards/quiz.webp'),
            soon: true),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final pad = w >= 900 ? 28.0 : 14.0;
      final cols = w >= 1300 ? 4 : (w >= 820 ? 3 : 2);
      final tileH = w >= 820 ? 230.0 : 196.0;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 6),
          sliver: SliverToBoxAdapter(
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
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 10),
          sliver: const SliverToBoxAdapter(
            child: Text('القائمة الرئيسية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: tileH),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final s = sections[i];
                return OpenCard(
                  open: s.page,
                  onClosed: () => setState(() {}),
                  closed: (_) => SectionCard(image: s.image, title: s.title, subtitle: s.subtitle, icon: s.icon, accent: s.accent, soon: s.soon, compact: w < 820),
                );
              },
              childCount: sections.length,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 28),
          sliver: const SliverToBoxAdapter(child: SafetyStrip(text: 'افصل، اقفل، علّق الكارت، واتأكد بالأفوميتر قبل ما تلمس.')),
        ),
      ]);
    });
  }
}
