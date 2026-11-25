// The hand-held instruments of the schematic simulator: a digital multimeter,
// a clamp meter and a wattmeter, each drawn as a small device the student moves
// around the screen. The readings come from [Measure] (lib/sim/measure.dart).
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MeterKind { dmm, clamp, watt }

const kMeterNames = {MeterKind.dmm: 'أفوميتر رقمي', MeterKind.clamp: 'كلامب ميتر (بنز أمبير)', MeterKind.watt: 'واتميتر'};

/// modes on the selector of each instrument: key, dial label, Arabic hint
const kMeterModes = {
  MeterKind.dmm: [('vac', 'V~', 'جهد متردد'), ('vdc', 'V=', 'جهد مستمر'), ('ohm', 'Ω', 'مقاومة'), ('beep', '•))', 'استمرارية')],
  MeterKind.clamp: [('aac', 'A~', 'تيار متردد'), ('vac', 'V~', 'جهد متردد')],
  MeterKind.watt: [('w', 'W', 'قدرة فعالة')],
};

/// what an instrument shows
class MeterReading {
  final String value; // the big digits ("230.4", "OL", "----")
  final String unit; // V · A · Ω · kΩ · W
  final String note; // a line under the display (hint or warning)
  final bool warn;
  final double? needle; // wattmeter: 0–1 of full scale
  final String scale; // wattmeter full-scale text
  final List<(String, String)> extra; // small secondary values
  const MeterReading(this.value, this.unit, {this.note = '', this.warn = false, this.needle, this.scale = '', this.extra = const []});
  static const idle = MeterReading('----', '');
}

/// display text with 4 significant digits like a 4-digit meter
String meterDigits(double v) {
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(0);
  if (a >= 100) return v.toStringAsFixed(1);
  if (a >= 10) return v.toStringAsFixed(2);
  return v.toStringAsFixed(3);
}

/// resistance with its range: (digits, unit)
(String, String) ohmText(double? r) {
  if (r == null) return ('OL', 'Ω');
  if (r >= 1e6) return (meterDigits(r / 1e6), 'MΩ');
  if (r >= 1e3) return (meterDigits(r / 1e3), 'kΩ');
  return (r < 0.05 ? '0.00' : meterDigits(r), 'Ω');
}

class MeterPanel extends StatelessWidget {
  final MeterKind kind;
  final String mode;
  final MeterReading reading;
  final String red, black, clamp; // probe / clamp positions (empty: not placed)
  final bool needsProbes, needsClamp;
  final int nextProbe; // 0 red · 1 black: the probe the next tap on a pin places
  final ValueChanged<String> onMode;
  final ValueChanged<int> onPickProbe;
  final VoidCallback onClose, onClear;
  const MeterPanel({
    super.key,
    required this.kind,
    required this.mode,
    required this.reading,
    required this.red,
    required this.black,
    required this.clamp,
    required this.needsProbes,
    required this.needsClamp,
    required this.nextProbe,
    required this.onMode,
    required this.onPickProbe,
    required this.onClose,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final body = switch (kind) { MeterKind.dmm => const Color(0xFF262B33), MeterKind.clamp => const Color(0xFF2B2F27), MeterKind.watt => const Color(0xFF1F2A3A) };
    final rim = switch (kind) { MeterKind.dmm => const Color(0xFFF2B705), MeterKind.clamp => const Color(0xFFE8541E), MeterKind.watt => const Color(0xFF8FA6C4) };
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 268,
        decoration: BoxDecoration(
          color: rim,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))],
        ),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(body, Colors.white, 0.08)!, body]),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.drag_indicator_rounded, size: 18, color: Colors.white38),
              const SizedBox(width: 4),
              Expanded(child: Text(kMeterNames[kind]!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
              InkWell(onTap: onClose, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: Colors.white70))),
            ]),
            if (kind == MeterKind.clamp) const SizedBox(height: 40, child: CustomPaint(painter: _JawPainter())),
            const SizedBox(height: 4),
            if (kind == MeterKind.watt) _gauge() else _lcd(),
            const SizedBox(height: 8),
            // selector dial positions
            Row(children: [
              for (final (k, label, hint) in kMeterModes[kind]!)
                Expanded(
                  child: Tooltip(
                    message: hint,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onMode(k),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: mode == k ? rim : const Color(0x22FFFFFF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, fontSize: 14, color: mode == k ? Colors.black : Colors.white)),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            if (needsProbes)
              Row(children: [
                Expanded(child: _probe('أحمر +', red, const Color(0xFFE53935), nextProbe == 0, () => onPickProbe(0))),
                const SizedBox(width: 6),
                Expanded(child: _probe('أسود COM', black, const Color(0xFF111111), nextProbe == 1, () => onPickProbe(1))),
              ]),
            if (needsClamp) ...[
              if (needsProbes) const SizedBox(height: 6),
              _probe('الفك على سلك', clamp, rim, false, null),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                  needsClamp && clamp.isEmpty
                      ? 'المس أي سلك عشان تقفل الفك عليه'
                      : needsProbes && (red.isEmpty || black.isEmpty)
                          ? 'المس طرف أي مكوّن عشان تحط المجس ${nextProbe == 0 ? 'الأحمر' : 'الأسود'}'
                          : 'المس طرف تاني عشان تنقل المجس',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white60, height: 1.4),
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('شيل المجسات', style: TextStyle(fontSize: 12))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _lcd() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB9C9B4), Color(0xFF94A88F)]),
          border: Border.all(color: Colors.black54, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(textDirection: TextDirection.ltr, children: [
            Text(mode == 'beep' ? '•))' : (mode == 'vdc' ? 'DC' : (mode == 'ohm' ? '' : 'AC')),
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: Color(0xFF1D2A1A), fontWeight: FontWeight.w700)),
            const Spacer(),
            const Text('AUTO', style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: Color(0xFF1D2A1A), fontWeight: FontWeight.w700)),
          ]),
          Row(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(reading.value,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 40, height: 1.05, fontWeight: FontWeight.w700, color: Color(0xFF111A10))),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(reading.unit, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111A10))),
            ),
          ]),
          if (reading.note.isNotEmpty)
            Text(reading.note, style: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w700, color: reading.warn ? const Color(0xFF9B111E) : const Color(0xFF2C3A28))),
        ]),
      );

  Widget _gauge() => Container(
        decoration: BoxDecoration(color: const Color(0xFFF4F1E8), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black54, width: 2)),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 92, child: CustomPaint(painter: _NeedlePainter(reading.needle ?? 0, reading.scale))),
          Row(textDirection: TextDirection.ltr, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(reading.value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF1B2330))),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(reading.unit, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: Color(0xFF1B2330)))),
          ]),
          if (reading.extra.isNotEmpty)
            Wrap(alignment: WrapAlignment.center, spacing: 10, textDirection: TextDirection.ltr, children: [
              for (final (k, v) in reading.extra)
                Text('$k $v', textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: Color(0xFF3D4A5E))),
            ]),
          if (reading.note.isNotEmpty)
            Text(reading.note, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.3, color: reading.warn ? const Color(0xFF9B111E) : const Color(0xFF3D4A5E))),
        ]),
      );

  Widget _probe(String label, String at, Color col, bool next, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0x18FFFFFF),
            border: Border.all(color: next ? Colors.white : Colors.white12, width: next ? 1.6 : 1),
          ),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: Colors.white54))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(at.isEmpty ? label : at,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
}

class _JawPainter extends CustomPainter {
  const _JawPainter();
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2;
    final p = Paint()
      ..color = const Color(0xFFE8541E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCircle(center: Offset(cx, s.height + 4), radius: 34), math.pi * 1.08, math.pi * 0.38, false, p);
    c.drawArc(Rect.fromCircle(center: Offset(cx, s.height + 4), radius: 34), math.pi * 1.54, math.pi * 0.38, false, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _NeedlePainter extends CustomPainter {
  final double v; // 0–1
  final String scale;
  _NeedlePainter(this.v, this.scale);
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height - 4);
    final r = math.min(s.width / 2 - 8, s.height - 12);
    const a0 = math.pi * 1.15, sweep = math.pi * 0.7;
    final ink = Paint()
      ..color = const Color(0xFF1B2330)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    c.drawArc(Rect.fromCircle(center: ctr, radius: r), a0, sweep, false, ink);
    c.drawArc(Rect.fromCircle(center: ctr, radius: r - 4), a0 + sweep * 0.8, sweep * 0.2, false, Paint()
      ..color = const Color(0xFFD7263D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    for (var i = 0; i <= 20; i++) {
      final a = a0 + sweep * i / 20;
      final len = i % 5 == 0 ? 10.0 : 5.0;
      c.drawLine(ctr + Offset(math.cos(a), math.sin(a)) * r, ctr + Offset(math.cos(a), math.sin(a)) * (r - len), ink);
      if (i % 5 == 0) {
        final tp = TextPainter(
            text: TextSpan(text: '${i * 5}', style: const TextStyle(fontSize: 8, fontFamily: 'JetBrainsMono', color: Color(0xFF3D4A5E))), textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(c, ctr + Offset(math.cos(a), math.sin(a)) * (r - 18) - Offset(tp.width / 2, tp.height / 2));
      }
    }
    final tp = TextPainter(
        text: TextSpan(text: scale, style: const TextStyle(fontSize: 9, fontFamily: 'JetBrainsMono', color: Color(0xFF3D4A5E), fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, ctr - Offset(tp.width / 2, r * 0.45));
    final a = a0 + sweep * v.clamp(0.0, 1.05);
    c.drawLine(ctr, ctr + Offset(math.cos(a), math.sin(a)) * (r - 6), Paint()
      ..color = const Color(0xFFD7263D)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round);
    c.drawCircle(ctr, 5, Paint()..color = const Color(0xFF1B2330));
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter old) => old.v != v || old.scale != scale;
}
