import 'package:flutter/material.dart';

import '../services/export_service.dart';
import 'lesson_sheet_page.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/audio_service.dart';
import 'icons.dart';
import 'theme.dart';
import 'viewer3d.dart';
import 'widgets.dart';

enum AutoAction { none, sheet, video }

class ComponentPage extends StatefulWidget {
  final String componentId;
  final AutoAction autoAction;
  const ComponentPage({super.key, required this.componentId, this.autoAction = AutoAction.none});

  @override
  State<ComponentPage> createState() => _ComponentPageState();
}

class _ComponentPageState extends State<ComponentPage> with SingleTickerProviderStateMixin {
  late final Component c;
  late String _model;
  final _viewer = Viewer3DController();
  late final TabController _tabs;
  String? _selected;
  double _explode = 0;
  bool _labels = true;
  bool _working = false;

  bool get _hasParts => c.parts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    c = Repository.instance.byId(widget.componentId)!;
    _model = c.model;
    _tabs = TabController(length: _hasParts ? 4 : 2, vsync: this);
    Repository.instance.setLastComponent(c.id);
    _viewer.load(_model, nameAr: c.nameAr, nameEn: c.nameEn);
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

  bool _autoDone = false;
  void _onLoaded() {
    if (_autoDone || widget.autoAction == AutoAction.none) return;
    _autoDone = true;
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (widget.autoAction == AutoAction.sheet) _openSheet();
      if (widget.autoAction == AutoAction.video) _makeVideo();
    });
  }

  void _pickFromList(String id) {
    _viewer.focus(id);
    _onPart(id);
  }

  void _scrub(double v) {
    setState(() => _explode = v);
    _viewer.scrub(v);
  }

  void _snapTo(double v) {
    setState(() => _explode = v);
    _viewer.setExplode(v);
    AudioService.instance.sfx(v > 0.5 ? 'explode_whoosh' : 'assemble_snap');
  }

  Future<void> _openSheet() async {
    if (_working) return;
    setState(() => _working = true);
    final shots = await _viewer.captureSheet();
    if (!mounted) return;
    setState(() => _working = false);
    if (shots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('استنى المجسم يحمّل وجرّب تاني.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonSheetPage(component: c, shots: shots)));
  }

  Future<void> _makeVideo() async {
    if (_working) return;
    setState(() => _working = true);
    final file = await _viewer.recordVideo();
    if (!mounted) return;
    setState(() {
      _working = false;
      _explode = 0;
    });
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الجهاز ده مش بيدعم تسجيل الفيديو من العارض.')));
      return;
    }
    final ext = file.path.split('.').last;
    final mb = (await file.length()) / (1024 * 1024);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CC.surface,
        title: const Text('فيديو الشرح جاهز', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('${c.nameAr} · فيديو ${ext.toUpperCase()} · ${mb.toStringAsFixed(1)} ميجا\nتقدر تحفظه أو تبعته.',
            style: const TextStyle(height: 1.7, color: CC.text2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CC.amber, foregroundColor: CC.bg),
            onPressed: () async {
              Navigator.pop(ctx);
              await ExportService.deliverFile(file, 'ControlAcademy_${ExportService.safeName(c.nameEn)}.$ext',
                  mime: ext == 'mp4' ? 'video/mp4' : 'video/webm', text: c.nameAr);
            },
            child: const Text('حفظ / مشاركة'),
          ),
        ],
      ),
    );
  }

  void _setModel(String m) {
    if (m == _model) return;
    setState(() {
      _model = m;
      _selected = null;
      _explode = 0;
    });
    _viewer.load(m, nameAr: c.nameAr, nameEn: c.nameEn);
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
        const SizedBox(width: 8),
        SquareButton(icon: CcIcons.sheet, label: 'ورقة الدرس (صورة / PDF)', onTap: _working ? null : _openSheet),
        const SizedBox(width: 8),
        SquareButton(icon: CcIcons.film, label: 'فيديو الشرح', onTap: _working ? null : _makeVideo),
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
              child: Stack(children: [
                Positioned.fill(child: Viewer3D(controller: _viewer, onPart: _onPart, onLoaded: _onLoaded)),
                PositionedDirectional(
                  top: 10,
                  start: 10,
                  end: 10,
                  child: ValueListenableBuilder<int?>(
                    valueListenable: _viewer.progress,
                    builder: (context, p, _) {
                      if (p == null && !_working) return const SizedBox.shrink();
                      return Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: panelBox(color: const Color(0xE60B0F12), radius: 10, border: CC.amberLine),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: CC.amber)),
                            const SizedBox(width: 10),
                            Text(p == null ? 'جاري تجهيز الصور…' : 'بيتسجّل الفيديو… $p%',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          if (_hasParts) ...[
            Tooltip(
              message: 'تركيب',
              child: IconButton(
                onPressed: _working ? null : () => _snapTo(0),
                icon: const CcIcon(CcIcons.assemble, size: 22, color: CC.text2),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: CC.amber,
                  inactiveTrackColor: CC.line,
                  thumbColor: CC.amber,
                  overlayColor: CC.amber.withValues(alpha: 0.15),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                ),
                child: Semantics(
                  label: 'التحكم في الفك والتركيب',
                  child: Slider(value: _explode, onChanged: _working ? null : _scrub),
                ),
              ),
            ),
            Tooltip(
              message: 'فك',
              child: IconButton(
                onPressed: _working ? null : () => _snapTo(1),
                icon: const CcIcon(CcIcons.explode, size: 22, color: CC.text2),
              ),
            ),
            const SizedBox(width: 4),
            SquareButton(icon: CcIcons.tag, label: _labels ? 'إخفاء الأسماء والأرقام' : 'إظهار الأسماء والأرقام', active: _labels, onTap: () {
              setState(() => _labels = !_labels);
              _viewer.setLabels(_labels);
            }),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          SquareButton(icon: CcIcons.reset, label: 'إعادة الكاميرا', onTap: _viewer.reset),
        ]),
        SizedBox(height: compact ? 4 : 12),
      ]),
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
