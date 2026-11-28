import 'dart:ui' show Offset;

import '../sim/model.dart';
import 'circuits.dart';

/// Whole-room installations: a real board (RCD and a breaker per line), a junction box
/// in the ceiling, and every point in the room wired through it, the way it is done on site.

// board with RCD, lighting breaker Q1 (10 A) and socket breaker Q2 (16 A), prewired
List<Part> _rcdBoard() => [
      Part('G1', Kind.supply, const Offset(30, 24)),
      Part('R1', Kind.rcd, const Offset(180, 20)),
      Part('Q1', Kind.mcb, const Offset(240, 22), rating: 10),
      Part('Q2', Kind.mcb, const Offset(275, 22), rating: 16),
      Part('NB', Kind.nbar, const Offset(320, 30)),
      Part('EB', Kind.ebar, const Offset(320, 80)),
    ];

const _rcdPre = [
  Step('G1.L', 'R1.Li', WireColor.brown, ''),
  Step('G1.N', 'R1.Ni', WireColor.blue, ''),
  Step('G1.PE', 'EB.e1', WireColor.earth, ''),
  Step('R1.Lo', 'Q1.in', WireColor.brown, ''),
  Step('Q1.in', 'Q2.in', WireColor.brown, ''),
  Step('R1.No', 'NB.n1', WireColor.blue, ''),
];

List<Fault> _faults(List<(FaultKind, String)> l) => [for (final x in l) Fault(x.$1, x.$2)];

final List<CircuitDef> projectCircuits = [
  CircuitDef(
    id: 'p1', no: 101, level: 3, title: 'مشروع: غرفة نوم كاملة', room: 'غرفة النوم',
    brief: 'غرفة نوم زي اللي في الموقع: لوحة فيها مفتاح تسريب وقاطع إنارة 10 أمبير وقاطع برايز 16 أمبير، وعلبة تجميع (بواطة) 6 نقط في السقف بيتقابل فيها كل حاجة: لمبة السقف بمفتاحها جنب الباب، وبريزتين بأرضي.',
    tips: [
      'كل نقطة في البواطة ليها وظيفة واحدة: 1 فاز الإنارة، 2 راجع المفتاح، 3 النيوترال، 4 فاز البرايز، 5 الأرضي. اكتب الأرقام على غطا البواطة.',
      'المفتاح بينزل له سلكين بس من البواطة: فاز داخل وراجع طالع للمبة. النيوترال عمره ما ينزل للمفتاح.',
      'الإنارة والبرايز على قاطعين منفصلين، عشان لو البريزة عملت قصر متقطعش النور وانت بتصلّح.',
      'سيب 15 لـ 20 سم سلك زيادة في كل علبة عشان التوصيل والتغيير بعدين.',
    ],
    pre: _rcdPre,
    parts: () => [
      ..._rcdBoard(),
      Part('J1', Kind.jbox6, const Offset(470, 200)),
      Part('S1', Kind.sw1, const Offset(100, 400)),
      Part('E1', Kind.lamp, const Offset(300, 380), watts: 60),
      Part('X1', Kind.socket, const Offset(620, 400)),
      Part('X2', Kind.socket, const Offset(800, 400)),
    ],
    steps: const [
      Step('Q1.out', 'J1.t1', WireColor.brown, 'فاز الإنارة: من القاطع Q1 لنقطة 1 في البواطة'),
      Step('J1.t1', 'S1.L', WireColor.brown, 'من نقطة 1 لطرف L في المفتاح (الفاز الداخل)'),
      Step('S1.1', 'J1.t2', WireColor.brown, 'راجع المفتاح: من L1 لنقطة 2 في البواطة'),
      Step('J1.t2', 'E1.L', WireColor.brown, 'من نقطة 2 لوسط دواية لمبة السقف'),
      Step('NB.n2', 'J1.t3', WireColor.blue, 'النيوترال: من القضيب لنقطة 3 في البواطة'),
      Step('J1.t3', 'E1.N', WireColor.blue, 'من نقطة 3 لقلاووظ الدواية'),
      Step('Q2.out', 'J1.t4', WireColor.brown, 'فاز البرايز: من القاطع Q2 لنقطة 4'),
      Step('J1.t4', 'X1.L', WireColor.brown, 'من نقطة 4 لطرف L في البريزة الأولى'),
      Step('J1.t4', 'X2.L', WireColor.brown, 'من نقطة 4 لطرف L في البريزة التانية'),
      Step('J1.t3', 'X1.N', WireColor.blue, 'من نقطة 3 لطرف N في البريزة الأولى'),
      Step('J1.t3', 'X2.N', WireColor.blue, 'من نقطة 3 لطرف N في البريزة التانية'),
      Step('EB.e2', 'J1.t5', WireColor.earth, 'الأرضي: من القضيب لنقطة 5'),
      Step('J1.t5', 'X1.PE', WireColor.earth, 'من نقطة 5 لأرضي البريزة الأولى'),
      Step('J1.t5', 'X2.PE', WireColor.earth, 'من نقطة 5 لأرضي البريزة التانية'),
    ],
    tests: const [
      Scenario('النور مطفي', {'S1': false}, {'E1': false, 'X1': true, 'X2': true}),
      Scenario('النور منور', {'S1': true}, {'E1': true, 'X1': true, 'X2': true}),
    ],
    faults: _faults([
      (FaultKind.looseTerm, 'J1.t3'), (FaultKind.leakToEarth, 'X2.L'), (FaultKind.lampBurnt, 'E1'),
      (FaultKind.mcbFaulty, 'Q2'), (FaultKind.wireCut, 'w8'), (FaultKind.switchBroken, 'S1'),
    ]),
  ),
  CircuitDef(
    id: 'p2', no: 102, level: 3, title: 'مشروع: طرقة بدفياتير وجرس الباب', room: 'الطرقة',
    brief: 'طرقة فيها لمبة بتتحكم فيها من أولها وآخرها بمفتاحين دفياتير، وجرس الباب بضاغط برا الشقة. كله متجمع في بواطة 8 نقط.',
    tips: [
      'نقط البواطة: 1 فاز، 2 نيوترال، 3 و4 السلكين المتنقلين، 5 راجع اللمبة، 6 راجع الجرس.',
      'السلكين المتنقلين بلون واحد مختلف (رمادي) عشان متلخبطهمش مع الفاز.',
      'الجرس واللمبة على نفس قاطع الإنارة 10 أمبير لأن الاتنين أحمال صغيرة.',
    ],
    parts: () => [
      ...head(),
      Part('J1', Kind.jbox8, const Offset(450, 190)),
      Part('S1', Kind.sw2, const Offset(80, 400)),
      Part('S2', Kind.sw2, const Offset(240, 400)),
      Part('E1', Kind.lamp, const Offset(420, 380), watts: 60),
      Part('P1', Kind.pb, const Offset(620, 400)),
      Part('H1', Kind.bell, const Offset(800, 400)),
    ],
    steps: const [
      Step('Q1.out', 'J1.t1', WireColor.brown, 'الفاز من القاطع لنقطة 1 في البواطة'),
      Step('J1.t1', 'S1.C', WireColor.brown, 'من نقطة 1 للطرف المشترك C في المفتاح الأول'),
      Step('S1.1', 'J1.t3', WireColor.grey, 'المتنقل الأول: L1 في المفتاح الأول لنقطة 3'),
      Step('S1.2', 'J1.t4', WireColor.grey, 'المتنقل التاني: L2 في المفتاح الأول لنقطة 4'),
      Step('J1.t3', 'S2.1', WireColor.grey, 'من نقطة 3 لطرف L1 في المفتاح التاني'),
      Step('J1.t4', 'S2.2', WireColor.grey, 'من نقطة 4 لطرف L2 في المفتاح التاني'),
      Step('S2.C', 'J1.t5', WireColor.brown, 'المشترك في المفتاح التاني لنقطة 5 (راجع اللمبة)'),
      Step('J1.t5', 'E1.L', WireColor.brown, 'من نقطة 5 لوسط الدواية'),
      Step('NB.n2', 'J1.t2', WireColor.blue, 'النيوترال من القضيب لنقطة 2'),
      Step('J1.t2', 'E1.N', WireColor.blue, 'من نقطة 2 لقلاووظ الدواية'),
      Step('J1.t1', 'P1.1', WireColor.brown, 'من نقطة 1 (الفاز) لطرف 1 في ضاغط الجرس'),
      Step('P1.2', 'J1.t6', WireColor.brown, 'من طرف 2 في الضاغط لنقطة 6'),
      Step('J1.t6', 'H1.1', WireColor.brown, 'من نقطة 6 لطرف 1 في الجرس'),
      Step('J1.t2', 'H1.2', WireColor.blue, 'من نقطة 2 (النيوترال) لطرف 2 في الجرس'),
    ],
    tests: const [
      Scenario('S1=1 و S2=1', {'S1': false, 'S2': false}, {'E1': true, 'H1': false}),
      Scenario('S1=2 و S2=1', {'S1': true, 'S2': false}, {'E1': false}),
      Scenario('S1=2 و S2=2', {'S1': true, 'S2': true}, {'E1': true}),
      Scenario('حد ضغط الجرس', {'S1': true, 'S2': false, 'P1': true}, {'H1': true, 'E1': false}),
    ],
    faults: _faults([
      (FaultKind.looseTerm, 'J1.t4'), (FaultKind.bellDead, 'H1'), (FaultKind.wireCut, 'w9'),
      (FaultKind.switchBroken, 'S2'), (FaultKind.looseTerm, 'J1.t2'),
    ]),
  ),
  CircuitDef(
    id: 'p3', no: 103, level: 4, title: 'مشروع: مطبخ (لمبة وكشاف LED وبرايز)', room: 'المطبخ',
    brief: 'مطبخ بمفتاح مزدوج: الزرار الأول للمبة السقف، والتاني لكشاف LED بدرايفر فوق الرخامة. وبريزتين 16 أمبير بأرضي على قاطع لوحدهم ومحميين بمفتاح التسريب. كله في بواطة 10 نقط.',
    tips: [
      'نقط البواطة: 1 فاز الإنارة، 2 النيوترال، 3 راجع اللمبة، 4 راجع الكشاف، 5 فاز البرايز، 6 الأرضي.',
      'الراجع التاني لونه أسود عشان تفرقه عن الأول وانت في السقف.',
      'الدرايفر جنب الكشاف، والسلك بينهم تيار مستمر: الأحمر موجب والأسود سالب.',
      'برايز المطبخ لازم على مفتاح تسريب 30 مللي لأنها جنب الحوض.',
    ],
    pre: _rcdPre,
    parts: () => [
      ..._rcdBoard(),
      Part('J1', Kind.jbox10, const Offset(470, 190)),
      Part('S1', Kind.swd, const Offset(60, 400)),
      Part('E1', Kind.lamp, const Offset(200, 380), watts: 60),
      Part('DR1', Kind.driver, const Offset(310, 440)),
      Part('LP1', Kind.ledpanel, const Offset(470, 380)),
      Part('X1', Kind.socket, const Offset(680, 400)),
      Part('X2', Kind.socket, const Offset(850, 400)),
    ],
    steps: const [
      Step('Q1.out', 'J1.t1', WireColor.brown, 'فاز الإنارة من Q1 لنقطة 1'),
      Step('J1.t1', 'S1.L', WireColor.brown, 'من نقطة 1 للطرف المشترك L في المفتاح المزدوج'),
      Step('S1.1', 'J1.t3', WireColor.brown, 'الزرار الأول (L1) لنقطة 3'),
      Step('J1.t3', 'E1.L', WireColor.brown, 'من نقطة 3 لوسط دواية اللمبة'),
      Step('S1.2', 'J1.t4', WireColor.black, 'الزرار التاني (L2) لنقطة 4 بسلك أسود'),
      Step('J1.t4', 'DR1.L', WireColor.black, 'من نقطة 4 لطرف L في الدرايفر'),
      Step('NB.n2', 'J1.t2', WireColor.blue, 'النيوترال من القضيب لنقطة 2'),
      Step('J1.t2', 'E1.N', WireColor.blue, 'من نقطة 2 لقلاووظ الدواية'),
      Step('J1.t2', 'DR1.N', WireColor.blue, 'من نقطة 2 لطرف N في الدرايفر'),
      Step('DR1.+', 'LP1.+', WireColor.red, 'موجب الدرايفر للكشاف'),
      Step('DR1.-', 'LP1.-', WireColor.black, 'سالب الدرايفر للكشاف'),
      Step('Q2.out', 'J1.t5', WireColor.brown, 'فاز البرايز من Q2 لنقطة 5'),
      Step('J1.t5', 'X1.L', WireColor.brown, 'من نقطة 5 للبريزة الأولى'),
      Step('J1.t5', 'X2.L', WireColor.brown, 'من نقطة 5 للبريزة التانية'),
      Step('J1.t2', 'X1.N', WireColor.blue, 'النيوترال للبريزة الأولى'),
      Step('J1.t2', 'X2.N', WireColor.blue, 'النيوترال للبريزة التانية'),
      Step('EB.e2', 'J1.t6', WireColor.earth, 'الأرضي من القضيب لنقطة 6'),
      Step('J1.t6', 'X1.PE', WireColor.earth, 'من نقطة 6 لأرضي البريزة الأولى'),
      Step('J1.t6', 'X2.PE', WireColor.earth, 'من نقطة 6 لأرضي البريزة التانية'),
    ],
    tests: const [
      Scenario('كله مطفي', {'S1': false, 'S1b': false}, {'E1': false, 'LP1': false, 'X1': true, 'X2': true}),
      Scenario('اللمبة بس', {'S1': true, 'S1b': false}, {'E1': true, 'LP1': false}),
      Scenario('الكشاف بس', {'S1': false, 'S1b': true}, {'E1': false, 'LP1': true}),
      Scenario('الاتنين', {'S1': true, 'S1b': true}, {'E1': true, 'LP1': true, 'X1': true, 'X2': true}),
    ],
    faults: _faults([
      (FaultKind.driverDead, 'DR1'), (FaultKind.leakToEarth, 'X1.L'), (FaultKind.looseTerm, 'J1.t2'),
      (FaultKind.wireCut, 'w10'), (FaultKind.looseTerm, 'S1.2'),
    ]),
  ),
];
