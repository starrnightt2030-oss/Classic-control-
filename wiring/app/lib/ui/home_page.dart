import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/circuits.dart';
import '../services/progress.dart';
import '../theme.dart';
import 'calc_page.dart';
import 'circuits_page.dart';
import 'lab/lab_page.dart';
import 'lab/painters.dart';
import 'learn_page.dart';
import 'viewer3d.dart';
import '../data/lessons.dart';
import 'projects_page.dart';
import 'quiz_page.dart';

class HomePage extends StatelessWidget {
  final ValueChanged<int> onTab;
  const HomePage({required this.onTab});

  void _push(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final tiles = [
      ('lamp_1', 'محاكي الدوائر', '21 دايرة تفاعلية', () => onTab(1)),
      ('sw2_1', 'رسم الدوائر', 'ارسم وحاكي بالرموز', () => _push(context, const LabPage(skin: Skin.schematic))),
      ('multimeter', 'الدروس', 'من الأساسيات للتأسيس', () => _push(context, const LessonsPage())),
      ('kwh_meter', 'الحاسبات', 'أحمال، كابلات، قواطع', () => _push(context, const CalcPage())),
      ('tester', 'الاختبارات', 'بنك أسئلة وانترفيو', () => _push(context, const QuizHome())),
      ('jbox8', 'المشروعات', 'غرفة نوم، طرقة، مطبخ', () => _push(context, const ProjectsPage())),
    ];
    return NavyBackground(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Progress.i,
          builder: (context, _) {
            final last = circuitById(Progress.i.lastCircuit);
            final done = circuits.where((c) => Progress.i.stars.containsKey(c.id)).length;
            return ListView(padding: EdgeInsets.zero, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo.webp', width: 46)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GoldText(AppInfo.nameAr, size: 19),
                      Text(AppInfo.nameEn, style: TextStyle(fontSize: 11, color: C.dim)),
                    ]),
                  ),
                  _Stat(Icons.star_rounded, '${Progress.i.totalStars}'),
                ]),
              ),
              // banner
              Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: wide ? 3.2 : 1.75,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.asset('assets/images/home_banner.webp', fit: BoxFit.cover, alignment: Alignment.centerLeft),
                      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.transparent, Color(0xCC06122E)]))),
                      Positioned(
                        right: 16,
                        top: 16,
                        bottom: 16,
                        width: wide ? 420 : 210,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(Progress.i.studentName.isEmpty ? 'أهلاً بيك يا بشمهندس' : 'أهلاً يا ${Progress.i.studentName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text('اتعلم التمديدات الكهربية خطوة بخطوة، وصّل بإيدك، واكتشف الأعطال زي الحقيقة.', style: TextStyle(fontSize: 12.5, color: C.text, height: 1.4)),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => last == null ? onTab(1) : _push(context, CircuitPage(last)),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(last == null ? 'ابدأ أول دايرة' : 'كمّل: ${last.title}', overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              // tiles
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: wide ? 6 : 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .82,
                  children: [
                    for (final t in tiles)
                      GlowCard(
                        padding: const EdgeInsets.all(6),
                        onTap: t.$4,
                        child: Column(children: [
                          Expanded(child: Container(width: double.infinity, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: kRenderBg), child: ModelPicture(t.$1))),
                          const SizedBox(height: 6),
                          Text(t.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text(t.$3, style: const TextStyle(fontSize: 10.5, color: C.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                  ],
                ),
              ),
              // progress
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                child: GlowCard(
                  child: Row(children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(value: done / circuits.length, strokeWidth: 6, color: C.gold, backgroundColor: Colors.white12),
                        Text('$done/${circuits.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('تقدّمك', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('دواير خلصتها: $done • نجوم: ${Progress.i.totalStars} • أعطال اكتشفتها: ${Progress.i.faultsFound.values.fold(0, (a, b) => a + b)}', style: const TextStyle(fontSize: 12, color: C.dim)),
                      ]),
                    ),
                  ]),
                ),
              ),
              SectionTitle('دواير مقترحة', trailing: TextButton(onPressed: () => onTab(1), child: const Text('الكل'))),
              SizedBox(
                height: 150,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final c in circuits.where((c) => !Progress.i.stars.containsKey(c.id)).take(8))
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: SizedBox(width: 200, child: CircuitCard(c, compact: true)),
                    ),
                ]),
              ),
              SectionTitle('مكتبة سريعة', trailing: TextButton(onPressed: () => onTab(3), child: const Text('التعلم'))),
              SizedBox(
                height: 120,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final l in lessons.take(10))
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _push(context, LessonPage(l)),
                        child: Container(
                          width: 150,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: kRenderBg, border: Border.all(color: Colors.white12)),
                          child: Stack(children: [
                            Positioned.fill(bottom: 26, child: ModelPicture(l.cover)),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                color: const Color(0xCC06122E),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 24),
            ]);
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData i;
  final String v;
  const _Stat(this.i, this.v);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: glowCard(r: 20, border: C.gold),
        child: Row(children: [Icon(i, color: C.gold, size: 18), const SizedBox(width: 4), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]),
      );
}
