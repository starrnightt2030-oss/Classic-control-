// «خطوط الإنتاج»: the 15 production-line projects by level. A card shows the line's
// machine (its Blender sprite); a tap opens the brief (story, what you build, the
// devices and the faults to practise), and a ready line opens in the panel lab.
import 'package:flutter/material.dart';

import '../lab/lab_page.dart';
import '../ui/section_pages.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'lines.dart';

/// machines with a Blender sprite in assets/panel (mach_<kind>_base.webp)
const _sprites = {'belt', 'fan', 'gate', 'press', 'fill', 'sort', 'lift', 'hoist', 'cart'};

String? lineImage(ProdLine l) {
  final k = l.machine.substring(5);
  return _sprites.contains(k) ? 'assets/panel/mach_${k}_base.webp' : null;
}

class LinesPage extends StatelessWidget {
  const LinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ready = kLines.where((l) => l.ready).length;
    return SectionScaffold(
      title: 'خطوط الإنتاج',
      child: LayoutBuilder(builder: (context, box) {
        final pad = box.maxWidth >= 900 ? 28.0 : 16.0;
        final cols = box.maxWidth >= 1100 ? 3 : box.maxWidth >= 640 ? 2 : 1;
        return ListView(padding: EdgeInsets.fromLTRB(pad, 6, pad, 28), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: panelBox(color: CC.cyanBg, border: CC.cyanLine, radius: 14),
            child: Text(
              '${kLines.length} مشروع تحكم كلاسيك من مصانع حقيقية، من غير PLC. كل خط ماكينة مجسمة جنب اللوحة: '
              'توصّل الدايرة بإيدك، تشغّل، وتشوف الماكينة بتتحرك بدايرتك. جاهز منهم $ready، والباقي بيتبني.',
              style: const TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFCDF3F8)),
            ),
          ),
          for (final lv in kLineLevels.entries) ...[
            const SizedBox(height: 18),
            SectionTitle(lv.value.$1),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(lv.value.$2, style: const TextStyle(color: CC.muted, fontSize: 12.5)),
            ),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cols == 1 ? 2.5 : 2.1,
              children: [for (final l in kLines.where((l) => l.level == lv.key)) _LineTile(line: l, onTap: () => showLineBrief(context, l))],
            ),
          ],
        ]);
      }),
    );
  }
}

class _LineTile extends StatelessWidget {
  final ProdLine line;
  final VoidCallback onTap;
  const _LineTile({required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = lineImage(line);
    return Material(
      color: const Color(0x12FFFFFF),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: line.ready ? CC.cyanLine : CC.glassBorder)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 104,
              decoration: BoxDecoration(color: const Color(0xFF0E1A30), borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.all(4),
              child: img == null
                  ? const Icon(Icons.precision_manufacturing_outlined, color: CC.muted, size: 40)
                  : Opacity(opacity: line.ready ? 1 : 0.55, child: Image.asset(img, fit: BoxFit.contain)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${line.n}', style: const TextStyle(fontFamily: CC.mono, fontWeight: FontWeight.w700, color: CC.amber)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line.short, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 3),
                Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: CC.muted, height: 1.4)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: panelBox(color: line.ready ? CC.cyanBg : CC.amberBg, border: line.ready ? CC.cyanLine : CC.amberLine, radius: 20),
                  child: Text(line.ready ? 'جاهز للتوصيل' : 'قريبًا', style: TextStyle(fontSize: 11.5, color: line.ready ? CC.cyan : CC.amber)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// the line's brief; a ready line opens in the panel lab from here
Future<void> showLineBrief(BuildContext context, ProdLine l) {
  final img = lineImage(l);
  Widget list(String title, List<String> items, IconData icon, Color col) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: col),
                const SizedBox(width: 8),
                Expanded(child: Text(items[i], style: const TextStyle(fontSize: 13.5, height: 1.5, color: CC.text2))),
              ]),
            ),
        ]),
      );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        if (img != null)
          Container(
            height: 170,
            decoration: BoxDecoration(color: const Color(0xFF0E1A30), borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(8),
            child: Image.asset(img, fit: BoxFit.contain),
          ),
        const SizedBox(height: 12),
        Text('${l.n}. ${l.short}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(l.title, style: const TextStyle(color: CC.cyan, fontSize: 13.5)),
        const SizedBox(height: 10),
        Text(l.story, style: const TextStyle(height: 1.7, fontSize: 14)),
        list('هتعمل إيه', l.steps, Icons.check_circle_outline_rounded, CC.green),
        list('المكونات', l.parts, Icons.memory_rounded, CC.cyan),
        list('أعطال تتدرب تدوّر عليها', l.faults, Icons.build_circle_outlined, CC.gold),
        const SizedBox(height: 18),
        if (l.ready)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabPage(exercise: l.circuit)));
            },
            icon: const Icon(Icons.cable_rounded),
            label: const Text('ابدأ التوصيل في معمل اللوحة'),
          )
        else
          const OutlinedButton(onPressed: null, child: Text('الخط ده بيتبني، وهينزل في تحديث قريب')),
      ]),
    ),
  );
}
