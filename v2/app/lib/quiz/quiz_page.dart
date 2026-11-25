// «اختبر نفسك»: quick test, full timed exam, or one topic; symbols and schematics
// as figures; explanation after each answer; results and best scores are kept.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../schem/ladder.dart';
import '../schem/model.dart';
import '../schem/sheet_paint.dart';
import '../schem/symbols.dart';
import '../services/audio_service.dart';
import '../ui/theme.dart';
import 'bank.dart';

const _histKey = 'quiz_history_v1';

class QuizResult {
  final String mode, title;
  final int score, total, seconds;
  final DateTime at;
  const QuizResult(this.mode, this.title, this.score, this.total, this.seconds, this.at);
  int get pct => total == 0 ? 0 : (score * 100 / total).round();
  Map<String, Object> toJson() => {'m': mode, 't': title, 's': score, 'n': total, 'sec': seconds, 'at': at.toIso8601String()};
  static QuizResult fromJson(Map<String, dynamic> j) =>
      QuizResult(j['m'] as String, j['t'] as String, j['s'] as int, j['n'] as int, j['sec'] as int, DateTime.parse(j['at'] as String));
}

Future<List<QuizResult>> loadHistory() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_histKey);
  if (raw == null) return [];
  return [for (final e in jsonDecode(raw) as List) QuizResult.fromJson(e as Map<String, dynamic>)];
}

Future<void> _saveResult(QuizResult r) async {
  final l = await loadHistory();
  l.insert(0, r);
  final p = await SharedPreferences.getInstance();
  await p.setString(_histKey, jsonEncode([for (final x in l.take(60)) x.toJson()]));
}

class QuizHomePage extends StatefulWidget {
  const QuizHomePage({super.key});
  @override
  State<QuizHomePage> createState() => _QuizHomePageState();
}

class _QuizHomePageState extends State<QuizHomePage> {
  List<QuizResult> hist = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final h = await loadHistory();
    if (mounted) setState(() => hist = h);
  }

  int? _best(String mode) {
    final l = hist.where((r) => r.mode == mode);
    if (l.isEmpty) return null;
    return l.map((r) => r.pct).reduce(math.max);
  }

  Future<void> _start(String mode, String title, List<QQ> qs, {int? seconds}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuizRunPage(mode: mode, title: title, questions: qs, seconds: seconds)));
    _reload();
  }

  List<QQ> _pick(Iterable<QQ> src, int n) {
    final l = src.toList()..shuffle();
    return l.take(n).toList();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
    final total = kQuiz.length;
    return Scaffold(
      appBar: AppBar(title: const Text('اختبر نفسك')),
      body: AppBackdrop(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('$total سؤالًا في ${kQuizCats.length} موضوعات، مع شرح لكل إجابة.', style: const TextStyle(color: CC.text2)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 3.2 : 2.6,
            children: [
              _ModeCard(
                  icon: Icons.bolt_rounded,
                  color: CC.amber,
                  title: 'اختبار سريع',
                  sub: '10 أسئلة عشوائية من كل الموضوعات',
                  best: _best('quick'),
                  onTap: () => _start('quick', 'اختبار سريع', _pick(kQuiz, 10))),
              _ModeCard(
                  icon: Icons.workspace_premium_rounded,
                  color: CC.gold,
                  title: 'الامتحان الشامل',
                  sub: '30 سؤالًا في 20 دقيقة، والنتيجة بتقدير',
                  best: _best('exam'),
                  onTap: () => _start('exam', 'الامتحان الشامل', _pick(kQuiz, 30), seconds: 20 * 60)),
              _ModeCard(
                  icon: Icons.schema_outlined,
                  color: CC.green,
                  title: 'قراءة الرموز والمخططات',
                  sub: 'تعرّف على رموز IEC وافهم الدوائر الجاهزة',
                  best: _best('read'),
                  onTap: () => _start('read', 'الرموز والمخططات', _pick(kQuiz.where((q) => q.cat == 'sym' || q.cat == 'read' || q.fig != null), 12))),
            ],
          ),
          const SizedBox(height: 22),
          const Text('حسب الموضوع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (id, name, col) in kQuizCats)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _start('cat_$id', name, _pick(kQuiz.where((q) => q.cat == id), 12)),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: panelBox(radius: 18),
                    child: Row(children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(col), boxShadow: glow(Color(col), 0.7))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text('${kQuiz.where((q) => q.cat == id).length} سؤال', style: const TextStyle(color: CC.muted, fontSize: 12.5)),
                      const SizedBox(width: 12),
                      if (_best('cat_$id') != null) _Pct(_best('cat_$id')!),
                      const Icon(Icons.chevron_left_rounded, color: CC.muted),
                    ]),
                  ),
                ),
              ),
            ),
          if (hist.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('آخر النتائج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in hist.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Pct(r.pct),
                title: Text(r.title),
                subtitle: Text('${r.score} من ${r.total} · ${_dur(r.seconds)} · ${r.at.day}/${r.at.month}', style: const TextStyle(color: CC.muted)),
              ),
          ],
        ]),
      ),
    );
  }
}

String _dur(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

class _Pct extends StatelessWidget {
  final int pct;
  const _Pct(this.pct);
  @override
  Widget build(BuildContext context) {
    final c = pct >= 85 ? CC.green : (pct >= 60 ? CC.gold : CC.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: c), color: c.withValues(alpha: 0.12)),
      child: Text('$pct%', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  final int? best;
  final VoidCallback onTap;
  const _ModeCard({required this.icon, required this.color, required this.title, required this.sub, required this.best, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: panelBox(radius: 22, border: color.withValues(alpha: 0.5)),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.6))),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(sub, maxLines: 2, style: const TextStyle(color: CC.text2, fontSize: 12.5, height: 1.4)),
                ]),
              ),
              if (best != null) _Pct(best!),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------ running a quiz
class QuizRunPage extends StatefulWidget {
  final String mode, title;
  final List<QQ> questions;
  final int? seconds; // time limit
  const QuizRunPage({super.key, required this.mode, required this.title, required this.questions, this.seconds});
  @override
  State<QuizRunPage> createState() => _QuizRunPageState();
}

class _QuizRunPageState extends State<QuizRunPage> {
  int i = 0;
  int? picked;
  late List<List<int>> order; // shuffled option order per question
  final answers = <int, int>{}; // question index → picked original option index
  final sw = Stopwatch()..start();
  Timer? _t;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    order = [for (final q in widget.questions) List<int>.generate(q.o.length, (k) => k)..shuffle(r)];
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final lim = widget.seconds;
      if (lim != null && sw.elapsed.inSeconds >= lim && !finished) _finish();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  int get score => answers.entries.where((e) => e.value == 0).length;

  void _pick(int orig) {
    if (picked != null) return;
    setState(() {
      picked = orig;
      answers[i] = orig;
    });
    AudioService.instance.sfx(orig == 0 ? 'success_chime' : 'soft_fail');
  }

  void _next() {
    if (i + 1 >= widget.questions.length) {
      _finish();
      return;
    }
    setState(() {
      i++;
      picked = null;
    });
  }

  Future<void> _finish() async {
    if (finished) return;
    finished = true;
    sw.stop();
    final r = QuizResult(widget.mode, widget.title, score, widget.questions.length, sw.elapsed.inSeconds, DateTime.now());
    await _saveResult(r);
    if (!mounted) return;
    AudioService.instance.sfx(r.pct >= 60 ? 'success_fanfare' : 'soft_fail');
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => _ResultPage(result: r, questions: widget.questions, answers: answers)));
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[i];
    final lim = widget.seconds;
    final left = lim == null ? null : math.max(0, lim - sw.elapsed.inSeconds);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(left != null ? '⏱ ${_dur(left)}' : _dur(sw.elapsed.inSeconds),
                  textDirection: TextDirection.ltr, style: TextStyle(fontFamily: CC.mono, color: left != null && left < 60 ? CC.red : CC.text2)),
            ),
          ),
        ],
      ),
      body: AppBackdrop(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final fig = q.fig == null ? null : _Figure(q.fig!);
          final options = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < order[i].length; k++) _option(q, order[i][k], k),
            if (picked != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: panelBox(radius: 16, border: picked == 0 ? CC.green : CC.gold),
                child: Text(q.why, style: const TextStyle(height: 1.7)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _next,
                icon: Icon(i + 1 >= widget.questions.length ? Icons.flag_rounded : Icons.arrow_back_rounded),
                label: Text(i + 1 >= widget.questions.length ? 'إنهاء وعرض النتيجة' : 'السؤال التالي'),
              ),
            ],
          ]);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                Text('${i + 1} / ${widget.questions.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: (i + (picked == null ? 0 : 1)) / widget.questions.length, minHeight: 7, backgroundColor: CC.line),
                  ),
                ),
                const SizedBox(width: 12),
                Text('✓ $score', style: const TextStyle(color: CC.green, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
                Text(kQuizCats.firstWhere((x) => x.$1 == q.cat, orElse: () => kQuizCats.first).$2, style: const TextStyle(color: CC.accentSoft, fontSize: 12.5)),
                const SizedBox(height: 6),
                Text(q.q, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.6)),
                const SizedBox(height: 14),
                if (wide && fig != null)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: fig),
                    const SizedBox(width: 16),
                    Expanded(child: options),
                  ])
                else ...[
                  if (fig != null) ...[fig, const SizedBox(height: 14)],
                  options,
                ],
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _option(QQ q, int orig, int k) {
    final letter = 'أبجد'[k % 4];
    final chosen = picked == orig;
    Color border = CC.line;
    Color? fill;
    IconData? mark;
    if (picked != null) {
      if (orig == 0) {
        border = CC.green;
        fill = CC.green.withValues(alpha: 0.12);
        mark = Icons.check_circle_rounded;
      } else if (chosen) {
        border = CC.red;
        fill = CC.red.withValues(alpha: 0.12);
        mark = Icons.cancel_rounded;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: picked == null ? () => _pick(orig) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: border, width: 1.4), color: fill ?? CC.surface),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: border == CC.line ? CC.line2 : border)),
                child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(q.o[orig], style: const TextStyle(fontSize: 15, height: 1.5))),
              if (mark != null) Icon(mark, color: border),
            ]),
          ),
        ),
      ),
    );
  }
}

/// a symbol or a schematic shown with the question (tap a schematic to enlarge)
class _Figure extends StatelessWidget {
  final String fig;
  const _Figure(this.fig);
  @override
  Widget build(BuildContext context) {
    if (fig.startsWith('sym:')) {
      final d = kSyms[fig.substring(4)];
      if (d == null) return const SizedBox();
      return Container(
        height: 190,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: CustomPaint(painter: _SymFig(d)),
      );
    }
    final r = readyById(fig.substring(5));
    if (r == null) return const SizedBox();
    final doc = r.build();
    final sheet = CustomPaint(painter: _SheetFig(doc), size: Size.infinite);
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
          child: InteractiveViewer(maxScale: 8, child: AspectRatio(aspectRatio: doc.sheetW / doc.sheetH, child: sheet)),
        ),
      ),
      child: Container(
        height: 260,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: sheet)),
          const PositionedDirectional(bottom: 8, start: 8, child: Icon(Icons.zoom_in_rounded, color: Color(0xFF3D8BFF))),
        ]),
      ),
    );
  }
}

class _SymFig extends CustomPainter {
  final SymDef d;
  _SymFig(this.d);
  @override
  void paint(Canvas c, Size size) {
    final w = (d.w + 3) * kG, h = (d.h + 1) * kG;
    final s = math.min(size.width / w, size.height / h);
    c.translate((size.width - d.w * kG * s) / 2, (size.height - d.h * kG * s) / 2);
    c.scale(s);
    paintSymbol(c, d, labels: false);
  }

  @override
  bool shouldRepaint(covariant _SymFig old) => old.d != d;
}

class _SheetFig extends CustomPainter {
  final SchemDoc doc;
  _SheetFig(this.doc);
  @override
  void paint(Canvas c, Size size) {
    final w = doc.sheetW * kG, h = doc.sheetH * kG;
    final s = math.min(size.width / w, size.height / h);
    c.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    c.scale(s);
    SheetPainter(doc, print: true).paint(c, Size(w, h));
  }

  @override
  bool shouldRepaint(covariant _SheetFig old) => false;
}

// ------------------------------------------------------------------ result
class _ResultPage extends StatelessWidget {
  final QuizResult result;
  final List<QQ> questions;
  final Map<int, int> answers;
  const _ResultPage({required this.result, required this.questions, required this.answers});

  @override
  Widget build(BuildContext context) {
    final p = result.pct;
    final c = p >= 85 ? CC.green : (p >= 60 ? CC.gold : CC.red);
    final grade = p >= 90 ? 'ممتاز' : (p >= 80 ? 'جيد جدًا' : (p >= 65 ? 'جيد' : (p >= 50 ? 'مقبول' : 'يحتاج مراجعة')));
    final wrong = [for (var k = 0; k < questions.length; k++) if (answers[k] != 0) k];
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: AppBackdrop(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: p / 100, strokeWidth: 12, color: c, backgroundColor: CC.line)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$p%', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: c)),
                  Text(grade, style: const TextStyle(color: CC.text2, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Center(child: Text('${result.score} إجابة صحيحة من ${result.total} · الزمن ${_dur(result.seconds)}', style: const TextStyle(color: CC.text2))),
          const SizedBox(height: 20),
          if (wrong.isNotEmpty) ...[
            const Text('راجع هذه الأسئلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final k in wrong)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: panelBox(radius: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(questions[k].q, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5)),
                  const SizedBox(height: 6),
                  if (answers[k] != null) Text('إجابتك: ${questions[k].o[answers[k]!]}', style: const TextStyle(color: CC.red)),
                  Text('الصحيح: ${questions[k].o[0]}', style: const TextStyle(color: CC.green)),
                  const SizedBox(height: 6),
                  Text(questions[k].why, style: const TextStyle(color: CC.text2, height: 1.6)),
                ]),
              ),
          ] else
            const Center(child: Text('كل إجاباتك صحيحة. أحسنت!', style: TextStyle(fontSize: 16, color: CC.green))),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع إلى الاختبارات')),
        ]),
      ),
    );
  }
}
