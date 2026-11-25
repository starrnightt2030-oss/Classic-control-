// PDF of a schematic: page 1 the drawing (A4 landscape), page 2 the component list.
// Both pages are painted with Flutter (correct Arabic shaping) and placed as images.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'model.dart';
import 'sheet_paint.dart';
import 'symbols.dart';

String todayText() {
  final t = DateTime.now();
  return '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
}

Future<Uint8List> _png(void Function(Canvas) draw, int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  draw(c);
  final img = await rec.endRecording().toImage(w, h);
  final b = await img.toByteData(format: ui.ImageByteFormat.png);
  return b!.buffer.asUint8List();
}

Future<Uint8List> sheetPng(SchemDoc d, {double scale = 2.5}) {
  final w = (d.sheetW * kG * scale).round(), h = (d.sheetH * kG * scale).round();
  return _png((c) {
    c.scale(scale);
    SheetPainter(d, print: true, date: todayText()).paint(c, Size(d.sheetW * kG, d.sheetH * kG));
  }, w, h);
}

Future<Uint8List> bomPng(SchemDoc d) => _png((c) => paintBom(c, d, k: 2.5, date: todayText()), (595 * 2.5).round(), (842 * 2.5).round());

Future<Uint8List> schematicPdf(SchemDoc d) async {
  final sheet = await sheetPng(d);
  final bom = await bomPng(d);
  final doc = pw.Document(title: d.title, author: 'Control Academy');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(18),
    build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(sheet), fit: pw.BoxFit.contain)),
  ));
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Image(pw.MemoryImage(bom), fit: pw.BoxFit.fill),
  ));
  return doc.save();
}
