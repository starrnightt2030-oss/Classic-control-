import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/audio_service.dart';
import 'icons.dart';
import 'theme.dart';
import 'viewer3d.dart';
import 'widgets.dart';

class ComponentPage extends StatefulWidget {
  final String componentId;
  const ComponentPage({super.key, required this.componentId});

  @override
  State<ComponentPage> createState() => _ComponentPageState();
}

class _ComponentPageState extends State<ComponentPage> with SingleTickerProviderStateMixin {
  late final Component c;
  late String _model;
  final _viewer = Viewer3DController();
  late final TabController _tabs;
  String? _selected;
  bool _exploded = false;
  bool _labels = true;

  bool get _hasParts => c.parts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    c = Repository.instance.byId(widget.componentId)!;
    _model = c.model;
    _tabs = TabController(length: _hasParts ? 4 : 2, vsync: this);
    Repository.instance.setLastComponent(c.id);
    _viewer.load(_model);
  }

  @override
  void dispose() {
    _tabs.dispose();
    AudioService.instance.stopVoice();
    super.dispose();
  }

  void _onPart(String? id) {
    setState(() => _selected = id);
    if (id == null) return;
    Repository.instance.markSeen(c.id, id);
    if (_tabs.index != 0) _tabs.animateTo(0);
    final part = c.partById(id);
    AudioService.instance.playVoice(part?.audio).then((ok) {
      if (!ok) AudioService.instance.sfx('part_select');
    });
  }

  void _pickFromList(String id) {
    _viewer.select(id);
    _onPart(id);
  }

  void _setExploded(bool v) {
    if (v == _exploded) return;
    setState(() => _exploded = v);
    _viewer.setExplode(v ? 1 : 0);
    AudioService.instance.sfx(v ? 'explode_whoosh' : 'assemble_snap');
  }

  void _setModel(String m) {
    if (m == _model) return;
    setState(() {
      _model = m;
      _selected = null;
      _exploded = false;
    });
    _viewer.load(m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900 || box.maxWidth > box.maxHeight * 1.15;
          final header = _header();
          final stage = _stage(compact: !wide);
          final info = _info();
          if (wide) {
            final panelW = box.maxWidth >= 1200 ? 440.0 : (box.maxWidth >= 900 ? 380.0 : 320.0);
            return Row(children: [
              Expanded(child: Column(children: [header, Expanded(child: stage)])),
              Container(
                width: panelW,
                decoration: const BoxDecoration(
                  color: CC.surface,
                  border: BorderDirectional(start: BorderSide(color: CC.line)),
                ),
                child: info,
              ),
            ]);
          }
          return Column(children: [
            header,
            SizedBox(height: box.maxHeight * 0.47, child: stage),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  color: CC.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(top: BorderSide(color: CC.line)),
                ),
                child: info,
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _header() {
    final ref = c.references.isNotEmpty ? c.references.first.split(':').first.trim() : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(children: [
        SquareButton(icon: CcIcons.back, label: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.nameAr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
            Text(
              ref.isEmpty ? c.nameEn : '${c.nameEn} · $ref',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: CC.muted, fontFamily: CC.mono),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stage({required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      child: Column(children: [
        if (c.variants.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final v in c.variants) Center(child: Pill(label: variantLabel(v), selected: v == _model, onTap: () => _setModel(v))),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF222C35)), borderRadius: BorderRadius.circular(20)),
              child: Viewer3D(controller: _viewer, onPart: _onPart),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (_hasParts)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: panelBox(color: CC.bg, radius: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _seg('مُجمّع', !_exploded, () => _setExploded(false)),
                _seg('مفكوك', _exploded, () => _setExploded(true)),
              ]),
            ),
          const Spacer(),
          if (_hasParts) ...[
            SquareButton(icon: CcIcons.tag, label: _labels ? 'إخفاء الأسماء' : 'إظهار الأسماء', active: _labels, onTap: () {
              setState(() => _labels = !_labels);
              _viewer.setLabels(_labels);
            }),
            const SizedBox(width: 8),
          ],
          SquareButton(icon: CcIcons.reset, label: 'إعادة الكاميرا', onTap: _viewer.reset),
        ]),
        SizedBox(height: compact ? 4 : 12),
      ]),
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) {
    return Material(
      color: on ? CC.amber : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? CC.bg : CC.text2)),
        ),
      ),
    );
  }

  // ---------------- info panel ----------------
  Widget _info() {
    final tabs = <Tab>[
      if (_hasParts) const Tab(text: 'الجزء'),
      if (_hasParts) const Tab(text: 'الأجزاء'),
      const Tab(text: 'الدروس'),
      const Tab(text: 'عن المكوّن'),
    ];
    final views = <Widget>[
      if (_hasParts) _partView(),
      if (_hasParts) _partsList(),
      _lessons(),
      _about(),
    ];
    return Column(children: [
      const SizedBox(height: 6),
      TabBar(
        controller: _tabs,
        isScrollable: false,
        labelColor: CC.text,
        unselectedLabelColor: CC.muted,
        indicatorColor: CC.amber,
        dividerColor: CC.line,
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5, fontWeight: FontWeight.w600),
        tabs: tabs,
      ),
      Expanded(child: TabBarView(controller: _tabs, children: views)),
    ]);
  }

  Widget _partView() {
    final p = c.partById(_selected);
    if (p == null) {
      return ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: panelBox(color: CC.cyanBg, border: CC.cyanLine, radius: 14),
          child: const Row(children: [
            CcIcon(CcIcons.explode, color: CC.cyan),
            SizedBox(width: 12),
            Expanded(
              child: Text('المس أي جزء في المجسم، أو اختاره من «الأجزاء»، وهتلاقي شرحه هنا وتسمعه.',
                  style: TextStyle(fontSize: 14, height: 1.7, color: Color(0xFFCDF3F8))),
            ),
          ]),
        ),
        if (c.intro != null) ...[
          const SizedBox(height: 18),
          _clipBlock('مقدمة', c.intro!.text, c.intro!.audio),
        ],
      ]);
    }
    final idx = c.parts.indexOf(p) + 1;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: CC.amber, borderRadius: BorderRadius.circular(10)),
          child: Text('$idx', style: const TextStyle(fontFamily: CC.mono, fontWeight: FontWeight.w700, color: CC.bg)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nameAr, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
            Text(p.nameEn, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: CC.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        VoiceButton(audioRef: p.audio),
      ]),
      const SizedBox(height: 14),
      Text(p.text, style: const TextStyle(fontSize: 15, height: 1.85, color: Color(0xFFD5DEE4))),
      if ((p.fault ?? '').isNotEmpty) ...[
        const SizedBox(height: 14),
        _note(CcIcons.warning, 'العطل الشائع', p.fault!, CC.amber, const Color(0xFF1E1A0E), CC.amberLine),
      ],
      if ((p.test ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        _note(CcIcons.meter, 'إزاي تختبره', p.test!, CC.cyan, CC.cyanBg, CC.cyanLine),
      ],
    ]);
  }

  Widget _note(String icon, String title, String text, Color accent, Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: panelBox(color: bg, border: border, radius: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CcIcon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: accent)),
        ]),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 14, height: 1.75, color: CC.text2)),
      ]),
    );
  }

  Widget _partsList() {
    final seen = Repository.instance.seenParts(c.id);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
      itemCount: c.parts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final p = c.parts[i];
        final on = p.id == _selected;
        return Material(
          color: on ? CC.amberBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickFromList(p.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: on ? CC.amber : CC.surface2, borderRadius: BorderRadius.circular(7)),
                  child: Text('${i + 1}',
                      style: TextStyle(fontFamily: CC.mono, fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? CC.bg : CC.text2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.nameAr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(p.nameEn, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: CC.muted)),
                  ]),
                ),
                if (seen.contains(p.id)) const Icon(Icons.check_circle_rounded, size: 18, color: CC.green),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _lessons() {
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
      if (c.opening != null) ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _clipBlock('افتتاحية الدرس', c.opening!.text, c.opening!.audio)),
        const SizedBox(height: 12),
      ],
      for (var i = 0; i < c.lessons.length; i++) _lessonTile(i, c.lessons[i]),
      if (c.closing != null) ...[
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _clipBlock('الخلاصة', c.closing!.text, c.closing!.audio)),
      ],
    ]);
  }

  Widget _lessonTile(int i, Lesson l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: panelBox(color: CC.bg, radius: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: CC.amber,
          collapsedIconColor: CC.muted,
          leading: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: CC.surface2, borderRadius: BorderRadius.circular(13)),
            child: Text('${i + 1}', style: const TextStyle(fontFamily: CC.mono, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          title: Text(l.titleAr, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          subtitle: Text(l.titleEn, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: CC.muted)),
          children: [
            Align(alignment: AlignmentDirectional.centerEnd, child: VoiceButton(audioRef: l.audio, size: 40)),
            const SizedBox(height: 8),
            Text(l.text, style: const TextStyle(fontSize: 14.5, height: 1.85, color: Color(0xFFD5DEE4))),
          ],
        ),
      ),
    );
  }

  Widget _clipBlock(String title, String text, String? audio) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CC.text2))),
        VoiceButton(audioRef: audio, size: 40),
      ]),
      const SizedBox(height: 6),
      Text(text, style: const TextStyle(fontSize: 14.5, height: 1.85, color: Color(0xFFD5DEE4))),
    ]);
  }

  Widget _about() {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
      if (c.intro != null) _clipBlock('التعريف', c.intro!.text, c.intro!.audio),
      if (c.variants.length > 1) ...[
        const SizedBox(height: 18),
        const SectionTitle('الأنواع الموجودة'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in c.variants)
            Pill(label: variantLabel(v), selected: v == _model, onTap: () => _setModel(v)),
        ]),
      ],
      if (c.references.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('المراجع والمواصفات'),
        const SizedBox(height: 8),
        for (final r in c.references)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(r, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: CC.text2, fontFamily: CC.mono)),
          ),
      ],
    ]);
  }
}
