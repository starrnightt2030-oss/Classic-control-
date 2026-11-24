import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import '../data/models.dart';
import '../services/export_service.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// A formatted, printable lesson sheet for one component:
/// header, assembled + labelled exploded views, definition, numbered parts with
/// their explanation, the lessons, references. Exported as PNG or PDF.
class LessonSheetPage extends StatefulWidget {
  final Component component;
  final List<File> shots; // [assembled, exploded?]
  const LessonSheetPage({super.key, required this.component, required this.shots});

  @override
  State<LessonSheetPage> createState() => _LessonSheetPageState();
}

class _LessonSheetPageState extends State<LessonSheetPage> {
  static const double sheetW = 1000;
  final _whole = GlobalKey();
  final List<GlobalKey> _sections = [];
  int _secIndex = 0;
  final _tc = TransformationController();
  bool _busy = false;
  bool _fitted = false;

  Component get c => widget.component;

  @override
  Widget build(BuildContext context) {
    _secIndex = 0;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(children: [
              SquareButton(icon: CcIcons.back, label: 'رجوع', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ورقة الدرس', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(c.nameAr, style: const TextStyle(fontSize: 12.5, color: CC.muted)),
                ]),
              ),
              _action('صورة PNG', Icons.image_outlined, _busy ? null : _exportPng),
              const SizedBox(width: 8),
              _action('PDF', Icons.picture_as_pdf_outlined, _busy ? null : _exportPdf),
            ]),
          ),
          if (_busy) const LinearProgressIndicator(color: CC.amber, backgroundColor: CC.line, minHeight: 2),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              if (!_fitted) {
                final s = math.min(1.0, (box.maxWidth - 16) / sheetW);
                _tc.value = Matrix4.identity()
                  ..translate((box.maxWidth - sheetW * s) / 2, 8.0)
                  ..scale(s);
                _fitted = true;
              }
              return Container(
                color: const Color(0xFF05080B),
                child: InteractiveViewer(
                  transformationController: _tc,
                  constrained: false,
                  minScale: 0.15,
                  maxScale: 3,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: RepaintBoundary(key: _whole, child: _sheet()),
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback? onTap) => FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: CC.amber,
          foregroundColor: CC.bg,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  // ------------------------------------------------------------ the sheet
  Widget _sec(Widget child) {
    if (_secIndex >= _sections.length) _sections.add(GlobalKey());
    final k = _sections[_secIndex++];
    return RepaintBoundary(key: k, child: Container(color: _paper, child: child));
  }

  static const _paper = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF111820);
  static const _ink2 = Color(0xFF46535E);
  static const _gold = Color(0xFFD99500);
  static const _rule = Color(0xFFE3E8EC);

  Widget _sheet() {
    final parts = c.parts;
    final chunks = <List<int>>[];
    for (var i = 0; i < parts.length; i += 4) {
      chunks.add([for (var j = i; j < math.min(i + 4, parts.length); j++) j]);
    }
    final ref = c.references.isNotEmpty ? c.references.first.split(':').first.trim() : '';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Cairo', color: _ink, fontSize: 15, height: 1.75),
        child: SizedBox(
          width: sheetW,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            _sec(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: const Color(0xFF0B1220),
                padding: const EdgeInsets.fromLTRB(36, 22, 36, 22),
                child: Row(children: [
                  Image.asset('assets/images/logo_small.webp', width: 70, height: 70),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.nameAr, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700, height: 1.3)),
                      Text(ref.isEmpty ? c.nameEn : '${c.nameEn}  ·  $ref',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(color: Color(0xFFB9C6D1), fontSize: 15, fontFamily: CC.mono)),
                    ]),
                  ),
                  const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(AppInfo.brandEn, style: TextStyle(color: CC.amber, fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('ورقة درس', style: TextStyle(color: Color(0xFFB9C6D1), fontSize: 13)),
                  ]),
                ]),
              ),
              Container(height: 5, color: _gold),
              if (widget.shots.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 6),
                  child: _figure(widget.shots[1], 'الأجزاء الداخلية (مفكوك) — الأرقام زي جدول الأجزاء'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.shots.isNotEmpty) SizedBox(width: 380, child: _figure(widget.shots[0], 'الشكل الخارجي')),
                  if (widget.shots.isNotEmpty) const SizedBox(width: 24),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _h('التعريف'),
                      Text(c.intro?.text ?? '', style: const TextStyle(fontSize: 15, color: _ink)),
                    ]),
                  ),
                ]),
              ),
            ])),
            for (var ci = 0; ci < chunks.length; ci++)
              _sec(Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (ci == 0) _h('الأجزاء وشرحها'),
                  for (final i in chunks[ci]) _partRow(i + 1, parts[i]),
                ]),
              )),
            for (var li = 0; li < c.lessons.length; li++)
              _sec(Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (li == 0) _h('الدرس'),
                  Row(children: [
                    _num(li + 1, dark: true),
                    const SizedBox(width: 10),
                    Text(c.lessons[li].titleAr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Text(c.lessons[li].titleEn, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: _ink2)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(right: 38, top: 2, bottom: 6),
                    child: Text(c.lessons[li].text, style: const TextStyle(fontSize: 14.5)),
                  ),
                ]),
              )),
            _sec(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (c.references.isNotEmpty) ...[
                    _h('المراجع'),
                    for (final r in c.references)
                      Text(r, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: _ink2, fontFamily: CC.mono)),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF6E0), border: Border.all(color: const Color(0xFFF0D48A)), borderRadius: BorderRadius.circular(10)),
                    child: const Text('قاعدة السلامة: افصل، اقفل، علّق الكارت، واتأكد بالأفوميتر قبل ما تلمس.',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6B4A00))),
                  ),
                ]),
              ),
              Container(
                color: const Color(0xFF0B1220),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                child: Row(children: [
                  Image.asset(AppInfo.orgLogo, width: 34, height: 34),
                  const SizedBox(width: 10),
                  const Text('${AppInfo.organization} · ${AppInfo.brandEn}', style: TextStyle(color: Color(0xFFB9C6D1), fontSize: 12)),
                  const Spacer(),
                  const Text('تطوير: ${AppInfo.developer} · v${AppInfo.version}', style: TextStyle(color: Color(0xFFB9C6D1), fontSize: 12)),
                ]),
              ),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 6),
        child: Row(children: [
          Container(width: 6, height: 22, decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _num(int n, {bool dark = false}) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: dark ? const Color(0xFF0B1220) : CC.amber, borderRadius: BorderRadius.circular(7)),
        child: Text('$n', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: dark ? Colors.white : _ink, height: 1.2)),
      );

  Widget _figure(File f, String caption) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(f, fit: BoxFit.cover)),
        const SizedBox(height: 4),
        Text(caption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _ink2)),
      ]);

  Widget _partRow(int n, Part p) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _rule))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _num(n),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(p.nameAr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
                const SizedBox(width: 10),
                Flexible(child: Text(p.nameEn, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: _ink2))),
              ]),
              Text(p.text, style: const TextStyle(fontSize: 14)),
              if ((p.fault ?? '').isNotEmpty)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'العطل: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB06A00))),
                  TextSpan(text: p.fault),
                ]), style: const TextStyle(fontSize: 13.5, color: _ink2)),
              if ((p.test ?? '').isNotEmpty)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'الاختبار: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF00788A))),
                  TextSpan(text: p.test),
                ]), style: const TextStyle(fontSize: 13.5, color: _ink2)),
            ]),
          ),
        ]),
      );

  // ------------------------------------------------------------ export
  Future<ui.Image> _grab(GlobalKey k, double ratio) async {
    final ro = k.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final h = ro.size.height;
    final r = math.min(ratio, 14000 / math.max(h, 1));
    return ro.toImage(pixelRatio: r);
  }

  Future<Uint8List> _png(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _exportPng() async {
    setState(() => _busy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final img = await _grab(_whole, 1.6);
      final bytes = await _png(img);
      final where = await ExportService.deliverBytes(bytes, 'ControlAcademy_${ExportService.safeName(c.nameEn)}.png',
          mime: 'image/png', text: c.nameAr);
      _done(where);
    } catch (e) {
      _fail();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportPdf() async {
    setState(() => _busy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final imgs = <(Uint8List, int, int)>[];
      for (final k in _sections.take(_secIndex)) {
        final im = await _grab(k, 2.0);
        imgs.add((await _png(im), im.width, im.height));
      }
      const contentW = 595.28 - 44, contentH = 841.89 - 44;
      final doc = pw.Document(title: c.nameAr, author: AppInfo.brandEn);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        build: (ctx) => [
          for (final (b, w, h) in imgs)
            contentW * h / w > contentH
                ? pw.Center(child: pw.Image(pw.MemoryImage(b), height: contentH - 2, fit: pw.BoxFit.contain))
                : pw.Image(pw.MemoryImage(b), width: contentW, fit: pw.BoxFit.fitWidth),
        ],
      ));
      final bytes = await doc.save();
      final where = await ExportService.deliverBytes(bytes, 'ControlAcademy_${ExportService.safeName(c.nameEn)}.pdf',
          mime: 'application/pdf', text: c.nameAr);
      _done(where);
    } catch (e) {
      _fail();
    }
    if (mounted) setState(() => _busy = false);
  }

  void _done(String? where) {
    if (!mounted || where == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(where == 'shared' ? 'جاهزة للمشاركة والحفظ' : 'اتحفظت في: $where')));
  }

  void _fail() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حصلت مشكلة في التصدير، جرّب تاني.')));
  }
}
