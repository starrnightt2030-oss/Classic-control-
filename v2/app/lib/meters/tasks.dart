// Guided live experiments: each one a list of steps the trainee does on the 3D bench.
// A step turns green once it has been true at least once (so a series of measurements
// can be ticked off one after the other), except the steps marked `hold`, which must
// stay true (the knob on the right range, the lead in the right jack).
import 'bench.dart';
import 'instruments.dart';

class Ctx {
  final InstState s;
  final Bench b;
  final Reading r;
  const Ctx(this.s, this.b, this.r);

  bool lead(String color, String jack) => s.leads.any((l) => l.def.color == color && l.jack == jack);
  bool knob(String label) => s.pos?.label == label;

  /// the two probes (whatever lead) are on these two points
  bool on(String a, String b) {
    final at = {for (final l in s.leads) if (l.jack != null && l.at != null) l.at};
    return at.length == 2 && at.containsAll([a, b]);
  }

  bool leadAt(String id, String point) => s.leads.any((l) => l.def.id == id && l.jack != null && l.at == point);
  bool sw(String k) => b.switches[k] ?? false;
  bool near(double v, double lo, double hi) => r.value.isFinite && r.value >= lo && r.value <= hi;
  BoardBench? get board => b is BoardBench ? b as BoardBench : null;
  MotorBench? get motor => b is MotorBench ? b as MotorBench : null;
}

class TStep {
  final String text;
  final bool Function(Ctx) ok;
  final bool hold;
  const TStep(this.text, this.ok, {this.hold = false});
}

class Task {
  final String id, instrument, bench, title, intro, success;
  final List<TStep> steps;
  final void Function(InstState s, Bench b)? setup;
  const Task({required this.id, required this.instrument, required this.bench, required this.title, required this.intro, required this.success, required this.steps, this.setup});
}

class TaskRun {
  final Task task;
  final List<bool> done;
  TaskRun(this.task) : done = List.filled(task.steps.length, false);

  bool get finished => done.every((d) => d);

  /// re-check the steps; true when something changed
  bool update(Ctx c) {
    var changed = false;
    for (var i = 0; i < task.steps.length; i++) {
      final st = task.steps[i];
      final ok = st.ok(c);
      final now = st.hold ? ok : (done[i] || ok);
      if (now != done[i]) {
        done[i] = now;
        changed = true;
      }
    }
    return changed;
  }
}

bool _redVBlackCom(Ctx c) => c.lead('red', 'v') && c.lead('black', 'com');

final tasks = <Task>[
  // ---------------------------------------------------------------- analog multimeter
  Task(
    id: 'avo_phase',
    instrument: 'avo',
    bench: 'board',
    title: 'قياس جهد الفاز مع النيوترال',
    intro: 'أول قياس لأي كهربائي: الجهد بين الفاز L1 والنيوترال على دخول اللوحة.',
    success: 'المؤشر عند 230 على صف 0–250. ده جهد الفاز في مصر (220–230 فولت).',
    steps: [
      TStep('ركّب الكابل الأسود في COM والأحمر في +VΩmA', _redVBlackCom, hold: true),
      TStep('حوّل المفتاح على ACV 250', (c) => c.knob('ACV 250'), hold: true),
      TStep('مجس على "L1 دخول" والتاني على بارة N', (c) => c.on('pt_IN_L1', 'pt_N'), hold: true),
      TStep('اقرا: حوالي 230 فولت', (c) => c.on('pt_IN_L1', 'pt_N') && c.knob('ACV 250') && c.near(c.r.value, 215, 245)),
    ],
  ),
  Task(
    id: 'avo_line',
    instrument: 'avo',
    bench: 'board',
    title: 'الجهد بين فازتين (جهد الخط)',
    intro: 'بين أي فازتين 400 فولت. جرّب الأول على ACV 250 وشوف المؤشر بيخبط، وبعدين صح على 750.',
    success: '400 فولت = 230 × √3. على رينج 750 بتقرا على صف 0–250 وتضرب في 3: المؤشر عند حوالي 133.',
    steps: [
      TStep('الكابلات في COM و+VΩmA', _redVBlackCom, hold: true),
      TStep('المجسين على L1 دخول وL2 دخول', (c) => c.on('pt_IN_L1', 'pt_IN_L2'), hold: true),
      TStep('حوّل على ACV 750 (أعلى رينج)', (c) => c.knob('ACV 750'), hold: true),
      TStep('اقرا حوالي 400 فولت', (c) => c.knob('ACV 750') && c.near(c.r.value, 380, 420)),
      TStep('قيس كمان L2 مع L3', (c) => c.knob('ACV 750') && c.on('pt_IN_L2', 'pt_IN_L3') && c.near(c.r.value, 380, 420)),
    ],
  ),
  Task(
    id: 'avo_dead',
    instrument: 'avo',
    bench: 'board',
    title: 'التأكد من الفصل قبل الشغل',
    intro: 'قبل ما تلمس خط المحرك: اقفل قاطعه واتأكد بالجهاز إن مفيش جهد بين الفازات وبين كل فاز والأرضي.',
    success: 'صفر في كل القياسات: الخط مفصول وآمن. (في الشغل الحقيقي اختبر الجهاز على مصدر شغال قبل وبعد.)',
    steps: [
      TStep('الكابلات في COM و+VΩmA والمفتاح على ACV 750', (c) => _redVBlackCom(c) && c.knob('ACV 750'), hold: true),
      TStep('اقفل القاطع Q1 (دوس على ذراعه)', (c) => !c.sw('tog_Q1'), hold: true),
      TStep('X1:1 مع X1:2 = صفر', (c) => !c.sw('tog_Q1') && c.on('pt_X1_L1', 'pt_X1_L2') && c.near(c.r.value, 0, 5)),
      TStep('X1:1 مع X1:PE = صفر', (c) => !c.sw('tog_Q1') && c.on('pt_X1_L1', 'pt_X1_PE') && c.near(c.r.value, 0, 5)),
      TStep('X1:3 مع X1:PE = صفر', (c) => !c.sw('tog_Q1') && c.on('pt_X1_L3', 'pt_X1_PE') && c.near(c.r.value, 0, 5)),
    ],
  ),
  Task(
    id: 'avo_motor_v',
    instrument: 'avo',
    bench: 'motor',
    title: 'الجهد على ترامل المحرك',
    intro: 'شغّل المفتاح المحلي وقيس الجهد بين أطراف الملفات U1 وV1 وW1.',
    success: 'التلات قراءات 400 فولت متساوية: الفازات سليمة ومتزنة. وبين U1 والأرضي 230.',
    steps: [
      TStep('الكابلات في COM و+VΩmA', _redVBlackCom, hold: true),
      TStep('شغّل المفتاح المحلي Q0 (دوس عليه)', (c) => c.sw('tog_iso'), hold: true),
      TStep('ACV 750: U1 مع V1', (c) => c.knob('ACV 750') && c.on('pt_U1', 'pt_V1') && c.near(c.r.value, 380, 420)),
      TStep('ACV 750: V1 مع W1', (c) => c.knob('ACV 750') && c.on('pt_V1', 'pt_W1') && c.near(c.r.value, 380, 420)),
      TStep('ACV 750: W1 مع U1', (c) => c.knob('ACV 750') && c.on('pt_W1', 'pt_U1') && c.near(c.r.value, 380, 420)),
      TStep('ACV 250: U1 مع PE (حوالي 230)', (c) => c.knob('ACV 250') && c.on('pt_U1', 'pt_PE') && c.near(c.r.value, 215, 245)),
    ],
  ),
  Task(
    id: 'avo_winding',
    instrument: 'avo',
    bench: 'motor',
    title: 'قياس مقاومة الملفات',
    intro: 'المحرك مفصول والكباري متفكوكة: كل ملف لوحده من بدايته لنهايته. الملفات السليمة قيمها متساوية تقريبًا.',
    success: 'التلات ملفات حوالي 1.5 أوم: سليمة ومتساوية. فرق أكتر من 5% بين ملف والتاني يعني قصر لفّات أو وصلة سايبة.',
    steps: [
      TStep('اقفل المفتاح المحلي (المحرك مفصول)', (c) => !c.sw('tog_iso'), hold: true),
      TStep('فك الكباري (زرار "الكباري" تحت)', (c) => c.motor?.links == 'none', hold: true),
      TStep('حوّل على Ω ×1 والكابلات في COM و+VΩmA', (c) => c.knob('Ω ×1') && _redVBlackCom(c), hold: true),
      TStep('اضبط الصفر: لمّس المجسين ولف 0Ω ADJ', (c) => c.s.ohmZeroed),
      TStep('U1 مع U2', (c) => c.knob('Ω ×1') && c.on('pt_U1', 'pt_U2') && c.near(c.r.value, 0.5, 3)),
      TStep('V1 مع V2', (c) => c.knob('Ω ×1') && c.on('pt_V1', 'pt_V2') && c.near(c.r.value, 0.5, 3)),
      TStep('W1 مع W2', (c) => c.knob('Ω ×1') && c.on('pt_W1', 'pt_W2') && c.near(c.r.value, 0.5, 3)),
    ],
  ),
  // ---------------------------------------------------------------- digital multimeter
  Task(
    id: 'dmm_v',
    instrument: 'dmm',
    bench: 'board',
    title: 'جهد الفاز والخط بالديجيتال',
    intro: 'الديجيتال بيختار الرينج لوحده: بس اختار V~.',
    success: 'الرقم مباشر: 230 بين الفاز والنيوترال، و400 بين فازتين.',
    steps: [
      TStep('الأسود في COM والأحمر في VΩ', _redVBlackCom, hold: true),
      TStep('حوّل على V~', (c) => c.knob('V~'), hold: true),
      TStep('L1 دخول مع N', (c) => c.on('pt_IN_L1', 'pt_N') && c.near(c.r.value, 215, 245)),
      TStep('L1 دخول مع L3 دخول', (c) => c.on('pt_IN_L1', 'pt_IN_L3') && c.near(c.r.value, 380, 420)),
      TStep('N مع PE (المفروض قريب من الصفر)', (c) => c.on('pt_N', 'pt_PE') && c.near(c.r.value, 0, 2)),
    ],
  ),
  Task(
    id: 'dmm_amp',
    instrument: 'dmm',
    bench: 'board',
    title: 'قياس تيار السخان توالي',
    intro: 'الأفوميتر بيقيس التيار وهو جزء من الدائرة: نفك الكوبري X2 والجهاز يقفل الدائرة مكانه.',
    success: 'حوالي 4.35 أمبير = 1000 وات ÷ 230 فولت. رجّع الكابل الأحمر لـ VΩ فورًا بعد القياس!',
    steps: [
      TStep('اقفل القاطع Q3 الأول (أمان)', (c) => !c.sw('tog_Q3')),
      TStep('فك الكوبري بين X2:L وX2:L\' (دوس عليه)', (c) => c.board?.linkX2 == false, hold: true),
      TStep('الأحمر في 10A والأسود في COM، والمفتاح على A', (c) => c.lead('red', '10a') && c.lead('black', 'com') && c.knob('A'), hold: true),
      TStep('المجسين على X2:L وX2:L\'', (c) => c.on('pt_X2_L', 'pt_X2_Lo'), hold: true),
      TStep('شغّل Q3 واقرا التيار', (c) => c.sw('tog_Q3') && c.near(c.r.value, 4.0, 4.7)),
    ],
  ),
  Task(
    id: 'dmm_cont',
    instrument: 'dmm',
    bench: 'board',
    title: 'اختبار استمرارية الأرضي',
    intro: 'الأرضي لازم يكون موصّل كويس من البارة لترمينال المحرك: الصفارة تأكد ده بسرعة.',
    success: 'صفّر وقرا أقل من 1 أوم: الأرضي سليم.',
    steps: [
      TStep('الكابلات في COM وVΩ والمفتاح على •)))', (c) => _redVBlackCom(c) && c.knob('•)))'), hold: true),
      TStep('بارة PE مع X1:PE', (c) => c.on('pt_PE', 'pt_X1_PE') && c.r.beep),
    ],
  ),
  Task(
    id: 'dmm_winding',
    instrument: 'dmm',
    bench: 'motor',
    title: 'مقاومة الملفات بالديجيتال',
    intro: 'نفس اختبار الأفوميتر التناظري لكن بالأرقام. المحرك مفصول والكباري متفكوكة.',
    success: 'القيم 1.6 أوم تقريبًا (بمقاومة الكابلات). لو ملف OL يبقى مقطوع.',
    steps: [
      TStep('المحرك مفصول', (c) => !c.sw('tog_iso'), hold: true),
      TStep('الكباري متفكوكة', (c) => c.motor?.links == 'none', hold: true),
      TStep('المفتاح على Ω والكابلات في COM وVΩ', (c) => c.knob('Ω') && _redVBlackCom(c), hold: true),
      TStep('U1 مع U2', (c) => c.on('pt_U1', 'pt_U2') && c.near(c.r.value, 0.5, 3)),
      TStep('V1 مع V2', (c) => c.on('pt_V1', 'pt_V2') && c.near(c.r.value, 0.5, 3)),
      TStep('W1 مع W2', (c) => c.on('pt_W1', 'pt_W2') && c.near(c.r.value, 0.5, 3)),
    ],
  ),
  // ---------------------------------------------------------------- clamp meter
  Task(
    id: 'clamp_motor',
    instrument: 'clamp',
    bench: 'board',
    title: 'تيار المحرك في كل فاز',
    intro: 'المحرك شغال من القاطع Q1. قفّل الفك حوالين كل سلك لوحده.',
    success: 'التلات فازات تيار متقارب (حوالي 7 أمبير): الحمل متزن. لو فاز أعلى بكتير يبقى في مشكلة.',
    steps: [
      TStep('حوّل على 40A~', (c) => c.knob('40A~'), hold: true),
      TStep('القاطع Q1 شغال', (c) => c.sw('tog_Q1') && c.sw('tog_main'), hold: true),
      TStep('السلك L1', (c) => c.s.clampAt == 'clamp_L1' && c.near(c.r.value, 4, 9.5)),
      TStep('السلك L2', (c) => c.s.clampAt == 'clamp_L2' && c.near(c.r.value, 4, 9.5)),
      TStep('السلك L3', (c) => c.s.clampAt == 'clamp_L3' && c.near(c.r.value, 4, 9.5)),
    ],
  ),
  Task(
    id: 'clamp_cable',
    instrument: 'clamp',
    bench: 'board',
    title: 'ليه الكابل كله بيدّي صفر؟',
    intro: 'جرّب تقفل الفك على كابل المحرك كله تحت اللوحة.',
    success: 'صفر تقريبًا! مجموع تيارات الثلاث فازات (متجهات بينها 120°) = صفر. علشان كده سلك واحد بس جوه الفك.',
    steps: [
      TStep('حوّل على 40A~', (c) => c.knob('40A~'), hold: true),
      TStep('قيس سلك L1 لوحده', (c) => c.s.clampAt == 'clamp_L1' && c.near(c.r.value, 4, 9.5)),
      TStep('قفّل على الكابل كله', (c) => c.s.clampAt == 'clamp_CABLE' && c.near(c.r.value, 0, 0.5) && c.sw('tog_Q1')),
    ],
  ),
  Task(
    id: 'clamp_inrush',
    instrument: 'clamp',
    bench: 'board',
    title: 'تيار بدء المحرك',
    intro: 'المحرك وهو بيقوم بيسحب تيار كبير لحظة. خليك على L1 بالرينج الكبير واقفل Q1 وولّعه.',
    success: 'شفت التيار طلع لأكتر من 40 أمبير ثانية وبعدين نزل لتيار التشغيل. ده سبب اختيار قواطع المحركات بمنحنى C أو D.',
    steps: [
      TStep('حوّل على 400A~', (c) => c.knob('400A~'), hold: true),
      TStep('الفك على السلك L1', (c) => c.s.clampAt == 'clamp_L1', hold: true),
      TStep('اقفل Q1', (c) => !c.sw('tog_Q1')),
      TStep('شغّل Q1 وراقب التيار', (c) => c.s.clampAt == 'clamp_L1' && c.r.value > 20),
    ],
  ),
  Task(
    id: 'clamp_heater',
    instrument: 'clamp',
    bench: 'board',
    title: 'تيار السخان والطلمبة',
    intro: 'قيس تيار دائرة Q3 وغيّر نوع الحمل من تحت.',
    success: 'السخان والطلمبة تيارهم قريب (4.4 و4.5 أمبير) لكن القدرة الفعلية مختلفة: السخان 1000 وات والطلمبة 750 بس. الكلامب بيقيس التيار، والقدرة محتاجة واتميتر.',
    steps: [
      TStep('حوّل على 40A~', (c) => c.knob('40A~'), hold: true),
      TStep('الفك على سلك السخان', (c) => c.s.clampAt == 'clamp_Q3', hold: true),
      TStep('الحمل سخان: حوالي 4.35 أمبير', (c) => c.board?.heater == HeaterLoad.heater && c.near(c.r.value, 4.0, 4.7)),
      TStep('غيّر الحمل لطلمبة: حوالي 4.5 أمبير', (c) => c.board?.heater == HeaterLoad.motor && c.near(c.r.value, 4.1, 4.9)),
    ],
  ),
  // ---------------------------------------------------------------- megger
  Task(
    id: 'meg_earth',
    instrument: 'megger',
    bench: 'motor',
    title: 'عزل الملفات مع الأرضي',
    intro: 'أهم اختبار لأي محرك قبل التشغيل وبعد الصيانة. الكباري ممكن تفضل (الثلاث ملفات مع بعض للأرضي).',
    success: 'مئات الميجا أوم: العزل ممتاز. لاحظ القراية كانت بتعلى ببطء: الملفات بتتشحن زي المكثف.',
    steps: [
      TStep('اقفل المفتاح المحلي', (c) => !c.sw('tog_iso'), hold: true),
      TStep('ركّب الكابلات: LINE وEARTH', (c) => c.lead('red', 'line') && c.lead('black', 'earth'), hold: true),
      TStep('اتأكد من مفيش جهد: ACV بين U1 وPE = صفر', (c) => c.knob('ACV') && c.on('pt_U1', 'pt_PE') && c.near(c.r.value, 0, 5)),
      TStep('حوّل على 500V', (c) => c.knob('500V'), hold: true),
      TStep('LINE على U1 وEARTH على PE أو الجسم', (c) => c.leadAt('red', 'pt_U1') && (c.leadAt('black', 'pt_PE') || c.leadAt('black', 'pt_BODY')), hold: true),
      TStep('دوس TEST واستنى 3 ثواني', (c) => c.s.test && c.s.testSince > 3 && c.r.value > 1),
    ],
  ),
  Task(
    id: 'meg_phase',
    instrument: 'megger',
    bench: 'motor',
    title: 'العزل بين الملفات',
    intro: 'لازم الكباري تتفك عشان كل ملف يبقى لوحده، وبعدين بين كل ملفين.',
    success: 'العزل بين الملفات عالي جدًا. لو قراية بين ملفين صغيرة يبقى العزل بينهم اتحرق.',
    steps: [
      TStep('المحرك مفصول والكباري متفكوكة', (c) => !c.sw('tog_iso') && c.motor?.links == 'none', hold: true),
      TStep('حوّل على 500V أو 1000V', (c) => c.knob('500V') || c.knob('1000V'), hold: true),
      TStep('U1 مع V1 (TEST 3 ثواني)', (c) => c.on('pt_U1', 'pt_V1') && c.s.test && c.s.testSince > 3),
      TStep('V1 مع W1', (c) => c.on('pt_V1', 'pt_W1') && c.s.test && c.s.testSince > 3),
      TStep('W1 مع U1', (c) => c.on('pt_W1', 'pt_U1') && c.s.test && c.s.testSince > 3),
    ],
  ),
  Task(
    id: 'meg_fault',
    instrument: 'megger',
    bench: 'motor',
    title: 'اكتشف الملف المبلول',
    intro: 'المحرك ده كان واقف في مكان رطب. قيس كل ملف لوحده مع الجسم وحدد الملف الضعيف.',
    success: 'الملف U عزله أقل من 1 ميجا: ممنوع التشغيل. المحرك يتنشّف (فرن أو سخان) ويتقاس تاني.',
    setup: _dampMotor,
    steps: [
      TStep('المحرك مفصول والكباري متفكوكة', (c) => !c.sw('tog_iso') && c.motor?.links == 'none', hold: true),
      TStep('500V', (c) => c.knob('500V'), hold: true),
      TStep('U1 مع الجسم', (c) => c.leadAt('red', 'pt_U1') && c.s.test && c.s.testSince > 2.5 && (c.leadAt('black', 'pt_BODY') || c.leadAt('black', 'pt_PE'))),
      TStep('V1 مع الجسم', (c) => c.leadAt('red', 'pt_V1') && c.s.test && c.s.testSince > 2.5 && (c.leadAt('black', 'pt_BODY') || c.leadAt('black', 'pt_PE'))),
      TStep('W1 مع الجسم', (c) => c.leadAt('red', 'pt_W1') && c.s.test && c.s.testSince > 2.5 && (c.leadAt('black', 'pt_BODY') || c.leadAt('black', 'pt_PE'))),
    ],
  ),
  Task(
    id: 'meg_cable',
    instrument: 'megger',
    bench: 'board',
    title: 'عزل كابل المحرك من اللوحة',
    intro: 'نختبر الكابل والمحرك مع بعض من ترامل X1 في اللوحة.',
    success: 'العزل عالي: الكابل والمحرك سليمين. لو القراية وحشة، افصل الكابل عند المحرك وكرر عشان تعرف العيب في مين.',
    steps: [
      TStep('اقفل Q1', (c) => !c.sw('tog_Q1'), hold: true),
      TStep('500V والكابلات في LINE وEARTH', (c) => c.knob('500V') && c.lead('red', 'line') && c.lead('black', 'earth'), hold: true),
      TStep('LINE على X1:1 وEARTH على X1:PE', (c) => c.leadAt('red', 'pt_X1_L1') && c.leadAt('black', 'pt_X1_PE'), hold: true),
      TStep('دوس TEST واستنى', (c) => c.s.test && c.s.testSince > 3 && c.r.value > 1),
    ],
  ),
  // ---------------------------------------------------------------- wattmeter
  Task(
    id: 'watt_heater',
    instrument: 'watt',
    bench: 'board',
    title: 'قياس قدرة السخان',
    intro: 'ملف التيار توالي مكان الكوبري X2، وملف الجهد توازي على الحمل.',
    success: '80 قسمة × 12.5 = 1000 وات. السخان معامل قدرته 1 فالقدرة = الجهد × التيار.',
    steps: [
      TStep('اقفل Q3', (c) => !c.sw('tog_Q3')),
      TStep('فك الكوبري X2', (c) => c.board?.linkX2 == false, hold: true),
      TStep('ركّب الكابلات الأربعة في أطراف الجهاز', (c) => c.s.leads.every((l) => l.jack == l.def.id), hold: true),
      TStep('ملف التيار: ± على X2:L و5A على X2:L\'', (c) => c.leadAt('ia', 'pt_X2_L') && c.leadAt('i5', 'pt_X2_Lo'), hold: true),
      TStep('ملف الجهد: ± على X2:L\' و300V على X2:N', (c) => (c.leadAt('vc', 'pt_X2_Lo') || c.leadAt('vc', 'pt_X2_L')) && c.leadAt('v300', 'pt_X2_N'), hold: true),
      TStep('شغّل Q3 واقرا', (c) => c.sw('tog_Q3') && c.near(c.r.value, 950, 1050)),
    ],
  ),
  Task(
    id: 'watt_pf',
    instrument: 'watt',
    bench: 'board',
    title: 'قدرة الموتور ومعامل القدرة',
    intro: 'بنفس التوصيل غيّر الحمل لطلمبة 1 فاز (موتور) وقارن الوات بالجهد × التيار.',
    success: 'الوات 750 بس رغم إن V×I حوالي 1040: معامل القدرة 0.72. الفرق قدرة غير فعالة بتعمل المجال المغناطيسي للموتور.',
    steps: [
      TStep('الواتميتر متوصل صح وQ3 شغال', (c) => c.sw('tog_Q3') && c.leadAt('ia', 'pt_X2_L') && c.leadAt('i5', 'pt_X2_Lo') && c.leadAt('v300', 'pt_X2_N'), hold: true),
      TStep('الحمل سخان: 1000 وات', (c) => c.board?.heater == HeaterLoad.heater && c.near(c.r.value, 950, 1050)),
      TStep('غيّر الحمل لطلمبة: حوالي 750 وات', (c) => c.board?.heater == HeaterLoad.motor && c.near(c.r.value, 700, 800)),
    ],
  ),
];

void _dampMotor(InstState s, Bench b) {
  if (b is MotorBench) b.fault = MotorFault.damp;
}

List<Task> tasksFor(String instrument) => tasks.where((t) => t.instrument == instrument).toList();
