import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'cards.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Library: one swipeable card row per category; typing a search switches to a grid.
class LibraryPage extends StatefulWidget {
  final bool embedded;
  const LibraryPage({super.key, this.embedded = false});
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
    final repo = Repository.instance;
    final searching = _q.trim().isNotEmpty;
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
      final cw = c.maxWidth >= 900 ? 190.0 : 156.0;
      final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!widget.embedded) ...[
          const Text('مكتبة المكونات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          Text('${repo.all.length} مكوّن · اسحب الكروت يمين وشمال، واضغط على أي كارت يفتح',
              style: const TextStyle(fontSize: 13, color: CC.muted)),
          const SizedBox(height: 12),
        ],
        TextField(
          onChanged: (v) => setState(() => _q = v),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو الجزء… مثلاً كويل أو MCB',
            hintStyle: const TextStyle(color: CC.muted),
            prefixIcon: const Padding(padding: EdgeInsets.all(12), child: CcIcon(CcIcons.search, size: 20, color: CC.muted)),
            filled: true,
            fillColor: const Color(0x14FFFFFF),
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
            for (final cat in categories) Pill(label: cat.nameAr, selected: _cat == cat.id, onTap: () => setState(() => _cat = cat.id)),
          ]),
        ),
        const SizedBox(height: 16),
      ]);

      if (searching) {
        final items = repo.all.where(_match).toList();
        return CustomScrollView(slivers: [
          SliverPadding(padding: EdgeInsets.fromLTRB(pad, 14, pad, 0), sliver: SliverToBoxAdapter(child: header)),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('مفيش نتايج. جرّب كلمة تانية.', style: TextStyle(color: CC.muted))),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: cw + 30,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => ComponentCard(component: items[i], width: double.infinity, onClosed: () => setState(() {})),
                  childCount: items.length,
                ),
              ),
            ),
        ]);
      }

      final cats = _cat == null ? categories : categories.where((x) => x.id == _cat).toList();
      return ListView(padding: EdgeInsets.fromLTRB(pad, 14, pad, 28), children: [
        header,
        for (final cat in cats) ...[
          ComponentRow(
            title: cat.nameAr,
            items: [for (final id in cat.components) if (repo.byId(id) != null) repo.byId(id)!],
            cardWidth: cw,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 20),
        ],
      ]);
    });
  }
}
