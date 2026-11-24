import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'component_page.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _cat;
  String _q = '';

  bool _match(Component c) {
    if (_cat != null && categoryOf(c.id) != _cat) return false;
    if (_q.trim().isEmpty) return true;
    final q = _q.trim().toLowerCase();
    if (c.nameAr.contains(q) || c.nameEn.toLowerCase().contains(q) || c.id.contains(q)) return true;
    for (final p in c.parts) {
      if (p.nameAr.contains(q) || p.nameEn.toLowerCase().contains(q)) return true;
    }
    for (final v in c.variants) {
      if (variantLabel(v).toLowerCase().contains(q) || v.contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final items = Repository.instance.all.where(_match).toList();
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 8),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مكتبة المكونات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const Text('كل مكوّن بمجسم حقيقي، أجزاؤه بتتفك، وكل جزء ليه شرح',
                  style: TextStyle(fontSize: 13.5, color: CC.muted)),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الجزء… مثلاً كويل أو MCB',
                  hintStyle: const TextStyle(color: CC.muted),
                  prefixIcon: const Padding(padding: EdgeInsets.all(12), child: CcIcon(CcIcons.search, size: 20, color: CC.muted)),
                  filled: true,
                  fillColor: CC.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CC.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CC.amber)),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Pill(label: 'الكل', selected: _cat == null, onTap: () => setState(() => _cat = null)),
                  for (final cat in categories)
                    Pill(label: cat.nameAr, selected: _cat == cat.id, onTap: () => setState(() => _cat = cat.id)),
                ]),
              ),
            ]),
          ),
        ),
        if (items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('مفيش نتايج. جرّب كلمة تانية.', style: TextStyle(color: CC.muted))),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.86,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ComponentCard(component: items[i], onChanged: () => setState(() {})),
                childCount: items.length,
              ),
            ),
          ),
      ]);
    });
  }
}

class _ComponentCard extends StatelessWidget {
  final Component component;
  final VoidCallback onChanged;
  const _ComponentCard({required this.component, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final seen = Repository.instance.seenParts(component.id).length;
    final total = component.parts.length;
    return Material(
      color: CC.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: CC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComponentPage(componentId: component.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Center(child: Hero(tag: 'thumb_${component.id}', child: Thumb(component.id, size: 140)))),
            Text(component.nameAr,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(
                child: Text(
                  total > 0 ? '$total جزء${component.variants.length > 1 ? ' · ${component.variants.length} أنواع' : ''}' : '${component.variants.length} أنواع',
                  style: const TextStyle(fontSize: 11.5, color: CC.muted),
                ),
              ),
              if (total > 0 && seen >= total) const Icon(Icons.check_circle_rounded, size: 16, color: CC.green),
            ]),
          ]),
        ),
      ),
    );
  }
}
