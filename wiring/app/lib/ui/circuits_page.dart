import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/circuits.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../services/sprites.dart';
import '../sim/model.dart';
import '../sim/solver.dart';
import '../theme.dart';
import 'lab/fx.dart';
import 'functional.dart';
import 'lab/lab_page.dart';
import 'lab/painters.dart';

class CircuitsPage extends StatefulWidget {
  const CircuitsPage();
  @override
  State<CircuitsPage> createState() => _CircuitsPageState();
}

class _CircuitsPageState extends State<CircuitsPage> {
  int level = 0;
  @override
  Widget build(BuildContext context) {
    final list = circuits.where((c) => level == 0 || c.level == level).toList();
    final cols = math.max(1, (MediaQuery.sizeOf(context).width / 340).floor());
    return NavyBackground(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Progress.i,
          builder: (context, _) => CustomScrollView(slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GoldText('محاكي الدوائر', size: 22),
                  Text('كل دايرة: توصيل جاهز، دليل خطوة بخطوة، تحدي بالتقييم، واكتشاف أعطال.', style: TextStyle(color: C.dim, fontSize: 12.5)),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 54,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                  for (var l = 0; l < levelNames.length; l++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(l == 0 ? 'الكل (${circuits.length})' : levelNames[l]),
                        selected: level == l,
                        onSelected: (_) => setState(() => level = l),
                      ),
                    ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 150),
                delegate: SliverChildBuilderDelegate((context, i) => CircuitCard(list[i]), childCount: list.length),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Static preview of a circuit (finished wiring), in either skin.
class CircuitPreview extends StatelessWidget {
  final CircuitDef c;
  final Skin skin;
  final bool lit;
  const CircuitPreview(this.c, {this.skin = Skin.schematic, this.lit = false});
  @override
  Widget build(BuildContext context) {
    final sim = c.buildDone();
    SimResult res = SimResult();
    if (lit && c.tests.isNotEmpty) {
      sim.power = true;
      applyScenario(sim, c.tests.lastWhere((s) => s.wait == 0, orElse: () => c.tests.last));
      res = simulate(sim);
    }
    final bb = sim.parts.map((p) => p.rect).reduce((a, b) => a.expandToInclude(b)).inflate(16).intersect(Offset.zero & boardSize);
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(size: bb.size, child: CustomPaint(painter: _Crop(BoardPainter(BoardState(sim: sim, res: res, skin: skin, t: 0, fx: Fx(), showLabels: skin == Skin.board)), bb.topLeft))),
    );
  }
}

class _Crop extends CustomPainter {
  final BoardPainter inner;
  final Offset origin;
  _Crop(this.inner, this.origin) : super(repaint: Sprites.i.ready);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-origin.dx, -origin.dy);
    inner.paint(canvas, boardSize);
  }

  @override
  bool shouldRepaint(_Crop o) => true;
}

class CircuitCard extends StatelessWidget {
  final CircuitDef c;
  final bool compact;
  const CircuitCard(this.c, {this.compact = false});
  @override
  Widget build(BuildContext context) {
    final stars = Progress.i.stars[c.id] ?? 0;
    return GlowCard(
      padding: const EdgeInsets.all(8),
      onTap: () {
        Sound.play(Sfx.tap);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircuitPage(c)));
      },
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(color: const Color(0xFFDDE2E8), width: double.infinity, child: CircuitPreview(c, skin: Skin.board, lit: true)))),
              const SizedBox(height: 4),
              Text('${c.no}. ${c.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ])
          : Row(children: [
              SizedBox(
                width: 120,
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(color: const Color(0xFFDDE2E8), height: double.infinity, child: CircuitPreview(c, skin: Skin.board, lit: true))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(color: C.gold.withValues(alpha: .18), borderRadius: BorderRadius.circular(8)),
                      child: Text('${c.no} • ${levelNames[c.level]}', style: const TextStyle(fontSize: 10.5, color: C.goldHi)),
                    ),
                    const Spacer(),
                    for (var i = 0; i < 3; i++) Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: C.gold),
                  ]),
                  const SizedBox(height: 4),
                  Text(c.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.3)),
                  const SizedBox(height: 2),
                  Expanded(child: Text(c.brief, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.dim, height: 1.35))),
                ]),
              ),
            ]),
    );
  }
}

class CircuitPage extends StatefulWidget {
  final CircuitDef c;
  final int view;
  const CircuitPage(this.c, {this.view = 0});
  @override
  State<CircuitPage> createState() => _CircuitPageState();
}

class _CircuitPageState extends State<CircuitPage> {
  late int view = widget.view; // 0 board, 1 wiring diagram, 2 plan, 3 functional
  CircuitDef get c => widget.c;

  void _open(LabMode m) {
    Sound.play(Sfx.click);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabPage(circuit: c, mode: m, skin: view == 1 ? Skin.schematic : Skin.board)));
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final preview = Container(
      decoration: glowCard(r: 16),
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('مجسم'), icon: Icon(Icons.view_in_ar_outlined, size: 18)),
            ButtonSegment(value: 1, label: Text('التوصيل'), icon: Icon(Icons.cable_outlined, size: 18)),
            ButtonSegment(value: 3, label: Text('الوظيفي'), icon: Icon(Icons.schema_outlined, size: 18)),
            ButtonSegment(value: 2, label: Text('المسقط'), icon: Icon(Icons.map_outlined, size: 18)),
          ],
          selected: {view},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => view = s.first),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: boardSize.width / boardSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: view == 2
                ? Container(color: Colors.white, child: CustomPaint(painter: PlanPainter(c), size: Size.infinite))
                : view == 3
                ? Container(color: Colors.white, padding: const EdgeInsets.all(6), child: FunctionalDiagram(c))
                : Container(color: view == 0 ? const Color(0xFFDDE2E8) : Colors.white, child: CircuitPreview(c, skin: view == 0 ? Skin.board : Skin.schematic, lit: true)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          switch (view) {
            0 => 'المجسم: الأجهزة الحقيقية على لوحة التدريب، وكل سلك بلونه رايح فين',
            1 => 'رسم التوصيل (التفصيلي): نفس أماكن الأجهزة برموز IEC، وكل سلك ظاهر من طرف لطرف',
            3 => 'الرسم الوظيفي (مسار التيار): الفاز فوق والنيوترال تحت، وتمشي ورا التيار من المفاتيح للحمل',
            _ => 'الرسم التنفيذي (المسقط): أماكن النقط في الغرفة، والشرط على الخط = عدد الأسلاك',
          },
          style: const TextStyle(fontSize: 11.5, color: C.dim),
          textAlign: TextAlign.center,
        ),
      ]),
    );
    final modes = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _modeBtn(Icons.play_circle_fill_rounded, 'التوصيل الجاهز', 'شوف الدايرة شغالة وجرّب الحالات', () => _open(LabMode.demo)),
      _modeBtn(Icons.route_rounded, 'دليل خطوة بخطوة', 'الأطراف بتنور وانت توصل سلك سلك', () => _open(LabMode.guide)),
      _modeBtn(Icons.emoji_events_rounded, 'تحدي التوصيل', 'وصّل لوحدك وخد تقييم بالنجوم', () => _open(LabMode.challenge)),
      _modeBtn(Icons.build_circle_rounded, 'اكتشاف الأعطال', 'عطل مخفي: لاقيه بالقياس', () => _open(LabMode.faults)),
    ]);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.brief, style: const TextStyle(fontSize: 14.5, height: 1.6)),
      if (c.tips.isNotEmpty) ...[
        const SectionTitle('نصايح الصنعة'),
        for (final t in c.tips)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.lightbulb_outline, size: 18, color: C.gold), const SizedBox(width: 6), Expanded(child: Text(t, style: const TextStyle(height: 1.5)))]),
          ),
      ],
      const SectionTitle('جدول التوصيل'),
      for (var i = 0; i < c.steps.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 11, backgroundColor: wireColor(c.steps[i].c), child: Text('${i + 1}', style: const TextStyle(fontSize: 10, color: Colors.white))),
            const SizedBox(width: 8),
            Expanded(child: Text(c.steps[i].text, style: const TextStyle(height: 1.45))),
          ]),
        ),
      const SectionTitle('جدول الحالات'),
      Container(
        decoration: glowCard(r: 12),
        child: Column(children: [
          for (final s in c.tests)
            ListTile(
              dense: true,
              title: Text(s.label),
              trailing: Wrap(spacing: 6, children: [
                for (final e in s.expect.entries)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${e.key} ${e.value ? 'شغال' : 'مطفي'}', style: const TextStyle(fontSize: 11)),
                    backgroundColor: e.value ? C.ok.withValues(alpha: .25) : Colors.white10,
                  ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 20),
    ]);
    return PageFrame(
      title: '${c.no}. ${c.title}',
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: ListView(padding: const EdgeInsets.all(16), children: [preview, const SizedBox(height: 12), modes])),
              Expanded(flex: 2, child: ListView(padding: const EdgeInsets.all(16), children: [info])),
            ])
          : ListView(padding: const EdgeInsets.all(12), children: [preview, const SizedBox(height: 12), modes, const SizedBox(height: 8), info]),
    );
  }

  Widget _modeBtn(IconData i, String t, String s, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlowCard(
          onTap: f,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [C.goldHi, C.gold]), boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .4), blurRadius: 10)]),
              child: Icon(i, color: C.navy0),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)), Text(s, style: const TextStyle(color: C.dim, fontSize: 12))])),
            const Icon(Icons.chevron_left, color: C.dim),
          ]),
        ),
      );
}

/// Architectural plan of the circuit: room outline, IEC plan symbols and
/// conductor count ticks on every run.
class PlanPainter extends CustomPainter {
  final CircuitDef c;
  PlanPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / 1000, size.height / 620);
    canvas.scale(k);
    const ink = Color(0xFF1B2A4A);
    final wall = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    final room = const Rect.fromLTWH(70, 60, 860, 500);
    canvas.drawRect(room, wall);
    // door opening
    canvas.drawLine(const Offset(700, 560), const Offset(800, 560), Paint()
      ..color = Colors.white
      ..strokeWidth = 12);
    canvas.drawArc(Rect.fromCircle(center: const Offset(700, 560), radius: 100), -math.pi / 2, math.pi / 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black38);
    text(canvas, c.room, const Offset(500, 90), size: 20, color: Colors.black38, w: FontWeight.w700);

    final parts = c.parts();
    final pos = <String, Offset>{};
    pos['DB'] = const Offset(110, 300);
    final loads = parts.where((p) => const {Kind.lamp, Kind.tube, Kind.ledpanel, Kind.bell, Kind.lock}.contains(p.kind)).toList();
    final ctrls = parts.where((p) => const {Kind.sw1, Kind.sw2, Kind.swi, Kind.swd, Kind.pb, Kind.dimmer}.contains(p.kind)).toList();
    final sockets = parts.where((p) => p.kind == Kind.socket).toList();
    final extra = parts.where((p) => const {Kind.stair, Kind.driver, Kind.ballast, Kind.starter, Kind.rcd, Kind.meter, ...jboxKinds}.contains(p.kind)).toList();
    for (var i = 0; i < loads.length; i++) {
      pos[loads[i].id] = Offset(260 + (560.0 / math.max(1, loads.length)) * (i + .5), 230);
    }
    for (var i = 0; i < ctrls.length; i++) {
      pos[ctrls[i].id] = Offset(250 + (600.0 / math.max(1, ctrls.length)) * (i + .5), 535);
    }
    for (var i = 0; i < sockets.length; i++) {
      pos[sockets[i].id] = Offset(905, 200 + i * 140.0);
    }
    for (var i = 0; i < extra.length; i++) {
      pos[extra[i].id] = Offset(200, 120 + i * 90.0);
    }
    String place(String term) {
      final id = term.split('.').first;
      return const {'G1', 'Q1', 'Q2', 'NB', 'EB', 'M1'}.contains(id) ? 'DB' : id;
    }

    // count conductors between places
    final runs = <String, int>{};
    for (final w in c.referenceWires()) {
      final a = place(w.a), b = place(w.b);
      if (a == b || !pos.containsKey(a) || !pos.containsKey(b)) continue;
      final key = ([a, b]..sort()).join('|');
      runs[key] = (runs[key] ?? 0) + 1;
    }
    final line = Paint()
      ..color = ink
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    runs.forEach((key, n) {
      final ab = key.split('|');
      final a = pos[ab[0]]!, b = pos[ab[1]]!;
      final mid = Offset(b.dx, a.dy);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(path, line);
      final m = path.computeMetrics().first;
      final tan = m.getTangentForOffset(m.length / 2)!;
      final dir = tan.vector;
      final nrm = Offset(-dir.dy, dir.dx);
      for (var i = 0; i < n; i++) {
        final o = tan.position + dir * ((i - (n - 1) / 2) * 7);
        canvas.drawLine(o - nrm * 7 - dir * 3, o + nrm * 7 + dir * 3, line);
      }
    });
    // symbols
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = Colors.white;
    // board
    final db = pos['DB']!;
    canvas.drawRect(Rect.fromCenter(center: db, width: 40, height: 70), Paint()..color = ink);
    text(canvas, 'لوحة', db + const Offset(0, 50), size: 13, color: ink);
    for (final p in parts) {
      final o = pos[p.id];
      if (o == null) continue;
      switch (p.kind) {
        case Kind.lamp:
          canvas.drawCircle(o, 18, fill);
          canvas.drawCircle(o, 18, pen);
          canvas.drawLine(o + const Offset(-13, -13), o + const Offset(13, 13), pen);
          canvas.drawLine(o + const Offset(13, -13), o + const Offset(-13, 13), pen);
        case Kind.tube:
          canvas.drawRect(Rect.fromCenter(center: o, width: 90, height: 14), fill);
          canvas.drawRect(Rect.fromCenter(center: o, width: 90, height: 14), pen);
          canvas.drawLine(o + const Offset(-45, -12), o + const Offset(-45, 12), pen);
          canvas.drawLine(o + const Offset(45, -12), o + const Offset(45, 12), pen);
        case Kind.ledpanel:
          canvas.drawRect(Rect.fromCenter(center: o, width: 40, height: 40), fill);
          canvas.drawRect(Rect.fromCenter(center: o, width: 40, height: 40), pen);
          canvas.drawLine(o + const Offset(-20, -20), o + const Offset(20, 20), pen);
        case Kind.bell:
          canvas.drawArc(Rect.fromCircle(center: o, radius: 18), math.pi, math.pi, true, pen);
        case Kind.lock:
          canvas.drawRect(Rect.fromCenter(center: o, width: 30, height: 30), pen);
          text(canvas, 'ك', o, size: 14, color: ink);
        case Kind.socket:
          canvas.drawArc(Rect.fromCircle(center: o, radius: 18), math.pi / 2, math.pi, false, pen);
          canvas.drawLine(o + const Offset(0, -18), o + const Offset(0, 18), pen);
          canvas.drawLine(o + const Offset(-24, 0), o + const Offset(-18, 0), pen);
        case Kind.sw1:
        case Kind.sw2:
        case Kind.swi:
        case Kind.swd:
        case Kind.dimmer:
          canvas.drawCircle(o, 8, Paint()..color = ink);
          final d = const Offset(16, -22);
          canvas.drawLine(o, o + d, pen);
          canvas.drawLine(o + d, o + d + const Offset(8, 4), pen);
          if (p.kind == Kind.sw2 || p.kind == Kind.swi) canvas.drawLine(o, o + const Offset(-16, 22), pen);
          if (p.kind == Kind.swi) canvas.drawLine(o + const Offset(-16, -22), o + const Offset(16, 22), pen);
          if (p.kind == Kind.swd) canvas.drawLine(o, o + const Offset(-8, -26), pen);
          if (p.kind == Kind.dimmer) canvas.drawLine(o + const Offset(-14, 8), o + const Offset(10, -14), pen);
        case Kind.pb:
          canvas.drawCircle(o, 10, pen);
          canvas.drawCircle(o, 4, Paint()..color = ink);
        default:
          canvas.drawRect(Rect.fromCenter(center: o, width: 46, height: 30), fill);
          canvas.drawRect(Rect.fromCenter(center: o, width: 46, height: 30), pen);
          text(canvas, p.kind == Kind.stair ? 'T' : p.kind == Kind.driver ? 'DR' : p.kind == Kind.rcd ? 'RCD' : p.id, o, size: 11, color: ink);
      }
      text(canvas, p.id, o + const Offset(0, -32), size: 12, color: const Color(0xFF1B4FA0), w: FontWeight.w700);
    }
  }

  @override
  bool shouldRepaint(PlanPainter o) => o.c != c;
}
