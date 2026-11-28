import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/questions.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../theme.dart';

class QuizHome extends StatelessWidget {
  const QuizHome();
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'الاختبارات',
        body: ListenableBuilder(
          listenable: Progress.i,
          builder: (context, _) => ListView(padding: const EdgeInsets.all(12), children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(children: [
                Image.asset('assets/images/quiz_art.webp', height: 170, width: double.infinity, fit: BoxFit.cover),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, C.navy0.withValues(alpha: .9)])))),
                Positioned(
                  right: 16,
                  top: 24,
                  width: 230,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الاختبار الشامل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('20 سؤال من كل الأبواب. لو جبت 70% أو أكتر تاخد شهادة. (${questions.length} سؤال في البنك)', style: const TextStyle(fontSize: 12, height: 1.4)),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () => _start(context, 'all', 'الاختبار الشامل', 20), child: const Text('ابدأ')),
                  ]),
                ),
              ]),
            ),
            const SectionTitle('اختبر نفسك في باب معيّن'),
            for (final e in quizCats.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlowCard(
                  onTap: () => _start(context, e.key, e.value, 10),
                  border: e.key == 'interview' ? C.gold : null,
                  child: Row(children: [
                    Icon(e.key == 'interview' ? Icons.work_outline_rounded : Icons.quiz_outlined, color: C.gold),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${questions.where((q) => q.cat == e.key).length} سؤال', style: const TextStyle(color: C.dim, fontSize: 12)),
                    const SizedBox(width: 8),
                    if (Progress.i.quizBest[e.key] != null) Text('${Progress.i.quizBest[e.key]}%', style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  void _start(BuildContext context, String cat, String title, int n) {
    Sound.play(Sfx.click);
    final pool = questions.where((q) => cat == 'all' || q.cat == cat).toList()..shuffle();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizPage(cat: cat, title: title, qs: pool.take(n).toList())));
  }
}

class QuizPage extends StatefulWidget {
  final String cat;
  final String title;
  final List<Q> qs;
  const QuizPage({required this.cat, required this.title, required this.qs});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int i = 0, score = 0;
  int? picked;
  late List<String> opts;
  final _r = math.Random();

  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  void _shuffle() => opts = List.of(widget.qs[i].a)..shuffle(_r);

  void _pick(int k) {
    if (picked != null) return;
    final ok = opts[k] == widget.qs[i].a.first;
    if (ok) score++;
    Sound.play(ok ? Sfx.success : Sfx.fail, volume: .7);
    setState(() => picked = k);
  }

  void _next() {
    if (i + 1 >= widget.qs.length) {
      final pct = (score * 100 / widget.qs.length).round();
      Progress.i.setQuiz(widget.cat, pct);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => QuizResult(title: widget.title, score: score, total: widget.qs.length)));
      return;
    }
    setState(() {
      i++;
      picked = null;
      _shuffle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.qs[i];
    return PageFrame(
      title: widget.title,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Text('سؤال ${i + 1} من ${widget.qs.length}', style: const TextStyle(color: C.goldHi)),
              const Spacer(),
              Text('الدرجة: $score', style: const TextStyle(color: C.dim)),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: (i + 1) / widget.qs.length, color: C.gold, backgroundColor: Colors.white12, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: glowCard(r: 16),
              child: Text(q.q, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5)),
            ),
            const SizedBox(height: 12),
            for (var k = 0; k < opts.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Opt(
                  text: opts[k],
                  letter: 'أبجد'[k],
                  state: picked == null
                      ? 0
                      : opts[k] == q.a.first
                          ? 1
                          : picked == k
                              ? 2
                              : 0,
                  onTap: () => _pick(k),
                ),
              ),
            if (picked != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: glowCard(r: 12, border: opts[picked!] == q.a.first ? C.ok : C.bad),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, color: C.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text(q.why, style: const TextStyle(height: 1.5))),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _next, child: Text(i + 1 >= widget.qs.length ? 'النتيجة' : 'السؤال اللي بعده')),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Opt extends StatelessWidget {
  final String text;
  final String letter;
  final int state; // 0 neutral, 1 right, 2 wrong
  final VoidCallback onTap;
  const _Opt({required this.text, required this.letter, required this.state, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final col = state == 1 ? C.ok : state == 2 ? C.bad : null;
    return GlowCard(
      onTap: onTap,
      border: col,
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: col ?? C.gold.withValues(alpha: .25), child: Text(letter, style: TextStyle(color: col == null ? C.goldHi : Colors.white, fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
        if (state == 1) const Icon(Icons.check_circle, color: C.ok),
        if (state == 2) const Icon(Icons.cancel, color: C.bad),
      ]),
    );
  }
}

class QuizResult extends StatelessWidget {
  final String title;
  final int score, total;
  const QuizResult({required this.title, required this.score, required this.total});
  @override
  Widget build(BuildContext context) {
    final pct = (score * 100 / total).round();
    final pass = pct >= 70;
    return PageFrame(
      title: 'النتيجة',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: pct / 100, strokeWidth: 12, color: pass ? C.ok : C.warn, backgroundColor: Colors.white12)),
                  Text('$pct%', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(pass ? 'ممتاز! نجحت في $title' : 'محتاج تراجع شوية وتجرب تاني', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('$score إجابة صح من $total', textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
            const SizedBox(height: 16),
            if (pass) Certificate(title: title, pct: pct),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع للاختبارات')),
          ]),
        ),
      ),
    );
  }
}

class Certificate extends StatelessWidget {
  final String title;
  final int pct;
  const Certificate({required this.title, required this.pct});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = Progress.i.studentName.isEmpty ? 'المتدرب' : Progress.i.studentName;
    return AspectRatio(
      aspectRatio: 1.414,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: C.gold, width: 6),
          boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .4), blurRadius: 20)],
        ),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF0A2563), width: 1.5)),
          padding: const EdgeInsets.all(10),
          child: FittedBox(
            child: SizedBox(
              width: 560,
              height: 370,
              child: Column(children: [
                Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/logo.webp', width: 60)),
                  const Spacer(),
                  const Column(children: [
                    Text(AppInfo.nameAr, style: TextStyle(color: Color(0xFF0A2563), fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(AppInfo.nameEn, style: TextStyle(color: Color(0xFF5D4037), fontSize: 11)),
                  ]),
                  const Spacer(),
                  const Icon(Icons.workspace_premium_rounded, color: C.gold, size: 56),
                ]),
                const SizedBox(height: 14),
                const Text('شهادة إتمام', style: TextStyle(color: Color(0xFF0A2563), fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('تشهد الأكاديمية بأن', style: TextStyle(color: Colors.black87, fontSize: 15)),
                Text(name, style: const TextStyle(color: Color(0xFFB8860B), fontSize: 28, fontWeight: FontWeight.w700)),
                Text('اجتاز «$title» بنسبة $pct%', style: const TextStyle(color: Colors.black87, fontSize: 16)),
                const Spacer(),
                Row(children: [
                  Text('${now.day}/${now.month}/${now.year}', style: const TextStyle(color: Colors.black54)),
                  const Spacer(),
                  const Column(children: [
                    Text(AppInfo.developer, style: TextStyle(color: Color(0xFF0A2563), fontWeight: FontWeight.w700)),
                    Text('المدرب', style: TextStyle(color: Colors.black54, fontSize: 11)),
                  ]),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
