// Fault generator for the free lab: one hidden fault, the trainee finds it, we score it.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_service.dart';
import '../sim/engine.dart';
import '../ui/theme.dart';
import 'model.dart';

const _histKey = 'lab_fault_history_v1';

class FaultKind {
  final String key, nameAr, hint;
  const FaultKind(this.key, this.nameAr, this.hint);
}

const kFaultKinds = [
  FaultKind('wire', 'سلك مقطوع', 'راقب الأسلاك المضيئة: الجهد يتوقف عند نقطة معينة في المسار.'),
  FaultKind('coil_open', 'ملف كونتاكتور أو مرحّل مقطوع', 'الجهد يصل إلى طرفي الملف A1 و A2، لكن الجهاز لا يجذب.'),
  FaultKind('weld', 'نقاط كونتاكتور ملتحمة', 'الحمل يستمر في العمل حتى بعد فصل الملف.'),
  FaultKind('nc_open', 'نقطة مغلقة لا توصّل', 'دائرة التحكم مقطوعة عند جهاز يُفترض أن نقطته المغلقة توصّل.'),
  FaultKind('no_close', 'نقطة مفتوحة لا تُغلق', 'الضغط أو الجذب يحدث، لكن نقطته المفتوحة لا تُغلق الدائرة.'),
  FaultKind('lamp_dead', 'لمبة بيان محترقة', 'الجهد يصل إلى X1 و X2، واللمبة لا تضيء.'),
  FaultKind('phase_loss', 'فقد فاز من المصدر', 'المحرك يطنّ ولا يدور، وأحد أسلاك القوى غير مضيء من البداية.'),
  FaultKind('open_pole', 'قطب لا يوصّل في جهاز قوى', 'فاز يصل قبل الجهاز ولا يخرج منه.'),
  FaultKind('ol_set', 'ضبط الأوفرلود أقل من تيار المحرك', 'المحرك يعمل ثم يفصل بعد مدة قصيرة بلا حمل زائد.'),
];

FaultKind faultKind(String k) => kFaultKinds.firstWhere((f) => f.key == k);

class FaultSession {
  final String kind;
  final String? partId;
  final int? wireIndex;
  final String? wireKey; // a|b of the broken wire, stable across edits
  final double? oldSet;
  double seconds = 0;
  int attempts = 0;
  bool hintShown = false;

  FaultSession(this.kind, {this.partId, this.wireIndex, this.wireKey, this.oldSet});

  static FaultSession? create(LabDoc doc) {
    final r = math.Random();
    final cands = <FaultSession>[];
    final engineOf = {for (final p in doc.parts) p.id: p.d.engine};
    for (var i = 0; i < doc.wires.length; i++) {
      final w = doc.wires[i];
      if (w.color == 'ge') continue;
      cands.add(FaultSession('wire', wireIndex: i, wireKey: '${w.a}|${w.b}'));
    }
    engineOf.forEach((id, e) {
      if (e == 'kc' || e == 'relay') {
        cands.add(FaultSession('coil_open', partId: id));
        cands.add(FaultSession('weld', partId: id));
      }
      if (e == 'kc' || e == 'mcb3') cands.add(FaultSession('open_pole', partId: id));
      if (e == 'ol' || e == 'pb_nc' || e == 'estop') cands.add(FaultSession('nc_open', partId: id));
      if (e == 'pb_no' || e == 'aux') cands.add(FaultSession('no_close', partId: id));
      if (e == 'lamp') cands.add(FaultSession('lamp_dead', partId: id));
      if (e == 'sup') cands.add(FaultSession('phase_loss', partId: id));
      if (e == 'ol' || e == 'mpcb') cands.add(FaultSession('ol_set', partId: id));
    });
    if (cands.length < 3 || !engineOf.containsValue('sup')) return null;
    return cands[r.nextInt(cands.length)];
  }

  /// inject into a freshly built simulation
  void applyTo(Lab l) {
    switch (kind) {
      case 'wire':
        final i = wireIndex;
        if (i != null && i < l.wires.length) l.brokenWires.add(l.wires[i]);
      case 'ol_set':
        final c = l.byId(partId!);
        if (c != null) c.p['set'] = 3.0;
      default:
        final c = partId == null ? null : l.byId(partId!);
        if (c != null) {
          c.s.fault = kind;
          if (kind == 'phase_loss') c.p['lost'] = 'L3';
        }
    }
    l.solve();
  }

  void tick(double dt) => seconds += dt;

  String clockText() {
    final s = seconds.floor();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String describe(LabDoc doc) {
    final k = faultKind(kind);
    if (kind == 'wire') {
      final parts = wireKey?.split('|') ?? const ['?', '?'];
      return '${k.nameAr}: ${parts[0]} ↔ ${parts[1]}';
    }
    final p = partId == null ? null : doc.byId(partId!);
    return '${k.nameAr}: ${p?.d.nameAr ?? ''} $partId';
  }

  bool check(String kindGuess, String target) {
    attempts++;
    if (kindGuess != kind) return false;
    if (kind == 'wire') return target == wireKey;
    return target == partId;
  }

  Future<void> record(LabDoc doc, {required bool solved}) async {
    final prefs = await SharedPreferences.getInstance();
    final l = (jsonDecode(prefs.getString(_histKey) ?? '[]') as List).cast<Map<String, dynamic>>();
    l.insert(0, {
      'at': DateTime.now().toIso8601String(),
      'fault': describe(doc),
      'attempts': attempts,
      'seconds': seconds.round(),
      'solved': solved,
      'hint': hintShown,
    });
    if (l.length > 200) l.removeRange(200, l.length);
    await prefs.setString(_histKey, jsonEncode(l));
  }
}

class FaultSheet extends StatefulWidget {
  final FaultSession session;
  final LabDoc doc;
  final VoidCallback onSolved;
  const FaultSheet({super.key, required this.session, required this.doc, required this.onSolved});
  @override
  State<FaultSheet> createState() => _FaultSheetState();
}

class _FaultSheetState extends State<FaultSheet> {
  String? kind;
  String? target;
  String? message;
  bool good = false;

  FaultSession get f => widget.session;

  List<(String, String)> _targets() {
    final d = widget.doc;
    if (kind == null) return const [];
    if (kind == 'wire') {
      final nums = d.netNumbers();
      return [
        for (final w in d.wires)
          if (w.color != 'ge') ('${w.a}|${w.b}', 'سلك ${nums[w.a]} : ${w.a} ↔ ${w.b}'),
      ];
    }
    bool fits(String e) => switch (kind) {
          'coil_open' || 'weld' => e == 'kc' || e == 'relay',
          'open_pole' => e == 'kc' || e == 'mcb3',
          'nc_open' => e == 'ol' || e == 'pb_nc' || e == 'estop',
          'no_close' => e == 'pb_no' || e == 'aux',
          'lamp_dead' => e == 'lamp',
          'phase_loss' => e == 'sup',
          'ol_set' => e == 'ol' || e == 'mpcb',
          _ => false,
        };
    return [
      for (final p in d.parts)
        if (fits(p.d.engine)) (p.id, '${p.id} · ${p.d.nameAr}'),
    ];
  }

  void _submit() async {
    if (kind == null || target == null) return;
    final ok = f.check(kind!, target!);
    if (ok) {
      AudioService.instance.sfx('success_fanfare');
      await f.record(widget.doc, solved: true);
      setState(() {
        good = true;
        message = 'أحسنت! وجدت العطل في ${f.clockText()} بعد ${f.attempts} ${f.attempts == 1 ? 'محاولة' : 'محاولات'}.\n${f.describe(widget.doc)}';
      });
      widget.onSolved();
    } else {
      AudioService.instance.sfx('soft_fail');
      setState(() {
        message = f.attempts >= 2 && !f.hintShown ? 'ليس هذا. تلميح: ${faultKind(f.kind).hint}' : 'ليس هذا. راجع العَرَض وقِس مرة أخرى.';
        if (f.attempts >= 2) f.hintShown = true;
      });
    }
  }

  void _reveal() async {
    AudioService.instance.sfx('warning_alert');
    await f.record(widget.doc, solved: false);
    setState(() {
      good = true;
      message = 'العطل كان: ${f.describe(widget.doc)}\n${faultKind(f.kind).hint}';
    });
    widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('حدّد العطل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Text('${f.clockText()} · محاولات ${f.attempts}', style: const TextStyle(fontFamily: CC.mono, color: CC.gold)),
        ]),
        const SizedBox(height: 6),
        const Text('شغّل اللوحة، ولاحظ ما يعمل وما لا يعمل والأسلاك التي عليها جهد، ثم اختر نوع العطل ومكانه.',
            style: TextStyle(color: CC.muted, height: 1.6, fontSize: 13)),
        const SizedBox(height: 12),
        if (!good) ...[
          DropdownButtonFormField<String>(
            value: kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'نوع العطل'),
            items: [for (final k in kFaultKinds) DropdownMenuItem(value: k.key, child: Text(k.nameAr))],
            onChanged: (v) => setState(() {
              kind = v;
              target = null;
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(kind),
            value: target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'المكان'),
            items: [for (final (v, t) in targets) DropdownMenuItem(value: v, child: Text(t, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => target = v),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton(onPressed: kind != null && target != null ? _submit : null, child: const Text('تأكيد'))),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _reveal, child: const Text('أظهر الحل')),
          ]),
        ],
        if (message != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: panelBox(color: good ? const Color(0xFF0E2A1C) : CC.goldBg, border: good ? CC.green : CC.goldLine, radius: 12),
            child: Text(message!, style: const TextStyle(height: 1.7)),
          ),
        ],
        if (good) ...[
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
        ],
      ]),
    );
  }
}

Future<void> showFaultHistory(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final l = (jsonDecode(prefs.getString(_histKey) ?? '[]') as List).cast<Map<String, dynamic>>();
  if (!context.mounted) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
        const Text('سجل الأعطال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (l.isEmpty) const Text('لا توجد محاولات بعد.', style: TextStyle(color: CC.muted)),
        for (final e in l)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: panelBox(radius: 12),
            child: Row(children: [
              Icon(e['solved'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, color: e['solved'] == true ? CC.green : CC.red),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['fault']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                      '${(e['seconds'] as num) ~/ 60}:${((e['seconds'] as num) % 60).toString().padLeft(2, '0')} دقيقة · ${e['attempts']} محاولات${e['hint'] == true ? ' · بتلميح' : ''}',
                      style: const TextStyle(color: CC.muted, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
      ]),
    ),
  );
}
