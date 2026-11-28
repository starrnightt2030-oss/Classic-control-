import 'package:flutter/material.dart';

import '../../sim/solver.dart';
import '../../theme.dart';

enum MeterMode { volt, ohm, cont, neon }

const meterModeNames = {
  MeterMode.volt: 'V~',
  MeterMode.ohm: 'Ω',
  MeterMode.cont: '🔊',
  MeterMode.neon: 'مفك',
};

class MeterReading {
  final String value;
  final String hint;
  final bool beep;
  final bool neonLit;
  const MeterReading(this.value, this.hint, {this.beep = false, this.neonLit = false});
}

/// What the multimeter (or neon screwdriver) shows for the probes on [sim].
MeterReading readMeter(Sim sim, SimResult res, MeterMode mode, List<String> probes) {
  if (mode == MeterMode.neon) {
    if (probes.isEmpty) return const MeterReading('—', 'المس طرف بمفك الاختبار');
    final lit = sim.power && res.volts(probes.first) > 90;
    return MeterReading(lit ? 'منوّر' : 'مطفي', lit ? 'الطرف ده عليه فاز' : 'مفيش فاز على الطرف ده', neonLit: lit);
  }
  if (probes.length < 2) {
    return MeterReading('- - -', probes.isEmpty ? 'حط الطرف الأحمر على أول نقطة' : 'حط الطرف الأسود على التانية');
  }
  final a = probes[0], b = probes[1];
  if (mode == MeterMode.volt) {
    if (!sim.power) return const MeterReading('0.0 V', 'الكهرباء مفصولة');
    final v = (res.volts(a) - res.volts(b)).abs();
    return MeterReading('${v.toStringAsFixed(1)} V', v > 150 ? 'فيه جهد كامل بين النقطتين' : v > 5 ? 'جهد ناقص' : 'مفيش فرق جهد');
  }
  if (sim.power) return const MeterReading('!!!', 'افصل الكهرباء الأول قبل قياس الأوم', beep: true);
  final r = resistance(sim, a, b);
  if (mode == MeterMode.cont) {
    final ok = r != null && r < 50;
    return MeterReading(ok ? (r < 1 ? '000' : r.toStringAsFixed(0)) : 'OL', ok ? 'متصل (توصيل سليم)' : 'مفيش اتصال', beep: ok);
  }
  if (r == null) return const MeterReading('OL', 'دايرة مفتوحة (مقاومة لانهائية)');
  if (r < 1) return MeterReading('${r.toStringAsFixed(2)} Ω', 'قصر / توصيل مباشر');
  if (r >= 1000) return MeterReading('${(r / 1000).toStringAsFixed(2)} kΩ', 'مقاومة حمل');
  return MeterReading('${r.toStringAsFixed(1)} Ω', 'مقاومة حمل');
}

class MeterWidget extends StatelessWidget {
  final MeterMode mode;
  final MeterReading reading;
  final ValueChanged<MeterMode> onMode;
  final VoidCallback onClose;
  const MeterWidget({required this.mode, required this.reading, required this.onMode, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final neon = mode == MeterMode.neon;
    return Container(
      width: 186,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: neon ? [const Color(0xFF4FC3F7), const Color(0xFF0277BD)] : [const Color(0xFFFFD54F), const Color(0xFFF9A825)]),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
        border: Border.all(color: Colors.black26, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(neon ? 'مفك اختبار' : 'آفوميتر رقمي', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 12)),
          const Spacer(),
          InkWell(onTap: onClose, child: const Icon(Icons.close, size: 18, color: Colors.black87)),
        ]),
        const SizedBox(height: 6),
        Container(
          height: 54,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: neon ? (reading.neonLit ? const Color(0xFFFF6E40) : const Color(0xFF5D4037)) : const Color(0xFFA5C2A0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black45, width: 2),
            boxShadow: neon && reading.neonLit ? [const BoxShadow(color: Color(0xFFFF3D00), blurRadius: 18)] : null,
          ),
          child: Text(reading.value, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: neon ? 'Cairo' : 'monospace', fontSize: 24, fontWeight: FontWeight.w700, color: neon ? Colors.white : const Color(0xFF1B2A1B))),
        ),
        const SizedBox(height: 4),
        Text(reading.hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 11, height: 1.2)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final m in MeterMode.values)
            InkWell(
              onTap: () => onMode(m),
              child: Container(
                width: 38,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m == mode ? C.navy0 : Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(meterModeNames[m]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: m == mode ? C.goldHi : Colors.black87)),
              ),
            ),
        ]),
      ]),
    );
  }
}
