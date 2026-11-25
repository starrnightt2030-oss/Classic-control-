// The 17 classic control circuits as data: parts, reference wiring, interlocks, tasks.
// Ported from the v1 catalogue; texts in Modern Standard Arabic.
//
// Wire line: "from to color [p]"  (p = power wire)
// colors: br L1 brown · bk L2 black · gr L3 grey · bu neutral · gy earth · rd control
import 'engine.dart';

List<Wire> W(String s) => [
      for (final l in s.trim().split(RegExp(r'\n|\|')).map((e) => e.trim()).where((e) => e.isNotEmpty))
        () {
          final f = l.split(RegExp(r'\s+'));
          return Wire(f[0], f[1], col: f.length > 2 ? f[2] : 'rd', power: f.length > 3 && f[3] == 'p');
        }()
    ];

class _PW {
  static List<Wire> feed() => W('SUP.L1 Q1.1 br p|SUP.L2 Q1.3 bk p|SUP.L3 Q1.5 gr p');
  static List<Wire> qk(String k) => W('Q1.2 $k.1 br p|Q1.4 $k.3 bk p|Q1.6 $k.5 gr p');
  static List<Wire> kk(String a, String b) => W('$a.1 $b.1 br p|$a.3 $b.3 bk p|$a.5 $b.5 gr p');
  static List<Wire> om(String o, String m) => W('$o.2 $m.U1 br p|$o.4 $m.V1 bk p|$o.6 $m.W1 gr p|SUP.PE $m.PE gy p');
  static List<Wire> rev(String k1, String k2) => W('$k2.2 $k1.6 br p|$k2.4 $k1.4 bk p|$k2.6 $k1.2 gr p');
  static List<Wire> ctl() => W('SUP.L1 F1.1 rd');
  static List<Wire> sd(String o, String kd, String ks, String m) => W(
      '$o.2 $kd.1 br p|$o.4 $kd.3 bk p|$o.6 $kd.5 gr p|$kd.2 $m.W2 gr p|$kd.4 $m.U2 br p|$kd.6 $m.V2 bk p|'
      '$kd.2 $ks.1 gr p|$kd.4 $ks.3 br p|$kd.6 $ks.5 bk p|$ks.2 $ks.4 bk p|$ks.4 $ks.6 bk p');
}

List<Wire> _n(List<String> ids) => W(ids.map((i) => '$i SUP.N bu').join('|'));

typedef PartSpec = Comp Function();

class _P {
  static List<PartSpec> base() => [() => Comp('SUP', 'sup'), () => Comp('Q1', 'mcb3'), () => Comp('F1', 'mcb1')];
  static PartSpec k(String id, [bool aux = false]) => () => Comp(id, 'kc', p: {'aux': aux});
  static PartSpec ol(String id, String k) => () => Comp(id, 'ol', attach: k);
  static PartSpec m(String id, [String links = 'delta']) => () => Comp(id, 'motor', p: {'links': links});
  static PartSpec start(String id, String lb) => () => Comp(id, 'pb_no', p: {'col': 'g', 'lb': lb});
  static PartSpec stop(String id, String lb) => () => Comp(id, 'pb_nc', p: {'col': 'r', 'lb': lb});
  static PartSpec lamp(String id, String col, String lb) => () => Comp(id, 'lamp', p: {'col': col, 'lb': lb});
  static PartSpec kt(String id, String mode, double t) => () => Comp(id, 'timer', p: {'mode': mode, 'T': t});
  static PartSpec ka(String id) => () => Comp(id, 'relay');
  static PartSpec ls(String id, String lb) => () => Comp(id, 'ls', p: {'lb': lb});
}

class SimTask {
  final String text;
  final bool Function(Lab l) done;
  const SimTask(this.text, this.done);
}

class Circuit {
  final String id, group, title, short, desc, tip;
  final List<PartSpec> parts;
  final List<Wire> wires;
  final List<List<String>> mech;
  final (String, String, String)? track; // motor, left LS, right LS
  final double trackStart; // cart position at load (0 = left end … 1 = right end)
  final List<SimTask> tasks;
  const Circuit({
    required this.id,
    required this.group,
    required this.title,
    required this.short,
    required this.desc,
    required this.tip,
    required this.parts,
    required this.wires,
    this.mech = const [],
    this.track,
    this.trackStart = 0,
    required this.tasks,
  });

  /// A lab with this circuit's parts; wired with the reference solution unless [wired] is false.
  Lab build({bool wired = true}) {
    final l = Lab();
    for (final p in parts) {
      l.comps.add(p());
    }
    if (wired) l.wires.addAll(wires);
    l.mech.addAll(mech);
    final tr = track;
    if (tr != null) l.track = Track(tr.$1, tr.$2, tr.$3)..x = trackStart;
    l.solve();
    return l;
  }

  /// components the trainee operates (buttons, switches) in display order
  List<String> get controls => [
        for (final p in parts)
          () {
            final c = p();
            return const {'pb_no', 'pb_nc', 'estop', 'sel', 'mcb1', 'mcb3', 'ls'}.contains(c.type) ? c.id : null;
          }()
      ].whereType<String>().toList();
}

final _tPower = SimTask('ارفع قاطع التغذية الرئيسي', (l) => l.power);
SimTask _run(String txt, String m) => SimTask(txt, (l) => motorRunning(l, m));
SimTask _stop(String txt, String m) => SimTask(txt, (l) => motorStopped(l, m));
bool _pressed(Lab l, String id) => l[id].s.pr;

final List<Circuit> kCircuits = [
  // 1
  Circuit(
    id: 'c_dol', group: 'دوائر أساسية', title: 'تشغيل محرك وإيقافه بالضواغط مع لمبات البيان', short: 'التشغيل المباشر DOL',
    desc: 'الضاغط S1 الأخضر يشغّل الكونتاكتور K1، والنقطة المساعدة 13-14 للكونتاكتور تُمسك التشغيل بعد أن ترفع إصبعك، وهذه هي دائرة الإمساك الذاتي. '
        'والضاغط S0 الأحمر يفصل الدائرة. واللمبة الخضراء للتشغيل، والحمراء للإيقاف، والصفراء لعطل الأوفرلود.',
    tip: 'نقطة الأوفرلود 95-96 يجب أن تكون أول ما يلي قاطع التحكم F1، حتى يفصل أي حمل زائد الكونتاكتور فورًا.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.lamp('H1', 'g', 'تشغيل'), _P.lamp('H2', 'r', 'إيقاف'), _P.lamp('H3', 'y', 'عطل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F1.2 F2.97|F2.95 K1.53|F2.96 S0.11|F2.96 K1.21|F2.98 H3.X1|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 K1.A1|K1.54 H1.X1|K1.22 H2.X1'),
      ..._n(['K1.A2', 'H1.X2', 'H2.X2', 'H3.X2'])],
    tasks: [_tPower, _run('شغّل المحرك بالضاغط الأخضر S1', 'M1'), _stop('أوقف المحرك بالضاغط الأحمر S0', 'M1'),
      SimTask('اضغط زر الاختبار في الأوفرلود ولاحظ لمبة العطل', (l) => l['F2'].s.trip),
      SimTask('أعد ضبط الأوفرلود ثم شغّل مرة أخرى', (l) => motorRunning(l, 'M1') && !l['F2'].s.trip)],
  ),
  // 2
  Circuit(
    id: 'c_2loc', group: 'دوائر أساسية', title: 'تشغيل محرك من مكانين بضواغط تشغيل وإيقاف', short: 'التحكم من مكانين',
    desc: 'ضاغطا الإيقاف S01 و S02 موصّلان على التوالي، فأيهما يفصل. وضاغطا التشغيل S11 و S12 موصّلان على التوازي مع نقطة الإمساك، فأيهما يشغّل.',
    tip: 'القاعدة: الإيقاف على التوالي، والتشغيل على التوازي.',
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.stop('S01', 'إيقاف 1'), _P.stop('S02', 'إيقاف 2'), _P.start('S11', 'تشغيل 1'), _P.start('S12', 'تشغيل 2'), _P.lamp('H1', 'g', 'تشغيل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S01.11|S01.12 S02.11|S02.12 S11.13|S11.13 S12.13|S12.13 K1.13|S11.14 S12.14|S12.14 K1.14|K1.14 K1.A1|K1.A1 H1.X1'),
      ..._n(['K1.A2', 'H1.X2'])],
    tasks: [_tPower, _run('شغّل من المكان الأول بالضاغط S11', 'M1'), _stop('أوقف من المكان الثاني بالضاغط S02', 'M1'),
      _run('شغّل من المكان الثاني بالضاغط S12', 'M1'), _stop('أوقف من المكان الأول بالضاغط S01', 'M1')],
  ),
  // 3
  Circuit(
    id: 'c_2start', group: 'دوائر أساسية', title: 'تشغيل محرك بضاغطي تشغيل وضاغط إيقاف واحد', short: 'تشغيلان وإيقاف',
    desc: 'ضاغطا التشغيل S1 و S2 على التوازي، وضاغط إيقاف واحد S0. وأي ضاغط تشغيل يشغّل المحرك.',
    tip: 'يتم التوصيل على التوازي بقنطرة بين الطرفين 13 للضاغطين، وأخرى بين الطرفين 14.',
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل 1'), _P.start('S2', 'تشغيل 2'), _P.lamp('H1', 'g', 'تشغيل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 S2.13|S2.13 K1.13|S1.14 S2.14|S2.14 K1.14|K1.14 K1.A1|K1.A1 H1.X1'),
      ..._n(['K1.A2', 'H1.X2'])],
    tasks: [_tPower, _run('شغّل بالضاغط S1', 'M1'), _stop('أوقف بالضاغط S0', 'M1'), _run('شغّل بالضاغط S2', 'M1'), _stop('أوقف بالضاغط S0', 'M1')],
  ),
  // 4
  Circuit(
    id: 'c_2hand', group: 'دوائر أساسية', title: 'تشغيل محرك بالضغط على ضاغطين معًا (أمان اليدين)', short: 'التشغيل باليدين',
    desc: 'ضاغطا التشغيل S1 و S2 على التوالي، فلا يعمل المحرك إلا إذا ضغطتهما معًا. ويُستخدم هذا في المكابس لتبقى يدا العامل بعيدتين عن الخطر.',
    tip: 'اضغط S1 مطوّلًا ثم اضغط S2 وأنت ما زلت ضاغطًا عليه، وعلى الهاتف استخدم إصبعين.',
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'اليد اليمنى'), _P.start('S2', 'اليد اليسرى'), _P.lamp('H1', 'g', 'تشغيل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 K1.13|S1.14 S2.13|S2.14 K1.14|K1.14 K1.A1|K1.A1 H1.X1'),
      ..._n(['K1.A2', 'H1.X2'])],
    tasks: [_tPower, SimTask('اضغط S1 وحده، ولن يعمل المحرك', (l) => _pressed(l, 'S1') && !isOn(l, 'K1')),
      _run('اضغط S1 و S2 معًا', 'M1'), _stop('أوقف بالضاغط S0', 'M1')],
  ),
  // 5
  Circuit(
    id: 'c_ondelay', group: 'دوائر المؤقت', title: 'تشغيل محرك بعد مدة بمؤقت تأخير التوصيل', short: 'التشغيل المتأخر',
    desc: 'الضاغط S1 يشغّل المرحّل KA1 ويُمسك عليه. والمرحّل يشغّل المؤقت KT1، وبعد الزمن المضبوط تُغلق نقطة المؤقت 15-18 فتشغّل الكونتاكتور K1.',
    tip: 'مؤقت تأخير التوصيل يؤخر التوصيل فقط، فبمجرد أن ينفصل ملفه تعود نقاطه فورًا.',
    parts: [..._P.base(), _P.ka('KA1'), _P.kt('KT1', 'on', 4), _P.k('K1'), _P.ol('F2', 'K1'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.lamp('H1', 'g', 'تشغيل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 KA1.11|S1.14 KA1.14|KA1.14 KA1.A1|KA1.A1 KT1.A1|KA1.11 KT1.15|KT1.18 K1.A1|K1.A1 H1.X1'),
      ..._n(['KA1.A2', 'KT1.A2', 'K1.A2', 'H1.X2'])],
    tasks: [_tPower, _run('اضغط S1 وانتظر المؤقت', 'M1'), _stop('أوقف بالضاغط S0', 'M1'),
      SimTask('غيّر زمن المؤقت ثم جرّب مرة أخرى', (l) => l['KT1'].num_('T') != 4 && motorRunning(l, 'M1'))],
  ),
  // 6
  Circuit(
    id: 'c_offdelay', group: 'دوائر المؤقت', title: 'إيقاف محرك بعد مدة بمؤقت تأخير الفصل', short: 'الإيقاف المتأخر',
    desc: 'الضاغط S1 يشغّل المرحّل KA1 فيشغّل مؤقت تأخير الفصل، الذي تُغلق نقطته 15-18 فورًا وتشغّل K1. وعند الضغط على S0 ينفصل المرحّل، لكن المؤقت يُبقي المحرك يعمل حتى ينقضي الزمن.',
    tip: 'تفيد هذه الدائرة في مراوح التبريد التي يجب أن تستمر قليلًا بعد توقف الآلة.',
    parts: [..._P.base(), _P.ka('KA1'), _P.kt('KT1', 'off', 5), _P.k('K1'), _P.ol('F2', 'K1'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.lamp('H1', 'g', 'تشغيل'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|F2.96 KT1.15|S0.12 S1.13|S1.13 KA1.11|S1.14 KA1.14|KA1.14 KA1.A1|KA1.11 KA1.21|KA1.24 KT1.A1|KT1.18 K1.A1|K1.A1 H1.X1'),
      ..._n(['KA1.A2', 'KT1.A2', 'K1.A2', 'H1.X2'])],
    tasks: [_tPower, _run('شغّل المحرك بالضاغط S1', 'M1'),
      SimTask('اضغط S0، وستجد المحرك ما زال يعمل', (l) => !isOn(l, 'KA1') && motorRunning(l, 'M1')),
      _stop('انتظر حتى يتوقف من تلقاء نفسه', 'M1')],
  ),
  // 7
  Circuit(
    id: 'c_seq_on', group: 'تشغيل أكثر من محرك', title: 'محركان: لا يعمل الثاني إلا إذا كان الأول يعمل', short: 'الثاني بعد الأول',
    desc: 'نقطة مفتوحة من K1 هي 53-54 توصَّل على التوالي مع ملف K2. فما دام M1 متوقفًا يستحيل أن يعمل M2، وإذا توقف M1 توقف M2 معه.',
    tip: 'نقاط الأوفرلود للمحركين على التوالي في بداية دائرة التحكم، فأي عطل يوقف الاثنين.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.k('K2'), _P.ol('F3', 'K2'), _P.stop('S0', 'إيقاف 1'), _P.start('S1', 'تشغيل 1'), _P.stop('S2', 'إيقاف 2'), _P.start('S3', 'تشغيل 2'), _P.m('M1'), _P.m('M2')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.om('F3', 'M2'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 F3.95|F3.96 S0.11|F3.96 S2.11|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 K1.A1|S2.12 S3.13|S3.13 K2.13|S3.14 K2.14|K2.14 K1.53|K1.54 K2.A1'),
      ..._n(['K1.A2', 'K2.A2'])],
    tasks: [_tPower, SimTask('حاول تشغيل M2 بالضاغط S3 أولًا، ولن يعمل', (l) => _pressed(l, 'S3') && !isOn(l, 'K2')),
      _run('شغّل M1 بالضاغط S1', 'M1'), _run('شغّل M2 بالضاغط S3', 'M2'),
      SimTask('أوقف M1 ولاحظ M2', (l) => motorStopped(l, 'M1') && !isOn(l, 'K2'))],
  ),
  // 8
  Circuit(
    id: 'c_seq_off', group: 'تشغيل أكثر من محرك', title: 'محركان: لا يعمل الثاني إلا إذا كان الأول متوقفًا', short: 'الثاني والأول متوقف',
    desc: 'نقطة مغلقة من K1 هي 61-62 على التوالي مع ملف K2. فبمجرد أن يعمل M1 يتوقف M2، ولا يعمل حتى يتوقف M1.',
    tip: 'هذا نوع من منع التداخل الكهربائي بين محركين لا يجوز أن يعملا معًا.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.k('K2'), _P.ol('F3', 'K2'), _P.stop('S0', 'إيقاف 1'), _P.start('S1', 'تشغيل 1'), _P.stop('S2', 'إيقاف 2'), _P.start('S3', 'تشغيل 2'), _P.m('M1'), _P.m('M2')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.om('F3', 'M2'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 F3.95|F3.96 S0.11|F3.96 S2.11|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 K1.A1|S2.12 S3.13|S3.13 K2.13|S3.14 K2.14|K2.14 K1.61|K1.62 K2.A1'),
      ..._n(['K1.A2', 'K2.A2'])],
    tasks: [_tPower, _run('شغّل M2 بالضاغط S3', 'M2'),
      SimTask('شغّل M1 ولاحظ توقف M2', (l) => motorRunning(l, 'M1') && !isOn(l, 'K2')),
      SimTask('حاول تشغيل M2 و M1 يعمل', (l) => _pressed(l, 'S3') && isOn(l, 'K1') && !isOn(l, 'K2'))],
  ),
  // 9
  Circuit(
    id: 'c_seq_time', group: 'تشغيل أكثر من محرك', title: 'محركان: يعمل الثاني بعد الأول بزمن', short: 'التتابع بالمؤقت',
    desc: 'الضاغط S1 يشغّل K1، ونقطة K1 53-54 تشغّل المؤقت KT1. وبعد انقضاء الزمن تشغّل نقطة المؤقت 15-18 الكونتاكتور K2.',
    tip: 'المؤقت متغذٍّ من بعد نقطة K1، فإذا توقف M1 توقف M2 معه.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.kt('KT1', 'on', 4), _P.k('K2'), _P.ol('F3', 'K2'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.m('M1'), _P.m('M2')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.om('F3', 'M2'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 F3.95|F3.96 S0.11|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 K1.A1|K1.13 K1.53|K1.54 KT1.A1|K1.54 KT1.15|KT1.18 K2.A1'),
      ..._n(['K1.A2', 'KT1.A2', 'K2.A2'])],
    tasks: [_tPower, _run('شغّل بالضاغط S1', 'M1'), _run('انتظر حتى يعمل M2 من تلقاء نفسه', 'M2'),
      SimTask('أوقف المحركين بالضاغط S0', (l) => motorStopped(l, 'M1') && motorStopped(l, 'M2'))],
  ),
  // 10
  Circuit(
    id: 'c_seq_swap', group: 'تشغيل أكثر من محرك', title: 'يعمل الأول، ثم الثاني بعد زمن، ثم يتوقف الأول تلقائيًا', short: 'التبديل بالمؤقت',
    desc: 'يعمل K1 ويشغّل المؤقت. وعند انقضاء الزمن يعمل K2 ويُمسك على نفسه، وتفصل نقطته المغلقة 61-62 الكونتاكتور K1.',
    tip: 'لاحظ أن K2 يجب أن يُمسك على نفسه بالنقطة 13-14، لأن المؤقت ينفصل مع K1.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.kt('KT1', 'on', 4), _P.k('K2', true), _P.ol('F3', 'K2'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.m('M1'), _P.m('M2')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.om('F3', 'M2'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 F3.95|F3.96 S0.11|S0.12 S1.13|S0.12 KT1.15|S1.13 K1.13|S1.14 K1.14|K1.14 K2.61|K2.62 K1.A1|K1.13 K1.53|K1.54 KT1.A1|KT1.18 K2.A1|KT1.15 K2.13|K2.14 K2.A1'),
      ..._n(['K1.A2', 'KT1.A2', 'K2.A2'])],
    tasks: [_tPower, _run('شغّل بالضاغط S1', 'M1'),
      SimTask('انتظر حتى يعمل M2 ويتوقف M1', (l) => motorRunning(l, 'M2') && !isOn(l, 'K1')), _stop('أوقف بالضاغط S0', 'M2')],
  ),
  // 11
  Circuit(
    id: 'c_seq3', group: 'تشغيل أكثر من محرك', title: 'تشغيل ثلاثة محركات بالتتابع تلقائيًا بالمؤقتات', short: 'ثلاثة محركات بالتتابع',
    desc: 'يعمل K1 بالضاغط، ثم يشغّل KT1 الكونتاكتور K2، ثم يشغّل KT2 الكونتاكتور K3، كما في خطوط السيور التي تعمل واحدًا بعد الآخر.',
    tip: 'في الواقع تُشغَّل السيور من الأخير إلى الأول حتى لا تتكدس الخامة. فكّر كيف تعكس الترتيب.',
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.kt('KT1', 'on', 3), _P.k('K2', true), _P.ol('F3', 'K2'), _P.kt('KT2', 'on', 3), _P.k('K3'), _P.ol('F4', 'K3'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.m('M1'), _P.m('M2'), _P.m('M3')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.kk('K2', 'K3'), ..._PW.om('F2', 'M1'), ..._PW.om('F3', 'M2'), ..._PW.om('F4', 'M3'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 F3.95|F3.96 F4.95|F4.96 S0.11|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 K1.A1|K1.13 K1.53|K1.54 KT1.A1|K1.54 KT1.15|KT1.18 K2.A1|KT1.15 K2.53|K2.54 KT2.A1|K2.54 KT2.15|KT2.18 K3.A1'),
      ..._n(['K1.A2', 'KT1.A2', 'K2.A2', 'KT2.A2', 'K3.A2'])],
    tasks: [_tPower, _run('شغّل بالضاغط S1', 'M1'), _run('انتظر تشغيل M2', 'M2'), _run('انتظر تشغيل M3', 'M3'),
      SimTask('أوقف الجميع', (l) => motorStopped(l, 'M1') && motorStopped(l, 'M2') && motorStopped(l, 'M3'))],
  ),
  // 12
  Circuit(
    id: 'c_rev', group: 'عكس الحركة', title: 'عكس اتجاه محرك بالضواغط', short: 'العكس بالضواغط',
    desc: 'K1 للأمام و K2 للخلف. ويبدّل K2 الفاز L1 مع L3 ليدور المحرك عكسيًا. ونقطة مغلقة من كل كونتاكتور على التوالي مع ملف الآخر، وهذا منع التداخل الكهربائي، ومعه منع تداخل ميكانيكي.',
    tip: 'دون منع التداخل، إذا عمل الكونتاكتوران معًا حدث قصر بين الفازات. جرّب أن تعكس والمحرك يعمل دون إيقاف.',
    mech: const [['K1', 'K2']],
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.k('K2'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'أمام'), _P.start('S2', 'خلف'), _P.lamp('H1', 'g', 'أمام'), _P.lamp('H2', 'b', 'خلف'), _P.m('M1')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.rev('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S0.12 S2.13|S1.13 K1.13|S1.14 K1.14|K1.14 K2.21|K2.22 K1.A1|K1.A1 H1.X1|S2.13 K2.13|S2.14 K2.14|K2.14 K1.21|K1.22 K2.A1|K2.A1 H2.X1'),
      ..._n(['K1.A2', 'K2.A2', 'H1.X2', 'H2.X2'])],
    tasks: [_tPower, SimTask('شغّل للأمام بالضاغط S1', (l) => motorRunning(l, 'M1') && l['M1'].s.dir == 1),
      SimTask('اضغط S2 والمحرك يعمل، ولن ينعكس', (l) => _pressed(l, 'S2') && isOn(l, 'K1')),
      _stop('أوقف بالضاغط S0', 'M1'), SimTask('شغّل للخلف بالضاغط S2', (l) => motorRunning(l, 'M1') && l['M1'].s.dir == -1)],
  ),
  // 13
  Circuit(
    id: 'c_rev_semi', group: 'عكس الحركة', title: 'عكس الحركة نصف التلقائي بمفتاح نهاية الشوط', short: 'نصف تلقائي',
    desc: 'الضاغط S1 يحرّك العربة إلى الأمام. وعندما تصل إلى LS2 في النهاية، تفصل نقطته المغلقة K1 وتشغّل نقطته المفتوحة K2 فترجع العربة، وعندما تصل إلى LS1 تتوقف وحدها.',
    tip: 'في مفتاح نهاية الشوط نقطتان: 11-12 مغلقة و 23-24 مفتوحة، وتتبادلان حالتيهما عندما تضغط العربة عليه.',
    mech: const [['K1', 'K2']], track: ('M1', 'LS1', 'LS2'),
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.k('K2'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'ابدأ'), _P.lamp('H1', 'g', 'أمام'), _P.lamp('H2', 'b', 'رجوع'), _P.m('M1'), _P.ls('LS1', 'البداية'), _P.ls('LS2', 'النهاية')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.rev('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 K1.13|S1.14 K1.14|K1.14 LS2.11|LS2.12 K2.21|K2.22 K1.A1|K1.A1 H1.X1|K1.13 K2.13|K2.13 LS2.23|LS2.24 K2.14|K2.14 LS1.11|LS1.12 K1.21|K1.22 K2.A1|K2.A1 H2.X1'),
      ..._n(['K1.A2', 'K2.A2', 'H1.X2', 'H2.X2'])],
    tasks: [_tPower, _run('اضغط S1 لتتحرك العربة', 'M1'), SimTask('تصل العربة إلى النهاية وترجع وحدها', (l) => isOn(l, 'K2')),
      SimTask('تتوقف عند البداية', (l) => !isOn(l, 'K2') && (cartX(l) ?? 1) < 0.1 && motorStopped(l, 'M1'))],
  ),
  // 14
  Circuit(
    id: 'c_rev_auto', group: 'عكس الحركة', title: 'عكس الحركة التلقائي الترددي بمفاتيح نهاية الشوط', short: 'الحركة الترددية',
    desc: 'تذهب العربة وتعود بين LS1 و LS2 دون توقف. وكل مفتاح نهاية شوط يفصل اتجاهًا ويشغّل الآخر، ولا تتوقف الحركة إلا بالضاغط S0.',
    tip: 'النقطة المفتوحة للمفتاح LS1 على التوازي مع ضاغط الأمام، والنقطة المفتوحة للمفتاح LS2 على التوازي مع ضاغط الخلف.',
    mech: const [['K1', 'K2']], track: ('M1', 'LS1', 'LS2'), trackStart: 0.5,
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.k('K2'), _P.stop('S0', 'إيقاف'), _P.start('S1', 'أمام'), _P.start('S2', 'خلف'), _P.lamp('H1', 'g', 'أمام'), _P.lamp('H2', 'b', 'خلف'), _P.m('M1'), _P.ls('LS1', 'يسار'), _P.ls('LS2', 'يمين')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.rev('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 K1.13|K1.13 LS1.23|LS1.23 S2.13|S2.13 K2.13|K2.13 LS2.23|S1.14 K1.14|K1.14 LS1.24|LS1.24 LS2.11|LS2.12 K2.21|K2.22 K1.A1|K1.A1 H1.X1|S2.14 K2.14|K2.14 LS2.24|LS2.24 LS1.11|LS1.12 K1.21|K1.22 K2.A1|K2.A1 H2.X1'),
      ..._n(['K1.A2', 'K2.A2', 'H1.X2', 'H2.X2'])],
    tasks: [_tPower, _run('ابدأ بالضاغط S1', 'M1'), SimTask('ترجع العربة من عند LS2', (l) => isOn(l, 'K2')),
      SimTask('وتنعكس مرة أخرى عند LS1', (l) => isOn(l, 'K1') && (cartX(l) ?? 1) < 0.3), _stop('أوقف بالضاغط S0', 'M1')],
  ),
  // 15
  Circuit(
    id: 'c_rev_timer', group: 'عكس الحركة', title: 'عكس الحركة بمفتاح نهاية الشوط ومؤقت (توقف عند كل طرف)', short: 'العكس مع التوقف',
    desc: 'مثل الحركة الترددية، لكن العربة تتوقف عند كل طرف مدة قبل أن ترجع. فمفتاح نهاية الشوط يفصل الاتجاه ويشغّل مؤقتًا، والمؤقت هو الذي يشغّل الاتجاه العكسي.',
    tip: 'ينفصل المؤقت وحده بمجرد أن تبتعد العربة عن المفتاح، ويكون الكونتاكتور قد أمسك على نفسه.',
    mech: const [['K1', 'K2']], track: ('M1', 'LS1', 'LS2'), trackStart: 0.5,
    parts: [..._P.base(), _P.k('K1'), _P.ol('F2', 'K1'), _P.k('K2'), _P.kt('KT1', 'on', 3), _P.kt('KT2', 'on', 3), _P.stop('S0', 'إيقاف'), _P.start('S1', 'أمام'), _P.start('S2', 'خلف'), _P.m('M1'), _P.ls('LS1', 'يسار'), _P.ls('LS2', 'يمين')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.rev('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 K1.13|K1.13 KT2.15|KT2.15 S2.13|S2.13 K2.13|K2.13 KT1.15|KT1.15 LS2.23|LS2.23 LS1.23|S1.14 K1.14|K1.14 KT2.18|KT2.18 LS2.11|LS2.12 K2.21|K2.22 K1.A1|S2.14 K2.14|K2.14 KT1.18|KT1.18 LS1.11|LS1.12 K1.21|K1.22 K2.A1|LS2.24 KT1.A1|LS1.24 KT2.A1'),
      ..._n(['K1.A2', 'K2.A2', 'KT1.A2', 'KT2.A2'])],
    tasks: [_tPower, _run('ابدأ بالضاغط S1', 'M1'), SimTask('تتوقف العربة عند LS2 وتنتظر', (l) => l['KT1'].s.on && !isOn(l, 'K1')),
      SimTask('ثم ترجع وحدها', (l) => isOn(l, 'K2')), _stop('أوقف بالضاغط S0', 'M1')],
  ),
  // 16
  Circuit(
    id: 'c_sd', group: 'ستار دلتا', title: 'تشغيل ستار دلتا في اتجاه واحد بمؤقت', short: 'ستار دلتا',
    desc: 'الكونتاكتور الرئيسي KM1 وكونتاكتور الستار KM2 يعملان معًا، فيبدأ المحرك بتوصيلة ستار بتيار أقل بثلاث مرات. وبعد زمن المؤقت ينفصل KM2 ويعمل كونتاكتور الدلتا KM3، فيكمل المحرك بقدرته الكاملة.',
    tip: 'صندوق أطراف المحرك دون قناطر، والأطراف الستة U1 V1 W1 و U2 V2 W2 توصَّل إلى الكونتاكتورات. راقب مؤشر التيار أثناء البدء.',
    mech: const [['KM2', 'KM3']],
    parts: [..._P.base(), _P.k('KM1'), _P.ol('F2', 'KM1'), _P.k('KM2'), _P.k('KM3'), _P.kt('KT1', 'on', 5), _P.stop('S0', 'إيقاف'), _P.start('S1', 'تشغيل'), _P.lamp('H1', 'y', 'ستار'), _P.lamp('H2', 'g', 'دلتا'), _P.m('M1', 'none')],
    wires: [..._PW.feed(), ..._PW.qk('KM1'), ..._PW.om('F2', 'M1'), ..._PW.sd('F2', 'KM3', 'KM2', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S1.13 KM1.13|S1.14 KM1.14|KM1.14 KM1.A1|KM1.A1 KT1.A1|KT1.A1 KT1.15|KT1.16 KM3.21|KM3.22 KM2.A1|KM2.A1 H1.X1|KT1.18 KM2.21|KM2.22 KM3.A1|KM3.A1 H2.X1'),
      ..._n(['KM1.A2', 'KM2.A2', 'KM3.A2', 'KT1.A2', 'H1.X2', 'H2.X2'])],
    tasks: [_tPower, SimTask('شغّل بالضاغط S1 ولاحظ البدء بتوصيلة ستار', (l) => l['M1'].s.mode == 'star'),
      SimTask('انتظر التحويل إلى دلتا', (l) => l['M1'].s.mode == 'delta' && l['M1'].s.spd > 0.5), _stop('أوقف بالضاغط S0', 'M1')],
  ),
  // 17
  Circuit(
    id: 'c_sd2', group: 'ستار دلتا', title: 'ستار دلتا في اتجاهين تلقائيًا بمؤقت', short: 'ستار دلتا في اتجاهين',
    desc: 'K1 للأمام و K2 للخلف كونتاكتوران رئيسيان، ومعهما KM3 للستار و KM4 للدلتا. ويتغذى المؤقت من نقطة أي كونتاكتور رئيسي يعمل، فيحدث التحويل من ستار إلى دلتا في الاتجاهين.',
    tip: 'هناك منعا تداخل: أحدهما بين الأمام والخلف، والآخر بين الستار والدلتا.',
    mech: const [['K1', 'K2'], ['KM3', 'KM4']],
    parts: [..._P.base(), _P.k('K1', true), _P.ol('F2', 'K1'), _P.k('K2', true), _P.k('KM3'), _P.k('KM4'), _P.kt('KT1', 'on', 5), _P.stop('S0', 'إيقاف'), _P.start('S1', 'أمام'), _P.start('S2', 'خلف'), _P.lamp('H1', 'g', 'أمام'), _P.lamp('H2', 'b', 'خلف'), _P.m('M1', 'none')],
    wires: [..._PW.feed(), ..._PW.qk('K1'), ..._PW.kk('K1', 'K2'), ..._PW.rev('K1', 'K2'), ..._PW.om('F2', 'M1'), ..._PW.sd('F2', 'KM4', 'KM3', 'M1'), ..._PW.ctl(),
      ...W('F1.2 F2.95|F2.96 S0.11|S0.12 S1.13|S0.12 S2.13|S1.13 K1.13|S1.14 K1.14|K1.14 K2.21|K2.22 K1.A1|K1.A1 H1.X1|S2.13 K2.13|S2.14 K2.14|K2.14 K1.21|K1.22 K2.A1|K2.A1 H2.X1|K1.13 K1.53|K2.13 K2.53|K1.54 K2.54|K2.54 KT1.A1|KT1.A1 KT1.15|KT1.16 KM4.21|KM4.22 KM3.A1|KT1.18 KM3.21|KM3.22 KM4.A1'),
      ..._n(['K1.A2', 'K2.A2', 'KM3.A2', 'KM4.A2', 'KT1.A2', 'H1.X2', 'H2.X2'])],
    tasks: [_tPower, SimTask('شغّل للأمام بتوصيلة ستار', (l) => l['M1'].s.mode == 'star' && l['M1'].s.dir == 1),
      SimTask('انتظر التحويل إلى دلتا', (l) => l['M1'].s.mode == 'delta' && l['M1'].s.dir == 1),
      SimTask('أوقف ثم شغّل للخلف', (l) => l['M1'].s.mode == 'delta' && l['M1'].s.dir == -1)],
  ),
];

Circuit? circuitById(String id) {
  for (final c in kCircuits) {
    if (c.id == id) return c;
  }
  return null;
}
