import 'dart:ui' show Offset;

import '../sim/diagnose.dart';
import '../sim/model.dart';
import '../sim/solver.dart';
import '../ui/lab/wires.dart';
import 'project_circuits.dart';

export 'project_circuits.dart';

/// One wire in the reference wiring, with the guide text that goes with it.
class Step {
  final String a, b;
  final WireColor c;
  final String text;
  const Step(this.a, this.b, this.c, this.text);
}

/// A check the trainer runs: set switches, then expect outputs.
class Scenario {
  final String label;
  final Map<String, Object> set; // 'S1': true, 'S1b': true (2nd gang), 'D1': 0.5 (dimmer), 'X1': true (plug)
  final Map<String, bool> expect; // 'E1': lit, 'H1': rings, 'T1': lit, 'X1': socket live, 'Y1': lock opens, 'LP1': panel
  final double wait; // seconds to let staircase timers run before checking
  const Scenario(this.label, this.set, this.expect, {this.wait = 0});
}

class CircuitDef {
  final String id;
  final int no;
  final String title;
  final int level; // 1..4
  final String brief;
  final List<String> tips;
  final List<Part> Function() parts;
  final List<Step> steps;
  final List<Scenario> tests;
  final List<Fault> faults;
  final String room; // where it lives in the apartment
  /// board wiring that comes ready made; null = the usual supply/breaker/bars head
  final List<Step>? pre;
  const CircuitDef({
    required this.id, required this.no, required this.title, required this.level, required this.brief,
    this.tips = const [], required this.parts, required this.steps, required this.tests, required this.faults, this.room = 'الصالة',
    this.pre,
  });

  /// the wires that are already there when the lesson starts
  List<Wire> preWires() => pre == null ? headWires(parts()) : [for (final s in pre!) Wire(s.a, s.b, s.c)];

  /// all wires of the reference wiring (the board head included)
  List<Wire> referenceWires() => [...preWires(), ...steps.map((s) => Wire(s.a, s.b, s.c))];

  Sim buildEmpty() {
    final s = Sim(parts: parts(), wires: preWires());
    tidyWires(s);
    return s;
  }

  /// the finished board, its wires laid out by the tidy router (worked out once)
  Sim buildDone() {
    final s = Sim(parts: parts(), wires: referenceWires());
    final r = _routes[id];
    if (r != null && r.length == s.wires.length) {
      for (var i = 0; i < r.length; i++) {
        s.wires[i].pts = List.of(r[i]);
      }
    } else {
      tidyWires(s);
      _routes[id] = [for (final w in s.wires) List.of(w.pts)];
    }
    return s;
  }
}

/// The first wire of the reference wiring the student has not made yet (by net, so any
/// equivalent way of joining the two points counts), or null when nothing is missing.
Step? nextHint(CircuitDef c, Sim s) {
  final nets = netsOf(s, throughDevices: false);
  for (final st in c.steps) {
    if (!nets.same(st.a, st.b)) return st;
  }
  return null;
}

final Map<String, List<List<Offset>>> _routes = {};

const levelNames = ['', 'مبتدئ', 'متوسط', 'متقدم', 'احترافي'];

// ---------------------------------------------------------------- board head
// Supply G1, breaker Q1, neutral bar NB and earth bar EB are on every board.
List<Part> head({int rating = 10}) => [
      Part('G1', Kind.supply, const Offset(30, 24)),
      Part('Q1', Kind.mcb, const Offset(190, 14), rating: rating),
      Part('NB', Kind.nbar, const Offset(270, 22)),
      Part('EB', Kind.ebar, const Offset(270, 80)),
    ];

/// The board head is prewired: the lesson starts at the breaker.
List<Wire> headWires(List<Part> parts) {
  final ids = parts.map((p) => p.id).toSet();
  if (ids.contains('M1')) {
    return [
      Wire('G1.L', 'M1.Li', WireColor.brown),
      Wire('G1.N', 'M1.Ni', WireColor.blue),
      Wire('G1.PE', 'EB.e1', WireColor.earth),
    ];
  }
  return [
    Wire('G1.L', 'Q1.in', WireColor.brown),
    Wire('G1.N', 'NB.n1', WireColor.blue),
    Wire('G1.PE', 'EB.e1', WireColor.earth),
  ];
}

Part lamp(String id, double x, double y, {int w = 60, bool led = false}) => Part(id, Kind.lamp, Offset(x, y), watts: w, led: led);
Part sw(String id, Kind k, double x, double y) => Part(id, k, Offset(x, y));

List<Fault> _f(List<(FaultKind, String)> l) => [for (final x in l) Fault(x.$1, x.$2)];

/// wire index helper: faults on wires are named w<index in referenceWires>, head = 3 wires
String w(int stepIndex) => 'w${stepIndex + 3}';

final List<CircuitDef> circuits = [
  CircuitDef(
    id: 'c01', no: 1, level: 1, title: 'توصيل لمبة بمفتاح', room: 'غرفة النوم',
    brief: 'أبسط دايرة إنارة: المفتاح بيقطع الفاز، واللمبة بين الفاز الراجع من المفتاح والنيوترال.',
    tips: ['المفتاح دايمًا على الفاز، عشان الدواية تبقى مفصولة لما المفتاح يتقفل.', 'المسمار الوسطاني في الدواية للفاز، والقلاووظ للنيوترال.'],
    parts: () => [...head(), sw('S1', Kind.sw1, 220, 300), lamp('E1', 520, 280)],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'وصّل الفاز من طرف 2 تحت القاطع لطرف L في المفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'وصّل طرف L1 في المفتاح بالمسمار الوسطاني في الدواية (L)'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'وصّل النيوترال من قضيب النيوترال لقلاووظ الدواية (N)'),
    ],
    tests: const [
      Scenario('المفتاح مفتوح', {'S1': false}, {'E1': false}),
      Scenario('المفتاح مقفول', {'S1': true}, {'E1': true}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E1'), (FaultKind.wireCut, 'w4'), (FaultKind.switchBroken, 'S1'), (FaultKind.looseTerm, 'E1.N'), (FaultKind.wireCut, 'w5'), (FaultKind.mcbFaulty, 'Q1'), (FaultKind.looseTerm, 'S1.L')]),
  ),
  CircuitDef(
    id: 'c02', no: 2, level: 1, title: 'لمبة بمفتاح وبريزة', room: 'غرفة النوم',
    brief: 'لمبة بمفتاحها، وبريزة شغالة على طول من نفس الخط. البريزة ليها فاز ونيوترال وأرضي.',
    tips: ['البريزة بتاخد الفاز مباشرة من غير مفتاح.', 'سلك الأرضي الأخضر في الأصفر يروح لطرف الأرضي في البريزة.'],
    parts: () => [...head(rating: 16), sw('S1', Kind.sw1, 200, 300), lamp('E1', 420, 280), Part('X1', Kind.socket, const Offset(650, 300))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز من القاطع لطرف L في المفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'من L1 في المفتاح للمسمار الوسطاني في الدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال لقلاووظ الدواية'),
      Step('Q1.out', 'X1.L', WireColor.brown, 'الفاز من القاطع لطرف L في البريزة'),
      Step('NB.n3', 'X1.N', WireColor.blue, 'النيوترال لطرف N في البريزة'),
      Step('EB.e2', 'X1.PE', WireColor.earth, 'الأرضي لطرف الأرضي في البريزة'),
    ],
    tests: const [
      Scenario('المفتاح مفتوح', {'S1': false}, {'E1': false, 'X1': true}),
      Scenario('المفتاح مقفول', {'S1': true}, {'E1': true, 'X1': true}),
    ],
    faults: _f([(FaultKind.wireCut, 'w6'), (FaultKind.looseTerm, 'X1.N'), (FaultKind.lampBurnt, 'E1'), (FaultKind.leakToEarth, 'X1.L'), (FaultKind.switchBroken, 'S1'), (FaultKind.wireCut, 'w7')]),
  ),
  CircuitDef(
    id: 'c03', no: 3, level: 1, title: 'لمبة وبريزة بمفتاح بيتحكم في البريزة', room: 'المطبخ',
    brief: 'كل حمل ليه مفتاحه: S1 للمبة، وS2 بيفصل البريزة (زي بريزة السخان).',
    parts: () => [...head(rating: 16), sw('S1', Kind.sw1, 180, 300), lamp('E1', 360, 280), sw('S2', Kind.sw1, 560, 300), Part('X1', Kind.socket, const Offset(760, 300))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز لطرف L في المفتاح S1'),
      Step('S1.1', 'E1.L', WireColor.brown, 'من L1 في S1 لوسط الدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
      Step('Q1.out', 'S2.L', WireColor.brown, 'الفاز لطرف L في المفتاح S2'),
      Step('S2.1', 'X1.L', WireColor.brown, 'من L1 في S2 لطرف L في البريزة'),
      Step('NB.n3', 'X1.N', WireColor.blue, 'النيوترال للبريزة'),
      Step('EB.e2', 'X1.PE', WireColor.earth, 'الأرضي للبريزة'),
    ],
    tests: const [
      Scenario('الاتنين مفتوحين', {'S1': false, 'S2': false}, {'E1': false, 'X1': false}),
      Scenario('S1 بس', {'S1': true, 'S2': false}, {'E1': true, 'X1': false}),
      Scenario('S2 بس', {'S1': false, 'S2': true}, {'E1': false, 'X1': true}),
    ],
    faults: _f([(FaultKind.switchBroken, 'S2'), (FaultKind.wireCut, 'w7'), (FaultKind.looseTerm, 'E1.L'), (FaultKind.leakToEarth, 'X1.L')]),
  ),
  CircuitDef(
    id: 'c04', no: 4, level: 1, title: 'مجموعة لمبات على التوالي',
    brief: '3 لمبات ورا بعض في نفس السكة. الجهد بيتقسم عليهم فبينوّروا ضعيف، ولو واحدة اتحرقت الكل يطفي.',
    tips: ['في التوالي التيار واحد في كل اللمبات.', 'لو 3 لمبات زي بعض على 220 فولت، كل لمبة بياخد حوالي 73 فولت.'],
    parts: () => [...head(), sw('S1', Kind.sw1, 180, 320), lamp('E1', 380, 300), lamp('E2', 540, 300), lamp('E3', 700, 300)],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز لطرف L في المفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'من L1 في المفتاح لطرف L في اللمبة الأولى'),
      Step('E1.N', 'E2.L', WireColor.black, 'من الطرف التاني في اللمبة الأولى لأول طرف في التانية'),
      Step('E2.N', 'E3.L', WireColor.black, 'من التانية للتالتة'),
      Step('E3.N', 'NB.n2', WireColor.blue, 'من آخر لمبة للنيوترال'),
    ],
    tests: const [
      Scenario('المفتاح مفتوح', {'S1': false}, {'E1': false, 'E2': false, 'E3': false}),
      Scenario('المفتاح مقفول', {'S1': true}, {'E1': true, 'E2': true, 'E3': true}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E2'), (FaultKind.wireCut, 'w6'), (FaultKind.looseTerm, 'E3.N')]),
  ),
  CircuitDef(
    id: 'c05', no: 5, level: 1, title: 'مجموعة لمبات على التوازي',
    brief: 'كل لمبة واخدة 220 فولت كاملين، فبتنوّر بقدرتها الكاملة، ولو واحدة اتحرقت الباقي يكمّل.',
    parts: () => [...head(), sw('S1', Kind.sw1, 180, 320), lamp('E1', 380, 300), lamp('E2', 540, 300), lamp('E3', 700, 300)],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز لطرف L في المفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'الراجع من المفتاح للمبة الأولى'),
      Step('E1.L', 'E2.L', WireColor.brown, 'كوبري فاز من اللمبة الأولى للتانية'),
      Step('E2.L', 'E3.L', WireColor.brown, 'كوبري فاز من التانية للتالتة'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للمبة الأولى'),
      Step('E1.N', 'E2.N', WireColor.blue, 'كوبري نيوترال للتانية'),
      Step('E2.N', 'E3.N', WireColor.blue, 'كوبري نيوترال للتالتة'),
    ],
    tests: const [
      Scenario('المفتاح مفتوح', {'S1': false}, {'E1': false, 'E2': false, 'E3': false}),
      Scenario('المفتاح مقفول', {'S1': true}, {'E1': true, 'E2': true, 'E3': true}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E3'), (FaultKind.wireCut, 'w6'), (FaultKind.looseTerm, 'E2.N'), (FaultKind.wireCut, 'w4')]),
  ),
  CircuitDef(
    id: 'c06', no: 6, level: 2, title: 'نجفة توالي وتوازي (مفتاح توالي)', room: 'الصالة',
    brief: 'مفتاح بزرارين: الزرار الأول بيولّع مجموعة لمبات، والتاني بيولّع المجموعة التانية، والاتنين مع بعض النجفة كلها.',
    parts: () => [...head(), sw('S1', Kind.swd, 180, 320), lamp('E1', 380, 260), lamp('E2', 540, 260), lamp('E3', 380, 420), lamp('E4', 540, 420)],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للطرف المشترك L في المفتاح المزدوج'),
      Step('S1.1', 'E1.L', WireColor.brown, 'الزرار الأول (L1) للمجموعة الأولى'),
      Step('E1.L', 'E2.L', WireColor.brown, 'كوبري فاز بين لمبتين المجموعة الأولى'),
      Step('S1.2', 'E3.L', WireColor.black, 'الزرار التاني (L2) للمجموعة التانية'),
      Step('E3.L', 'E4.L', WireColor.black, 'كوبري بين لمبتين المجموعة التانية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للمبة 1'),
      Step('E1.N', 'E2.N', WireColor.blue, 'النيوترال للمبة 2'),
      Step('E2.N', 'E3.N', WireColor.blue, 'النيوترال للمبة 3'),
      Step('E3.N', 'E4.N', WireColor.blue, 'النيوترال للمبة 4'),
    ],
    tests: const [
      Scenario('الزرار الأول', {'S1': true, 'S1b': false}, {'E1': true, 'E2': true, 'E3': false, 'E4': false}),
      Scenario('الزرار التاني', {'S1': false, 'S1b': true}, {'E1': false, 'E2': false, 'E3': true, 'E4': true}),
      Scenario('الاتنين', {'S1': true, 'S1b': true}, {'E1': true, 'E2': true, 'E3': true, 'E4': true}),
    ],
    faults: _f([(FaultKind.wireCut, 'w6'), (FaultKind.lampBurnt, 'E1'), (FaultKind.looseTerm, 'S1.2'), (FaultKind.wireCut, 'w11')]),
  ),
  CircuitDef(
    id: 'c07', no: 7, level: 2, title: 'نجفة توازي بمفتاح واحد', room: 'الصالة',
    brief: 'نجفة فيها 4 لمبات كلهم توازي على مفتاح واحد.',
    parts: () => [...head(), sw('S1', Kind.sw1, 180, 320), lamp('E1', 380, 260), lamp('E2', 540, 260), lamp('E3', 380, 420), lamp('E4', 540, 420)],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للمفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'الراجع للمبة 1'),
      Step('E1.L', 'E2.L', WireColor.brown, 'كوبري فاز للمبة 2'),
      Step('E2.L', 'E4.L', WireColor.brown, 'كوبري فاز للمبة 4'),
      Step('E1.L', 'E3.L', WireColor.brown, 'كوبري فاز للمبة 3'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للمبة 1'),
      Step('E1.N', 'E2.N', WireColor.blue, 'النيوترال للمبة 2'),
      Step('E1.N', 'E3.N', WireColor.blue, 'النيوترال للمبة 3'),
      Step('E3.N', 'E4.N', WireColor.blue, 'النيوترال للمبة 4'),
    ],
    tests: const [
      Scenario('مفتوح', {'S1': false}, {'E1': false, 'E2': false, 'E3': false, 'E4': false}),
      Scenario('مقفول', {'S1': true}, {'E1': true, 'E2': true, 'E3': true, 'E4': true}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E4'), (FaultKind.wireCut, 'w7'), (FaultKind.looseTerm, 'E3.N')]),
  ),
  CircuitDef(
    id: 'c08', no: 8, level: 2, title: 'التحكم في لمبة من مكانين (دفياتير)', room: 'الطرقة',
    brief: 'مفتاحين دفياتير بينهم سلكين متنقلين. أي مفتاح يغيّر حالة اللمبة.',
    tips: ['الفاز يدخل الطرف المشترك C في المفتاح الأول.', 'الطرف المشترك في المفتاح التاني يطلع للمبة.', 'L1 مع L1 وL2 مع L2 بسلكين متنقلين.'],
    parts: () => [...head(), sw('S1', Kind.sw2, 200, 320), sw('S2', Kind.sw2, 480, 320), lamp('E1', 720, 300)],
    steps: const [
      Step('Q1.out', 'S1.C', WireColor.brown, 'الفاز للطرف المشترك C في المفتاح الأول'),
      Step('S1.1', 'S2.1', WireColor.grey, 'السلك المتنقل الأول: L1 مع L1'),
      Step('S1.2', 'S2.2', WireColor.grey, 'السلك المتنقل التاني: L2 مع L2'),
      Step('S2.C', 'E1.L', WireColor.brown, 'الطرف المشترك في المفتاح التاني لوسط الدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
    ],
    tests: const [
      Scenario('S1=1 و S2=1', {'S1': false, 'S2': false}, {'E1': true}),
      Scenario('S1=2 و S2=1', {'S1': true, 'S2': false}, {'E1': false}),
      Scenario('S1=1 و S2=2', {'S1': false, 'S2': true}, {'E1': false}),
      Scenario('S1=2 و S2=2', {'S1': true, 'S2': true}, {'E1': true}),
    ],
    faults: _f([(FaultKind.wireCut, 'w5'), (FaultKind.looseTerm, 'S2.C'), (FaultKind.switchBroken, 'S1'), (FaultKind.lampBurnt, 'E1')]),
  ),
  CircuitDef(
    id: 'c09', no: 9, level: 2, title: 'التحكم من 3 أماكن (انترميديت)', room: 'السلم',
    brief: 'دفياتير في الأول والآخر، وانترميديت في النص بيعكس السلكين المتنقلين.',
    parts: () => [...head(), sw('S1', Kind.sw2, 180, 330), sw('S2', Kind.swi, 400, 330), sw('S3', Kind.sw2, 620, 330), lamp('E1', 820, 300)],
    steps: const [
      Step('Q1.out', 'S1.C', WireColor.brown, 'الفاز للمشترك C في الدفياتير الأول'),
      Step('S1.1', 'S2.A1', WireColor.grey, 'L1 في المفتاح الأول لـ A1 في الانترميديت'),
      Step('S1.2', 'S2.A2', WireColor.grey, 'L2 في المفتاح الأول لـ A2 في الانترميديت'),
      Step('S2.B1', 'S3.1', WireColor.grey, 'B1 في الانترميديت لـ L1 في المفتاح الأخير'),
      Step('S2.B2', 'S3.2', WireColor.grey, 'B2 في الانترميديت لـ L2 في المفتاح الأخير'),
      Step('S3.C', 'E1.L', WireColor.brown, 'المشترك في المفتاح الأخير للدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
    ],
    tests: const [
      Scenario('كلهم وضع 1', {'S1': false, 'S2': false, 'S3': false}, {'E1': true}),
      Scenario('الأول اتقلب', {'S1': true, 'S2': false, 'S3': false}, {'E1': false}),
      Scenario('النص اتقلب', {'S1': false, 'S2': true, 'S3': false}, {'E1': false}),
      Scenario('الأخير اتقلب', {'S1': false, 'S2': false, 'S3': true}, {'E1': false}),
      Scenario('الأول والنص', {'S1': true, 'S2': true, 'S3': false}, {'E1': true}),
      Scenario('النص والأخير', {'S1': false, 'S2': true, 'S3': true}, {'E1': true}),
      Scenario('التلاتة', {'S1': true, 'S2': true, 'S3': true}, {'E1': false}),
    ],
    faults: _f([(FaultKind.wireCut, 'w6'), (FaultKind.switchBroken, 'S2'), (FaultKind.looseTerm, 'S3.2')]),
  ),
  CircuitDef(
    id: 'c10', no: 10, level: 3, title: 'التحكم من 4 أماكن (2 انترميديت)', room: 'السلم',
    brief: 'نفس فكرة 3 أماكن، بس بانترميديت تاني في السلسلة. ممكن تكمّل لأي عدد أماكن.',
    parts: () => [...head(), sw('S1', Kind.sw2, 150, 330), sw('S2', Kind.swi, 330, 330), sw('S3', Kind.swi, 510, 330), sw('S4', Kind.sw2, 690, 330), lamp('E1', 860, 300)],
    steps: const [
      Step('Q1.out', 'S1.C', WireColor.brown, 'الفاز للمشترك في الدفياتير الأول'),
      Step('S1.1', 'S2.A1', WireColor.grey, 'L1 لـ A1 في الانترميديت الأول'),
      Step('S1.2', 'S2.A2', WireColor.grey, 'L2 لـ A2 في الانترميديت الأول'),
      Step('S2.B1', 'S3.A1', WireColor.grey, 'B1 لـ A1 في الانترميديت التاني'),
      Step('S2.B2', 'S3.A2', WireColor.grey, 'B2 لـ A2 في الانترميديت التاني'),
      Step('S3.B1', 'S4.1', WireColor.grey, 'B1 لـ L1 في الدفياتير الأخير'),
      Step('S3.B2', 'S4.2', WireColor.grey, 'B2 لـ L2 في الدفياتير الأخير'),
      Step('S4.C', 'E1.L', WireColor.brown, 'المشترك للدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
    ],
    tests: const [
      Scenario('كلهم وضع 1', {'S1': false, 'S2': false, 'S3': false, 'S4': false}, {'E1': true}),
      Scenario('S3 اتقلب', {'S1': false, 'S2': false, 'S3': true, 'S4': false}, {'E1': false}),
      Scenario('S2 وS3', {'S1': false, 'S2': true, 'S3': true, 'S4': false}, {'E1': true}),
      Scenario('S4 اتقلب', {'S1': false, 'S2': false, 'S3': false, 'S4': true}, {'E1': false}),
    ],
    faults: _f([(FaultKind.wireCut, 'w8'), (FaultKind.switchBroken, 'S3')]),
  ),
  CircuitDef(
    id: 'c11', no: 11, level: 2, title: 'التحكم في شدة الإضاءة بدايمر', room: 'غرفة النوم',
    brief: 'الدايمر بيتركب مكان المفتاح على الفاز، وبيقلّل الجهد الواصل للمبة.',
    tips: ['اللمبات LED محتاجة لمبة مكتوب عليها Dimmable ودايمر مناسب.'],
    parts: () => [...head(), sw('D1', Kind.dimmer, 240, 320), lamp('E1', 520, 290, w: 100)],
    steps: const [
      Step('Q1.out', 'D1.L', WireColor.brown, 'الفاز لطرف L في الدايمر'),
      Step('D1.1', 'E1.L', WireColor.brown, 'من الدايمر لوسط الدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
    ],
    tests: const [
      Scenario('على الآخر', {'D1': 1.0}, {'E1': true}),
      Scenario('مقفول', {'D1': 0.0}, {'E1': false}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E1'), (FaultKind.switchBroken, 'D1'), (FaultKind.wireCut, 'w4')]),
  ),
  CircuitDef(
    id: 'c12', no: 12, level: 3, title: 'توصيل لمبة فلورسنت', room: 'المطبخ',
    brief: 'البلاست توالي مع الأنبوبة، والستارتر بين الفتيلتين. الستارتر بيسخّن الفتايل وبعدين يفصل فالبلاست يدي شرارة البدء.',
    tips: ['أنبوبة 120 سم = 40 وات وعايزة بلاست 40 وات.', 'من غير بلاست التيار بيعلى جدًا والقاطع يفصل.'],
    parts: () => [...head(), sw('S1', Kind.sw1, 160, 330), Part('BL1', Kind.ballast, const Offset(330, 230), watts: 40), Part('T1', Kind.tube, const Offset(520, 210), watts: 40), Part('ST1', Kind.starter, const Offset(640, 320))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للمفتاح'),
      Step('S1.1', 'BL1.1', WireColor.brown, 'من المفتاح لأول طرف في البلاست'),
      Step('BL1.2', 'T1.A1', WireColor.brown, 'من البلاست لطرف A1 في الأنبوبة'),
      Step('T1.A2', 'ST1.1', WireColor.black, 'من A2 لأول طرف في الستارتر'),
      Step('ST1.2', 'T1.B1', WireColor.black, 'من الستارتر لطرف B1 في الناحية التانية'),
      Step('T1.B2', 'NB.n2', WireColor.blue, 'من B2 للنيوترال'),
    ],
    tests: const [
      Scenario('مفتوح', {'S1': false}, {'T1': false}),
      Scenario('مقفول', {'S1': true}, {'T1': true}),
    ],
    faults: _f([(FaultKind.starterDead, 'ST1'), (FaultKind.ballastOpen, 'BL1'), (FaultKind.tubeDead, 'T1'), (FaultKind.looseTerm, 'T1.B2'), (FaultKind.wireCut, 'w5')]),
  ),
  CircuitDef(
    id: 'c13', no: 13, level: 3, title: 'لمبتين فلورسنت على التوازي', room: 'الورشة',
    brief: 'كل أنبوبة ليها بلاست وستارتر، والاتنين على مفتاح واحد.',
    parts: () => [...head(), sw('S1', Kind.sw1, 130, 330), Part('BL1', Kind.ballast, const Offset(300, 200), watts: 40), Part('T1', Kind.tube, const Offset(500, 180), watts: 40), Part('ST1', Kind.starter, const Offset(640, 250)),
      Part('BL2', Kind.ballast, const Offset(300, 420), watts: 40), Part('T2', Kind.tube, const Offset(500, 400), watts: 40), Part('ST2', Kind.starter, const Offset(640, 470))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للمفتاح'),
      Step('S1.1', 'BL1.1', WireColor.brown, 'من المفتاح للبلاست الأول'),
      Step('BL1.2', 'T1.A1', WireColor.brown, 'البلاست الأول للأنبوبة الأولى'),
      Step('T1.A2', 'ST1.1', WireColor.black, 'الأنبوبة الأولى للستارتر الأول'),
      Step('ST1.2', 'T1.B1', WireColor.black, 'الستارتر الأول للناحية التانية'),
      Step('T1.B2', 'NB.n2', WireColor.blue, 'النيوترال للأنبوبة الأولى'),
      Step('S1.1', 'BL2.1', WireColor.brown, 'من المفتاح للبلاست التاني'),
      Step('BL2.2', 'T2.A1', WireColor.brown, 'البلاست التاني للأنبوبة التانية'),
      Step('T2.A2', 'ST2.1', WireColor.black, 'للستارتر التاني'),
      Step('ST2.2', 'T2.B1', WireColor.black, 'الستارتر التاني للناحية التانية'),
      Step('T2.B2', 'NB.n3', WireColor.blue, 'النيوترال للأنبوبة التانية'),
    ],
    tests: const [
      Scenario('مفتوح', {'S1': false}, {'T1': false, 'T2': false}),
      Scenario('مقفول', {'S1': true}, {'T1': true, 'T2': true}),
    ],
    faults: _f([(FaultKind.starterDead, 'ST2'), (FaultKind.ballastOpen, 'BL1'), (FaultKind.wireCut, 'w9')]),
  ),
  CircuitDef(
    id: 'c14', no: 14, level: 3, title: 'لمبتين فلورسنت توالي على خانق واحد', room: 'الورشة',
    brief: 'أنبوبتين 60 سم (20 وات) ورا بعض على بلاست واحد 40 وات، ولكل أنبوبة ستارتر.',
    parts: () => [...head(), sw('S1', Kind.sw1, 130, 330), Part('BL1', Kind.ballast, const Offset(260, 220), watts: 40),
      Part('T1', Kind.tube, const Offset(470, 180), watts: 20), Part('ST1', Kind.starter, const Offset(610, 250)),
      Part('T2', Kind.tube, const Offset(470, 400), watts: 20), Part('ST2', Kind.starter, const Offset(610, 470))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للمفتاح'),
      Step('S1.1', 'BL1.1', WireColor.brown, 'من المفتاح للبلاست'),
      Step('BL1.2', 'T1.A1', WireColor.brown, 'من البلاست لـ A1 في الأنبوبة الأولى'),
      Step('T1.A2', 'ST1.1', WireColor.black, 'A2 للستارتر الأول'),
      Step('ST1.2', 'T1.B1', WireColor.black, 'الستارتر الأول لـ B1'),
      Step('T1.B2', 'T2.A1', WireColor.black, 'B2 في الأولى لـ A1 في التانية (توالي)'),
      Step('T2.A2', 'ST2.1', WireColor.black, 'A2 في التانية للستارتر التاني'),
      Step('ST2.2', 'T2.B1', WireColor.black, 'الستارتر التاني لـ B1'),
      Step('T2.B2', 'NB.n2', WireColor.blue, 'B2 في التانية للنيوترال'),
    ],
    tests: const [
      Scenario('مفتوح', {'S1': false}, {'T1': false, 'T2': false}),
      Scenario('مقفول', {'S1': true}, {'T1': true, 'T2': true}),
    ],
    faults: _f([(FaultKind.starterDead, 'ST1'), (FaultKind.tubeDead, 'T2'), (FaultKind.looseTerm, 'T1.B2')]),
  ),
  CircuitDef(
    id: 'c15', no: 15, level: 3, title: 'ماكينة السلم', room: 'السلم',
    brief: 'ضواغط على كل دور كلها توازي على طرف 3 في الماكينة. الضغطة بتولّع لمبات السلم لمدة وبعدين تطفي لوحدها.',
    tips: ['الضواغط توازي بين الفاز وطرف 3.', 'طرف 4 يطلع للمبات.', 'في المحاكاة المدة 12 ثانية.'],
    parts: () => [...head(), Part('K1', Kind.stair, const Offset(420, 160)), sw('P1', Kind.pb, 160, 360), sw('P2', Kind.pb, 300, 360), sw('P3', Kind.pb, 440, 360), lamp('E1', 640, 330), lamp('E2', 800, 330)],
    steps: const [
      Step('Q1.out', 'K1.L', WireColor.brown, 'الفاز لطرف L في الماكينة'),
      Step('NB.n2', 'K1.N', WireColor.blue, 'النيوترال لطرف N في الماكينة'),
      Step('Q1.out', 'P1.1', WireColor.brown, 'الفاز للضاغط الأول'),
      Step('P1.1', 'P2.1', WireColor.brown, 'كوبري فاز للضاغط التاني'),
      Step('P2.1', 'P3.1', WireColor.brown, 'كوبري فاز للضاغط التالت'),
      Step('P1.2', 'K1.S', WireColor.black, 'راجع الضاغط الأول لطرف 3'),
      Step('P2.2', 'P1.2', WireColor.black, 'راجع الضاغط التاني مع الأول'),
      Step('P3.2', 'P2.2', WireColor.black, 'راجع الضاغط التالت مع التاني'),
      Step('K1.O', 'E1.L', WireColor.brown, 'طرف 4 للمبة الأولى'),
      Step('E1.L', 'E2.L', WireColor.brown, 'كوبري للمبة التانية'),
      Step('NB.n3', 'E1.N', WireColor.blue, 'النيوترال للمبة الأولى'),
      Step('E1.N', 'E2.N', WireColor.blue, 'النيوترال للمبة التانية'),
    ],
    tests: const [
      Scenario('قبل الضغط', {}, {'E1': false, 'E2': false}),
      Scenario('ضغطة على أي ضاغط', {'P2': true}, {'E1': true, 'E2': true}),
      Scenario('بعد 13 ثانية', {}, {'E1': false, 'E2': false}, wait: 13),
    ],
    faults: _f([(FaultKind.looseTerm, 'K1.S'), (FaultKind.switchBroken, 'P2'), (FaultKind.wireCut, 'w11'), (FaultKind.lampBurnt, 'E2')]),
  ),
  CircuitDef(
    id: 'c16', no: 16, level: 3, title: 'الكالون الكهربي', room: 'باب الشقة',
    brief: 'ضاغط جوه الشقة بيوصّل الكالون فيسيب لسان الباب. (في الحقيقة الكالون غالبًا 12 فولت من محول الإنتركم، هنا بنبسّطها على 220.)',
    parts: () => [...head(), sw('P1', Kind.pb, 240, 340), Part('Y1', Kind.lock, const Offset(560, 280))],
    steps: const [
      Step('Q1.out', 'P1.1', WireColor.brown, 'الفاز للضاغط'),
      Step('P1.2', 'Y1.1', WireColor.brown, 'من الضاغط للكالون'),
      Step('Y1.2', 'NB.n2', WireColor.blue, 'الكالون للنيوترال'),
    ],
    tests: const [
      Scenario('من غير ضغط', {}, {'Y1': false}),
      Scenario('اضغط', {'P1': true}, {'Y1': true}),
    ],
    faults: _f([(FaultKind.switchBroken, 'P1'), (FaultKind.looseTerm, 'Y1.2')]),
  ),
  CircuitDef(
    id: 'c17', no: 17, level: 1, title: 'توصيل جرس كهربي', room: 'باب الشقة',
    brief: 'ضاغط عند الباب بيوصّل الفاز للجرس طول ما هو مضغوط.',
    parts: () => [...head(), sw('P1', Kind.pb, 240, 340), Part('H1', Kind.bell, const Offset(560, 300))],
    steps: const [
      Step('Q1.out', 'P1.1', WireColor.brown, 'الفاز لطرف 1 في الضاغط'),
      Step('P1.2', 'H1.1', WireColor.brown, 'من الضاغط لطرف 1 في الجرس'),
      Step('H1.2', 'NB.n2', WireColor.blue, 'الطرف التاني في الجرس للنيوترال'),
    ],
    tests: const [
      Scenario('من غير ضغط', {}, {'H1': false}),
      Scenario('اضغط', {'P1': true}, {'H1': true}),
    ],
    faults: _f([(FaultKind.bellDead, 'H1'), (FaultKind.switchBroken, 'P1'), (FaultKind.wireCut, 'w4')]),
  ),
  CircuitDef(
    id: 'c18', no: 18, level: 2, title: 'جرس كهربي مع لمبة بيان', room: 'باب الشقة',
    brief: 'اللمبة توازي مع الجرس، فتنوّر وهو بيرن (مفيدة للي سمعه ضعيف أو في الورش الدوشة).',
    parts: () => [...head(), sw('P1', Kind.pb, 200, 340), Part('H1', Kind.bell, const Offset(460, 300)), lamp('E1', 680, 280, w: 25)],
    steps: const [
      Step('Q1.out', 'P1.1', WireColor.brown, 'الفاز للضاغط'),
      Step('P1.2', 'H1.1', WireColor.brown, 'من الضاغط للجرس'),
      Step('H1.1', 'E1.L', WireColor.brown, 'كوبري من الجرس للمبة (توازي)'),
      Step('H1.2', 'NB.n2', WireColor.blue, 'الجرس للنيوترال'),
      Step('E1.N', 'NB.n3', WireColor.blue, 'اللمبة للنيوترال'),
    ],
    tests: const [
      Scenario('من غير ضغط', {}, {'H1': false, 'E1': false}),
      Scenario('اضغط', {'P1': true}, {'H1': true, 'E1': true}),
    ],
    faults: _f([(FaultKind.lampBurnt, 'E1'), (FaultKind.bellDead, 'H1'), (FaultKind.wireCut, 'w5')]),
  ),
  CircuitDef(
    id: 'c19', no: 19, level: 4, title: 'بريزة 16 أمبير بمفتاح تسريب أرضي', room: 'الحمام',
    brief: 'بريزة السخان أو الغسالة محمية بقاطع 16 أمبير ومفتاح تسريب 30 مللي أمبير بيفصل لو فيه تيار بيهرب للأرض.',
    tips: ['اضغط زرار TEST في مفتاح التسريب كل شهر.', 'لو التسريب فصل، دوّر على جهاز عازله ضعيف.'],
    parts: () => [...head(rating: 16), Part('R1', Kind.rcd, const Offset(420, 14)), Part('X1', Kind.socket, const Offset(600, 320), plug: true)],
    steps: const [
      Step('Q1.out', 'R1.Li', WireColor.brown, 'الفاز من القاطع لطرف L فوق في مفتاح التسريب'),
      Step('NB.n2', 'R1.Ni', WireColor.blue, 'النيوترال لطرف N فوق في مفتاح التسريب'),
      Step('R1.Lo', 'X1.L', WireColor.brown, 'L تحت للبريزة'),
      Step('R1.No', 'X1.N', WireColor.blue, 'N تحت للبريزة (النيوترال لازم يعدّي على مفتاح التسريب)'),
      Step('EB.e2', 'X1.PE', WireColor.earth, 'الأرضي للبريزة'),
    ],
    tests: const [
      Scenario('الجهاز شغال', {'X1': true}, {'X1': true}),
    ],
    faults: _f([(FaultKind.leakToEarth, 'X1.L'), (FaultKind.looseTerm, 'R1.No'), (FaultKind.wireCut, 'w5')]),
  ),
  CircuitDef(
    id: 'c20', no: 20, level: 4, title: 'كشاف LED بدرايفر', room: 'المطبخ',
    brief: 'الدرايفر بياخد 220 فولت متردد ويطلع جهد مستمر للكشاف. لازم تراعي القطبية + و −.',
    parts: () => [...head(), sw('S1', Kind.sw1, 180, 330), Part('DR1', Kind.driver, const Offset(380, 330)), Part('LP1', Kind.ledpanel, const Offset(640, 280))],
    steps: const [
      Step('Q1.out', 'S1.L', WireColor.brown, 'الفاز للمفتاح'),
      Step('S1.1', 'DR1.L', WireColor.brown, 'من المفتاح لطرف L في الدرايفر'),
      Step('NB.n2', 'DR1.N', WireColor.blue, 'النيوترال لطرف N في الدرايفر'),
      Step('DR1.+', 'LP1.+', WireColor.red, 'الموجب من الدرايفر للكشاف'),
      Step('DR1.-', 'LP1.-', WireColor.black, 'السالب من الدرايفر للكشاف'),
    ],
    tests: const [
      Scenario('مفتوح', {'S1': false}, {'LP1': false}),
      Scenario('مقفول', {'S1': true}, {'LP1': true}),
    ],
    faults: _f([(FaultKind.driverDead, 'DR1'), (FaultKind.looseTerm, 'LP1.-'), (FaultKind.switchBroken, 'S1')]),
  ),
  CircuitDef(
    id: 'c21', no: 21, level: 4, title: 'توصيل العداد الكهربي ولوحة التوزيع', room: 'الصالة',
    brief: 'العداد بعد مصدر الشركة، وبعده مفتاح التسريب الرئيسي، وبعده قواطع الخطوط: خط إنارة 10 أمبير وخط برايز 16 أمبير.',
    tips: ['أطراف العداد: 1 دخول فاز، 3 خروج فاز، 4 دخول نيوترال، 6 خروج نيوترال.', 'كل خط ليه قاطع، والنيوترال يتجمع على القضيب بعد مفتاح التسريب.'],
    parts: () => [
      Part('G1', Kind.supply, const Offset(30, 24)), Part('M1', Kind.meter, const Offset(190, 10)), Part('R1', Kind.rcd, const Offset(350, 20)),
      Part('Q1', Kind.mcb, const Offset(480, 20), rating: 10), Part('Q2', Kind.mcb, const Offset(540, 20), rating: 16),
      Part('NB', Kind.nbar, const Offset(620, 30)), Part('EB', Kind.ebar, const Offset(620, 90)),
      sw('S1', Kind.sw1, 300, 380), lamp('E1', 520, 360), Part('X1', Kind.socket, const Offset(760, 380)),
    ],
    steps: const [
      Step('M1.Lo', 'R1.Li', WireColor.brown, 'من طرف 3 في العداد للفاز فوق في مفتاح التسريب'),
      Step('M1.No', 'R1.Ni', WireColor.blue, 'من طرف 6 في العداد للنيوترال فوق في مفتاح التسريب'),
      Step('R1.Lo', 'Q1.in', WireColor.brown, 'فاز مفتاح التسريب لقاطع الإنارة'),
      Step('Q1.in', 'Q2.in', WireColor.brown, 'كوبري فاز لقاطع البرايز'),
      Step('R1.No', 'NB.n1', WireColor.blue, 'نيوترال مفتاح التسريب لقضيب النيوترال'),
      Step('Q1.out', 'S1.L', WireColor.brown, 'خط الإنارة للمفتاح'),
      Step('S1.1', 'E1.L', WireColor.brown, 'المفتاح للدواية'),
      Step('NB.n2', 'E1.N', WireColor.blue, 'النيوترال للدواية'),
      Step('Q2.out', 'X1.L', WireColor.brown, 'خط البرايز للبريزة'),
      Step('NB.n3', 'X1.N', WireColor.blue, 'النيوترال للبريزة'),
      Step('EB.e2', 'X1.PE', WireColor.earth, 'الأرضي للبريزة'),
    ],
    tests: const [
      Scenario('الإنارة مطفية', {'S1': false}, {'E1': false, 'X1': true}),
      Scenario('الإنارة شغالة', {'S1': true}, {'E1': true, 'X1': true}),
    ],
    faults: _f([(FaultKind.mcbFaulty, 'Q2'), (FaultKind.leakToEarth, 'E1.L'), (FaultKind.looseTerm, 'NB.n1'), (FaultKind.wireCut, 'w6')]),
  ),
];

/// the training circuits plus the full installation projects
List<CircuitDef> get allCircuits => [...circuits, ...projectCircuits];

CircuitDef? circuitById(String id) {
  for (final c in allCircuits) {
    if (c.id == id) return c;
  }
  return null;
}

/// Applies a scenario's switch settings to a copy of [s].
void applyScenario(Sim s, Scenario sc) {
  for (final p in s.parts) {
    if (p.kind == Kind.pb) p.on = false;
  }
  sc.set.forEach((k, v) {
    if (k.endsWith('b') && s.part(k.substring(0, k.length - 1)) != null && s.part(k) == null) {
      s.part(k.substring(0, k.length - 1))!.on2 = v as bool;
      return;
    }
    final p = s.part(k);
    if (p == null) return;
    if (p.kind == Kind.dimmer) {
      p.level = (v as num).toDouble();
    } else if (p.kind == Kind.socket) {
      p.plug = v as bool;
    } else {
      p.on = v as bool;
    }
  });
}

/// Whether output [id] is "on" in [r].
bool outputOn(Sim s, SimResult r, String id) {
  final p = s.part(id);
  if (p == null) return false;
  switch (p.kind) {
    case Kind.lamp:
      return (r.lamp[id] ?? 0) > 0.04;
    case Kind.bell:
      return r.bells.contains(id);
    case Kind.lock:
      return r.locks.contains(id);
    case Kind.tube:
      return r.tubes.contains(id);
    case Kind.ledpanel:
      return r.panels.contains(id);
    case Kind.socket:
      return r.sockets[id] ?? false;
    default:
      return false;
  }
}

class CheckReport {
  final List<String> passed = [];
  final List<String> failed = [];
  final List<String> warnings = [];
  bool get ok => failed.isEmpty;
  int get stars => failed.isNotEmpty ? 0 : warnings.isEmpty ? 3 : 2;
}

/// Runs every scenario of [c] on the student's wiring [s] and checks safety rules.
CheckReport checkCircuit(CircuitDef c, Sim s, {bool keepFaults = false}) {
  final rep = CheckReport();
  final sim = s.clone()..resetProtection();
  if (!keepFaults) sim.faults.clear();
  sim.power = true;
  sim.stairLeft.clear();
  for (final sc in c.tests) {
    applyScenario(sim, sc);
    var r = simulate(sim);
    if (sc.wait > 0) {
      for (final p in sim.parts.where((p) => p.kind == Kind.pb)) {
        p.on = false;
      }
      sim.tick(sc.wait);
      r = simulate(sim);
    }
    if (r.event != SimEvent.none) {
      rep.failed.add('${sc.label}: ${eventText(r.event)}');
      sim.resetProtection();
      continue;
    }
    final bad = <String>[];
    sc.expect.forEach((id, want) {
      final got = outputOn(sim, r, id);
      if (got != want) bad.add('$id ${want ? 'المفروض يشتغل' : 'المفروض يبقى مطفي'}');
    });
    if (bad.isEmpty) {
      rep.passed.add(sc.label);
    } else {
      rep.failed.add('${sc.label}: ${bad.join('، ')}');
    }
    // safety: a lamp that is off must not keep its holder live; the phase goes to the centre pin
    for (final p in sim.parts.where((p) => p.kind == Kind.lamp)) {
      final lit = (r.lamp[p.id] ?? 0) > 0.04;
      if (!lit && r.live('${p.id}.L') && !rep.warnings.any((w) => w.contains(p.id))) {
        rep.warnings.add('الدواية ${p.id} فاضلة مكهربة وهي مطفية: المفتاح لازم يقطع الفاز مش النيوترال');
      }
      if (lit && r.volts('${p.id}.N') > 90 && r.volts('${p.id}.L') < 90 && !rep.warnings.any((w) => w.contains(p.id))) {
        rep.warnings.add('الفاز واصل لقلاووظ الدواية ${p.id}: الفاز لازم يروح للمسمار الوسطاني');
      }
    }
  }
  // sockets need their earth
  for (final p in sim.parts.where((p) => p.kind == Kind.socket)) {
    if (resistance(sim.clone()..power = false, '${p.id}.PE', 'G1.PE') == null) {
      rep.warnings.add('البريزة ${p.id} من غير أرضي');
    }
  }
  return rep;
}

String eventText(SimEvent e) => switch (e) {
      SimEvent.shortCircuit => 'قصر! القاطع فصل',
      SimEvent.overload => 'حمل زيادة، القاطع فصل',
      SimEvent.leakage => 'تسريب أرضي، مفتاح التسريب فصل',
      SimEvent.fuse => 'قصر مباشر على المصدر، الفيوز الرئيسي ضرب',
      SimEvent.noBallast => 'أنبوبة من غير بلاست',
      SimEvent.none => '',
    };
