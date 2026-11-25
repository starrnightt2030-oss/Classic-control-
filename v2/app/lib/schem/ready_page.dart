// «المخططات الجاهزة»: every classic control circuit drawn with IEC symbols; open one
// to read it, simulate it, change it or print it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../ui/theme.dart';
import 'ladder.dart';
import 'model.dart';
import 'schem_page.dart';
import 'sheet_paint.dart';
import 'symbols.dart';

class ReadyDiagramsPage extends StatelessWidget {
  const ReadyDiagramsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ReadyCircuit>>{};
    for (final r in kReady) {
      (groups[r.group] ??= []).add(r);
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1200 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
      final pad = c.maxWidth >= 900 ? 28.0 : 14.0;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 4),
          sliver: const SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المخططات الجاهزة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('مخطط القوى ومخطط التحكم لكل دائرة برموز IEC 60617. افتح المخطط لتقرأه، أو شغّله بالمحاكاة، أو اطبعه.',
                  style: TextStyle(color: CC.text2, height: 1.6)),
            ]),
          ),
        ),
        for (final g in groups.entries) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 18, pad, 8),
            sliver: SliverToBoxAdapter(child: Text(g.key, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: CC.accentSoft))),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 250),
              delegate: SliverChildBuilderDelegate((context, i) => _Card(g.value[i]), childCount: g.value.length),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]);
    });
  }
}

class _Card extends StatefulWidget {
  final ReadyCircuit r;
  const _Card(this.r);
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  late final SchemDoc doc = widget.r.build();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SchemPage(initial: widget.r.build(), deliver: (b, n, m) => ExportService.deliverBytes(b, n, mime: m)))),
        child: Ink(
          decoration: panelBox(radius: 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(color: Colors.white, child: CustomPaint(painter: _Mini(doc), size: Size.infinite)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(widget.r.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: CC.text2, fontSize: 12.5, height: 1.45)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Mini extends CustomPainter {
  final SchemDoc doc;
  _Mini(this.doc);
  @override
  void paint(Canvas c, Size size) {
    final w = doc.sheetW * kG, h = doc.sheetH * kG;
    final s = math.min(size.width / w, size.height / h);
    c.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    c.scale(s);
    SheetPainter(doc, print: true).paint(c, Size(w, h));
  }

  @override
  bool shouldRepaint(covariant _Mini old) => false;
}
