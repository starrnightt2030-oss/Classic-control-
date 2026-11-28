import 'package:flutter/material.dart';

import '../data/circuits.dart';
import '../data/lessons.dart';
import '../data/library.dart';
import '../services/sound.dart';
import '../sim/model.dart';
import '../theme.dart';
import 'circuits_page.dart';
import 'lab/painters.dart';

class LearnPage extends StatelessWidget {
  const LearnPage();
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: NavyBackground(
          child: SafeArea(
            child: Column(children: [
              const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 4), child: Align(alignment: Alignment.centerRight, child: GoldText('التعلم', size: 22))),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: C.gold,
                labelColor: C.goldHi,
                unselectedLabelColor: C.dim,
                labelStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                tabs: [Tab(text: 'الدروس'), Tab(text: 'العِدد والمكونات'), Tab(text: 'جدول الرموز'), Tab(text: 'طرق الرسم')],
              ),
              const Expanded(child: TabBarView(children: [LessonsList(), LibraryList(), SymbolsTable(), DrawingMethods()])),
            ]),
          ),
        ),
      );
}

class LessonsPage extends StatelessWidget {
  const LessonsPage();
  @override
  Widget build(BuildContext context) => const PageFrame(title: 'الدروس', body: LessonsList());
}

class LessonsList extends StatelessWidget {
  const LessonsList();
  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: wide ? 360 : 420, mainAxisExtent: 112, mainAxisSpacing: 10, crossAxisSpacing: 10),
      itemCount: lessons.length,
      itemBuilder: (context, i) {
        final l = lessons[i];
        return GlowCard(
          padding: const EdgeInsets.all(8),
          onTap: () {
            Sound.play(Sfx.tap);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonPage(l)));
          },
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(l.image, width: 130, height: 96, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('الدرس ${i + 1}', style: const TextStyle(color: C.goldHi, fontSize: 11)),
                Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(l.sub, maxLines: 2, style: const TextStyle(color: C.dim, fontSize: 12)),
                Text('⏱ ${l.minutes} دقايق', style: const TextStyle(color: C.dim, fontSize: 11)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class LessonPage extends StatelessWidget {
  final Lesson l;
  const LessonPage(this.l);
  @override
  Widget build(BuildContext context) => PageFrame(
        title: l.title,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: AspectRatio(aspectRatio: 2.2, child: Image.asset(l.image, fit: BoxFit.cover))),
              const SizedBox(height: 10),
              Text(l.sub, style: const TextStyle(color: C.dim)),
              for (final p in l.parts) ...[
                SectionTitle(p.h),
                if (p.body.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(p.body, style: const TextStyle(fontSize: 15, height: 1.7))),
                for (final pt in p.points)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.bolt, size: 16, color: C.gold)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(pt, style: const TextStyle(fontSize: 14.5, height: 1.6))),
                    ]),
                  ),
              ],
              if (l.circuits.isNotEmpty) ...[
                const SectionTitle('طبّق على المحاكي'),
                for (final id in l.circuits)
                  if (circuitById(id) != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(height: 140, child: CircuitCard(circuitById(id)!))),
              ],
              const SizedBox(height: 20),
            ]),
          ),
        ),
      );
}

class LibraryList extends StatefulWidget {
  const LibraryList();
  @override
  State<LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<LibraryList> {
  String cat = libCats.first;
  String q = '';
  @override
  Widget build(BuildContext context) {
    final items = library.where((e) => q.isEmpty ? e.cat == cat : (e.name.contains(q) || e.en.toLowerCase().contains(q.toLowerCase()))).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'دوّر على عِدة أو مكون...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: C.card,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.glow.withValues(alpha: .5))),
          ),
          onChanged: (v) => setState(() => q = v.trim()),
        ),
      ),
      if (q.isEmpty)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final c in libCats) Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c))),
          ]),
        ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 170, mainAxisSpacing: 10, crossAxisSpacing: 10),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final e = items[i];
            return GlowCard(
              padding: const EdgeInsets.all(8),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LibItemPage(e))),
              child: Column(children: [
                Expanded(child: LibVisual(e)),
                const SizedBox(height: 6),
                Text(e.name, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
                Text(e.en, style: const TextStyle(fontSize: 10, color: C.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class LibVisual extends StatelessWidget {
  final LibItem e;
  final double emoji;
  const LibVisual(this.e, {this.emoji = 44});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: e.kind != null ? const LinearGradient(colors: [C.board, C.boardDark]) : const RadialGradient(colors: [C.cardHi, C.navy1]),
        ),
        padding: const EdgeInsets.all(8),
        child: e.kind != null ? PartIcon(e.kind!, size: 200) : Center(child: Text(e.emoji, style: TextStyle(fontSize: emoji))),
      );
}

class LibItemPage extends StatelessWidget {
  final LibItem e;
  const LibItemPage(this.e);
  @override
  Widget build(BuildContext context) => PageFrame(
        title: e.name,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              SizedBox(height: 220, child: LibVisual(e, emoji: 90)),
              const SizedBox(height: 10),
              Text(e.en, style: const TextStyle(color: C.goldHi)),
              const SizedBox(height: 6),
              Text(e.about, style: const TextStyle(fontSize: 15.5, height: 1.7)),
              if (e.kind != null) ...[
                const SectionTitle('الرمز في المخطط'),
                Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.all(8), child: PartIcon(e.kind!, size: 200, skin: Skin.schematic)),
                const SizedBox(height: 4),
                Text('الأطراف: ${partTypes[e.kind]!.terms.map((t) => t.label).join(' • ')}', style: const TextStyle(color: C.dim)),
              ],
              if (e.specs.isNotEmpty) ...[const SectionTitle('المواصفات'), for (final s in e.specs) _bullet(s, Icons.check_circle_outline)],
              if (e.use.isNotEmpty) ...[const SectionTitle('الاستخدام'), for (final s in e.use) _bullet(s, Icons.handyman_outlined)],
              if (e.safety.isNotEmpty) ...[
                const SectionTitle('تحذير'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: glowCard(r: 12, border: C.warn),
                  child: Row(children: [const Icon(Icons.warning_amber_rounded, color: C.warn), const SizedBox(width: 8), Expanded(child: Text(e.safety, style: const TextStyle(height: 1.5)))]),
                ),
              ],
              const SizedBox(height: 24),
            ]),
          ),
        ),
      );

  Widget _bullet(String s, IconData i) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 18, color: C.gold), const SizedBox(width: 8), Expanded(child: Text(s, style: const TextStyle(fontSize: 14.5, height: 1.5)))]),
      );
}

class SymbolsTable extends StatelessWidget {
  const SymbolsTable();
  @override
  Widget build(BuildContext context) {
    final kinds = Kind.values;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 190, mainAxisSpacing: 10, crossAxisSpacing: 10),
      itemCount: kinds.length,
      itemBuilder: (context, i) {
        final k = kinds[i];
        final t = partTypes[k]!;
        return GlowCard(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.all(6), child: PartIcon(k, size: 120, skin: Skin.schematic))),
                const SizedBox(width: 6),
                Expanded(child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.board, C.boardDark]), borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.all(6), child: PartIcon(k, size: 120))),
              ]),
            ),
            const SizedBox(height: 6),
            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(t.en, style: const TextStyle(fontSize: 10.5, color: C.dim)),
          ]),
        );
      },
    );
  }
}

class DrawingMethods extends StatelessWidget {
  const DrawingMethods();
  @override
  Widget build(BuildContext context) {
    final c = circuits.firstWhere((c) => c.id == 'c08');
    Widget card(String t, String s, Widget pic) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: glowCard(r: 16),
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: C.goldHi)),
              const SizedBox(height: 4),
              Text(s, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 8),
              AspectRatio(aspectRatio: 1000 / 620, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(color: Colors.white, child: pic))),
            ]),
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('نفس الدايرة (التحكم في لمبة من مكانين) مرسومة بالتلات طرق اللي هتقابلها في الشغل والامتحانات:', style: TextStyle(height: 1.6)),
          const SizedBox(height: 10),
          card('1. مخطط التوصيل (الحقيقي)', 'بيوري كل مكون بشكله وكل سلك بلونه ومكان ربطه. ده اللي بتمشي عليه وانت بتوصّل على اللوحة.', CircuitPreview(c, skin: Skin.board, lit: true)),
          card('2. المخطط الخطي (التفصيلي)', 'رموز IEC وخطوط مستقيمة بتوضح فكرة الدايرة ومسار التيار من غير الاهتمام بأماكن المكونات الحقيقية.', CircuitPreview(c, skin: Skin.schematic, lit: true)),
          card('3. المسقط (المخطط التنفيذي)', 'أماكن النقط على مسقط الغرفة. الخط بين النقطتين = ماسورة، وعدد الشرط عليه = عدد الأسلاك جواها.', CustomPaint(painter: PlanPainter(c), size: Size.infinite)),
        ]),
      ),
    );
  }
}
