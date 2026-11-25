// Fault diagnosis on the schematic: once the student's circuit works, hidden faults
// are put into it. The student observes, measures with the instruments, switches
// off, points at the faulty part and repairs it. Only faults that really change
// how the circuit behaves are chosen.
import 'dart:isolate';
import 'dart:math' as math;

import 'model.dart';
import 'symbols.dart';

class SFaultKind {
  final String key, nameAr, hint, lesson;
  const SFaultKind(this.key, this.nameAr, this.hint, this.lesson);
}

const kSFaultKinds = <SFaultKind>[
  SFaultKind('wire', 'سلك مقطوع', 'الجهد بيقف عند نقطة في المسار. قيس الجهد على طرفي كل سلك، أو افصل وقيس استمرارية السلك.',
      'السلك المقطوع بيبان سليم من برّه. القياس بالأفوميتر بيبيّنه: جهد على طرف ومفيش على الطرف التاني، أو OL في وضع الاستمرارية.'),
  SFaultKind('coil_open', 'ملف مقطوع', 'الجهد واصل لطرفي الملف A1 وA2، والجهاز مش بيجذب.',
      'لما يكون فيه جهد كامل على A1-A2 والكونتاكتور ما يجذبش، يبقى الملف نفسه مفتوح. بعد الفصل، مقاومة الملف هتقرا OL بدل مئات الأوم.'),
  SFaultKind('stuck_open', 'تلامس محروق مش بيوصّل', 'الجهاز بيشتغل، بس تلامسه مش بيكمّل الدائرة. قيس الجهد قبله وبعده.',
      'التلامس المحروق بيبقى قافل ميكانيكيًا لكن مش بيوصّل كهربيًا: جهد على طرف وصفر على التاني، أو OL في الاستمرارية.'),
  SFaultKind('stuck_closed', 'تلامس ملحوم', 'فيه حاجة شغالة وهي المفروض واقفة. دوّر على تلامس بيوصّل دايمًا.',
      'التلامس الملحوم بيفضل موصّل حتى لو الملف فاصل. في الاستمرارية بيصفّر طول الوقت.'),
  SFaultKind('no_close', 'ضاغط أو مفتاح مش بيقفل', 'لما تضغط الضاغط مفيش حاجة بتحصل. قيس على طرفيه وإنت ضاغط.',
      'الضاغط المفتوح اللي مش بيقفل بيبان من إن الجهد يفضل على طرف واحد بس حتى وإنت ضاغط.'),
  SFaultKind('nc_open', 'ضاغط أو نقطة مغلقة مفتوحة', 'دايرة التحكم مقطوعة من الأول عند ضاغط أو مفتاح المفروض إنه مقفول.',
      'النقطة المغلقة NC لازم توصّل وهي في وضعها الطبيعي. لو قريت جهد على طرف وصفر على التاني يبقى هي اللي فاتحة.'),
  SFaultKind('lamp_dead', 'حمل محروق (لمبة أو جرس أو ملف صمام)', 'الجهد واصل لطرفي الحمل وهو مش شغال.',
      'الحمل المحروق بيقرا جهد كامل على طرفيه ومفيش تيار. بعد الفصل بيقرا OL.'),
  SFaultKind('open_pole', 'قطب مفتوح في قاطع أو مصهر أو كونتاكتور', 'فاز داخل الجهاز ومش طالع منه.',
      'القطب المفتوح بيبان لما تقيس بين الفازات بعد الجهاز: فاز ناقص. والموتور بيزن ومش بيدور.'),
  SFaultKind('phase_loss', 'فاز ناقص من المصدر', 'الموتور بيزن ومش بيدور، وفيه فاز مش واصل من البداية.',
      'لو الفاز مش موجود عند المصدر نفسه، يبقى العيب في التغذية مش في اللوحة. قيس بين L1 وL2 وL3 عند المصدر.'),
  SFaultKind('ol_set', 'ضبط الأوفرلود أقل من تيار الموتور', 'الموتور بيشتغل شوية وبعدين بيفصل من غير حمل زيادة.',
      'قيس تيار الموتور بالكلامب وقارنه بضبط الأوفرلود. الضبط لازم يكون قريب من التيار المقنن للموتور.'),
];

SFaultKind sFaultKind(String k) => kSFaultKinds.firstWhere((f) => f.key == k);

class SFault {
  final String kind;
  final String? sym; // symbol id on the sheet (null for a wire fault)
  final String? wireKey; // "a|b" of the broken wire
  final String? lost; // phase_loss: L1 · L2 · L3
  bool fixed = false;
  SFault(this.kind, {this.sym, this.wireKey, this.lost});

  int? wireIndex(SchemDoc d) {
    for (var i = 0; i < d.wires.length; i++) {
      final w = d.wires[i];
      if ('${w.a}|${w.b}' == wireKey) return i;
    }
    return null;
  }

  /// does pointing at this symbol / wire find the fault?
  bool hit(SchemDoc d, {SPlaced? s, int? wire}) {
    if (kind == 'wire') return wire != null && wire == wireIndex(d);
    if (s == null) return false;
    if (s.id == sym) return true;
    final mine = d.byId(sym ?? '');
    if (mine == null) return false;
    switch (kind) {
      case 'phase_loss':
        return s.d.role == SymRole.source;
      case 'coil_open':
        return s.tag == mine.tag && s.d.role == SymRole.host;
      case 'ol_set':
        return s.tag == mine.tag && (s.sym == 'ol3' || s.sym == 'olnc' || s.sym == 'olno');
    }
    return false;
  }

  String where(SchemDoc d) {
    if (kind == 'wire') {
      final i = wireIndex(d);
      return i == null ? 'سلك' : 'السلك رقم ${d.wireNumbers()[i]}';
    }
    if (kind == 'phase_loss') return 'المصدر (الفاز $lost)';
    final s = d.byId(sym ?? '');
    return s == null ? '' : '${s.tag} (${s.d.nameAr})';
  }
}

/// Build the engine circuit with the faults that are still hidden.
SchemSim buildFaulted(SchemDoc d, List<SFault> faults) {
  final s = d.toSim();
  final l = s.lab;
  final docToEng = {for (final e in s.wireIndex.entries) e.value: e.key};
  for (final f in faults) {
    if (f.fixed) continue;
    switch (f.kind) {
      case 'wire':
        final di = f.wireIndex(d);
        final ei = di == null ? null : docToEng[di];
        if (ei != null) l.brokenWires.add(l.wires[ei]);
      case 'phase_loss':
        final x = l.byId('X0');
        if (x != null) {
          x.s.fault = 'phase_loss';
          x.p['lost'] = f.lost ?? 'L3';
        }
      case 'ol_set':
        final c = l.byId(s.compOf[f.sym] ?? '');
        c?.p['set'] = math.max(1.0, c.num_('set') * 0.45);
      default:
        final c = l.byId(s.compOf[f.sym] ?? '');
        c?.s.fault = f.kind;
    }
  }
  return s;
}

/// Every fault this drawing could hide (before checking that it shows).
List<SFault> faultCandidates(SchemDoc d) {
  final out = <SFault>[];
  for (final w in d.wires) {
    out.add(SFault('wire', wireKey: '${w.a}|${w.b}'));
  }
  final seenHost = <String>{};
  var hasL23 = false;
  for (final s in d.syms) {
    final e = s.d.engine;
    switch (s.d.role) {
      case SymRole.source:
        if (s.sym == 'sup3' || s.sym == 'L2' || s.sym == 'L3') hasL23 = true;
      case SymRole.host:
        if ((e == 'kc' || e == 'relay' || e == 'timer') && seenHost.add(s.tag)) out.add(SFault('coil_open', sym: s.id));
        if (e == 'ol') out.add(SFault('ol_set', sym: s.id));
      case SymRole.hostPart:
        out.add(SFault('open_pole', sym: s.id));
      case SymRole.contact:
        out.add(SFault('stuck_open', sym: s.id));
        if (!s.d.kind.startsWith('OL')) out.add(SFault('stuck_closed', sym: s.id));
      case SymRole.device:
        if (e == 'pb_no' || e == 'sel' || (e == 'ls' && s.d.kind == 'NO')) out.add(SFault('no_close', sym: s.id));
        if (e == 'pb_nc' || e == 'estop' || (e == 'ls' && s.d.kind == 'NC')) out.add(SFault('nc_open', sym: s.id));
        if (e == 'prox') out.add(SFault('stuck_open', sym: s.id));
        if (e == 'lamp') out.add(SFault('lamp_dead', sym: s.id));
        if (e == 'mcb1' || e == 'mcb2' || e == 'mcb3' || e == 'mcb4' || e == 'fuse' || e == 'mpcb' || e == 'isol3') out.add(SFault('open_pole', sym: s.id));
    }
  }
  if (hasL23) {
    for (final k in ['L1', 'L2', 'L3']) {
      if (d.syms.any((s) => s.sym == 'sup3' || s.sym == k)) out.add(SFault('phase_loss', lost: k));
    }
  }
  return out;
}

/// What the circuit does under a fixed routine: at rest, then each operator
/// input pressed for a moment and held (live nets and device states after each step).
String behaviour(SchemSim s) {
  final l = s.lab..setPower(true);
  final terms = l.allTerms();
  final b = StringBuffer();
  void snap() {
    l.run(0.8, dt: 0.1);
    final n = l.nets;
    for (final t in terms) {
      b.write(n != null && n.live(t) ? '1' : '0');
    }
    for (final c in l.comps) {
      b.write(c.s.on ? 'n' : 'f');
      if (c.type == 'motor' || c.type == 'motor1') b.write(c.s.mode);
      if (c.type == 'lamp') b.write(c.s.v > 5 ? 'L' : 'l');
    }
    b.write('|');
  }

  snap();
  final inputs = l.comps.where((c) => c.type == 'pb_no' || c.type == 'ls' || c.type == 'prox' || c.type == 'sel' || c.type == 'pb_nc').toList();
  for (final c in inputs) {
    switch (c.type) {
      case 'sel':
        l.actuate(c.id, 'sel');
        snap();
        l.actuate(c.id, 'sel');
      case 'ls':
      case 'prox':
        l.actuate(c.id, 'ls', true);
        snap();
        l.actuate(c.id, 'ls', false);
      default:
        l.actuate(c.id, 'press', true);
        snap();
        l.actuate(c.id, 'press', false);
    }
    snap();
  }
  return b.toString();
}

/// Does the drawing work well enough to hide faults in it? null when yes,
/// otherwise the reason in Arabic.
String? readyForFaults(SchemDoc d) {
  if (!d.syms.any((s) => s.d.role == SymRole.source)) return 'الدائرة مفيهاش تغذية.';
  final s = d.toSim();
  if (s.warnings.isNotEmpty) return s.warnings.first;
  behaviour(s);
  if (s.lab.events.any((e) => e.t == 'short' || e.t == 'mainTrip')) return 'الدائرة فيها قصر. صلّحها الأول وجرّبها.';
  if (s.lab.events.any((e) => e.t == 'burn' || e.t == 'mburn' || e.t == 'pop')) return 'فيه مكوّن بيتحرق في الدائرة. صلّحها الأول.';
  if (!s.lab.comps.any((c) => c.s.on && c.t.coil != null) && !s.lab.comps.any((c) => c.type == 'lamp' && c.s.v > 5) && !s.lab.comps.any((c) => c.s.mode == 'run' || c.s.mode == 'delta' || c.s.mode == 'star')) {
    return 'الدائرة مش بتشغّل أي حاجة لسه. جرّبها في المحاكاة واتأكد إنها شغالة.';
  }
  return null;
}

/// Pick [count] faults that each change the behaviour, from different devices.
List<SFault> pickFaults(SchemDoc d, int count, {math.Random? rnd}) {
  final r = rnd ?? math.Random();
  final healthy = behaviour(d.toSim());
  final cands = faultCandidates(d)..shuffle(r);
  final out = <SFault>[];
  final usedSym = <String>{}, usedKinds = <String, int>{};
  var current = healthy;
  // prefer variety: at most one wire fault per two faults
  for (final f in cands) {
    if (out.length >= count) break;
    if (f.sym != null && usedSym.contains(f.sym)) continue;
    if ((usedKinds[f.kind] ?? 0) >= (f.kind == 'wire' ? (count + 1) ~/ 2 : 1)) continue;
    if (f.kind == 'ol_set') {
      if (!d.syms.any((s) => s.d.engine == 'motor')) continue;
    } else {
      // shows on its own, and is not hidden behind the faults already chosen
      if (behaviour(buildFaulted(d, [f])) == healthy) continue;
      if (out.isNotEmpty && behaviour(buildFaulted(d, [...out, f])) == current) continue;
    }
    out.add(f);
    if (out.length < count) current = behaviour(buildFaulted(d, out));
    if (f.sym != null) usedSym.add(f.sym!);
    usedKinds[f.kind] = (usedKinds[f.kind] ?? 0) + 1;
  }
  return out;
}

/// score out of 100 and stars (1–3)
(int, int) faultScore({required int faults, required int wrong, required int hints, required double seconds, required bool gaveUp}) {
  var s = 100 - wrong * 8 - hints * 12 - math.max(0, (seconds - 120 * faults) / 30).floor() * 2;
  if (gaveUp) s = math.min(s, 30);
  s = s.clamp(0, 100);
  return (s, s >= 85 ? 3 : (s >= 60 ? 2 : 1));
}

/// [pickFaults] off the UI thread
Future<List<SFault>> pickFaultsAsync(SchemDoc d, int count) {
  final json = d.toJsonString();
  return Isolate.run(() => pickFaults(SchemDoc.fromJsonString(json), count));
}
