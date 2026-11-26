// The measuring instruments: what each one is, its parts, its knob, its jacks and leads,
// and what it reads on a bench (lib/meters/bench.dart).
//
// The numbers match the printed faces in v2/models/inst_faces.py: every needle sweeps
// 45° each side of vertical; the analog multimeter's ohm scale is f = Rc/(Rc+R) with
// Rc = 20 × the range; the megger's is f = log10(1+R/0.05)/log10(1+1000/0.05) (R in MΩ).
import 'dart:math' as math;

import 'bench.dart';

enum Mode { off, dcv, acv, dcma, ohm, buzz, aca, ma, a, batt, ins, none }

class KnobPos {
  final String label;
  final double angle;
  final Mode mode;

  /// full-scale value (V, mA, A), ohm multiplier, or test voltage
  final double range;
  const KnobPos(this.label, this.angle, this.mode, [this.range = 0]);
}

class Part {
  final String node, nameAr, about;
  const Part(this.node, this.nameAr, this.about);
}

class LeadDef {
  final String id, color, kind, nameAr;

  /// cable colour, when it differs from the plug
  final String? cable;
  const LeadDef(this.id, this.color, this.kind, this.nameAr, {this.cable});
}

class JackDef {
  final String id, label, about;
  const JackDef(this.id, this.label, this.about);
}

class Instrument {
  final String key, nameAr, nameEn, short, image;
  final List<Part> parts;
  final List<KnobPos> knob;
  final List<JackDef> jacks;
  final List<LeadDef> leads;
  final List<String> benches;
  final String mount;

  /// the explanation pages: (title, body)
  final List<(String, String)> guide;
  const Instrument({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.short,
    required this.image,
    required this.parts,
    required this.knob,
    required this.jacks,
    required this.leads,
    required this.benches,
    required this.mount,
    required this.guide,
  });

  bool get analog => key == 'avo' || key == 'megger' || key == 'watt';
}

// ------------------------------------------------------------------ the five instruments
const avo = Instrument(
  key: 'avo',
  nameAr: 'الأفوميتر التناظري (أبو مؤشر)',
  nameEn: 'Analog multimeter (AVO)',
  short: 'جهد AC وDC، مقاومة، تيار DC صغير، واختبار توصيل بالصوت. المؤشر بيتحرك على تدريج مرسوم.',
  image: 'assets/images/instruments/avo.webp',
  mount: 'mount_meter',
  benches: ['board', 'motor'],
  parts: [
    Part('scale', 'لوحة التدريج', 'عليها كذا تدريج: الأخضر فوق للأوم (الصفر يمين واللانهاية شمال)، والأسود للجهد والتيار (0–10 و0–50 و0–250)، والأحمر لجهد AC الصغير 10 فولت. بتقرا على التدريج اللي آخره قريب من الرينج اللي اخترته.'),
    Part('needle', 'المؤشر (الإبرة)', 'ملف صغير متعلق بين قطبين مغناطيس، لما يعدي فيه تيار يلف ومعاه الإبرة. الحركة بتبقى ناعمة وبيتهز شوية قبل ما يثبت.'),
    Part('window', 'الزجاج والمراية', 'تحت التدريج في شريط مراية: بص على الإبرة لحد ما خيالها في المراية يختفي وراها، كده عينك عمودية والقراية مظبوطة من غير خطأ زاوية (parallax).'),
    Part('zero_screw', 'مسمار ضبط الصفر الميكانيكي', 'قبل أي قياس والجهاز مفصول، لازم الإبرة تقف على الصفر الشمال. لو مش واقفة، لف المسمار ده بمفك صغير لحد ما تيجي على الصفر بالظبط.'),
    Part('knob', 'مفتاح اختيار الوظيفة والرينج', 'بيختار إنت بتقيس إيه وأقصى قيمة: DCV أو ACV (جهد مستمر أو متردد)، DCmA (تيار مستمر)، Ω (مقاومة)، وBUZZ (توصيل بصفارة). القاعدة الذهبية: لو مش عارف القيمة ابدأ بأعلى رينج وانزل.'),
    Part('ohm_adj', 'مفتاح ضبط صفر الأوم (0Ω ADJ)', 'في وضع الأوم، لمّس المجسين في بعض: المفروض الإبرة تروح لصفر الأوم يمين. لو مارحتش (البطارية بتضعف) لف المفتاح ده لحد ما تقف على الصفر. لازم تعيدها كل ما تغير رينج الأوم.'),
    Part('jack_com', 'مدخل COM (السالب)', 'بيدخل فيه الكابل الأسود دايمًا، في كل أنواع القياس.'),
    Part('jack_v', 'مدخل +VΩmA', 'بيدخل فيه الكابل الأحمر لقياس الجهد والمقاومة والتيار الصغير.'),
    Part('jack_10a', 'مدخل DC 10A', 'للتيار المستمر الكبير بس (لحد 10 أمبير) والجهاز بيتوصل توالي. خلي بالك: لو حطيت الأحمر هنا ولمست فازة ونيوترال يبقى قصر وشرارة.'),
    Part('panel', 'لوحة الرينجات', 'الألوان بتجمع الوظايف: أبيض للـ DCV، أحمر للـ ACV، أزرق للـ DCmA، أخضر للأوم.'),
    Part('case', 'الجسم', 'جسم بلاستيك معزول بحامل من ورا، ومكتوب عليه فئة الأمان CAT III 600V: يعني ينفع على لوحات التوزيع لحد 600 فولت.'),
  ],
  knob: [
    KnobPos('OFF', 0, Mode.off),
    KnobPos('DCV 2.5', 20, Mode.dcv, 2.5),
    KnobPos('DCV 10', 40, Mode.dcv, 10),
    KnobPos('DCV 50', 60, Mode.dcv, 50),
    KnobPos('DCV 250', 80, Mode.dcv, 250),
    KnobPos('DCV 1000', 100, Mode.dcv, 1000),
    KnobPos('ACV 10', 120, Mode.acv, 10),
    KnobPos('ACV 50', 140, Mode.acv, 50),
    KnobPos('ACV 250', 160, Mode.acv, 250),
    KnobPos('ACV 750', 180, Mode.acv, 750),
    KnobPos('DCmA 250', 200, Mode.dcma, 250),
    KnobPos('DCmA 25', 220, Mode.dcma, 25),
    KnobPos('Ω ×10k', 240, Mode.ohm, 10000),
    KnobPos('Ω ×1k', 260, Mode.ohm, 1000),
    KnobPos('Ω ×10', 280, Mode.ohm, 10),
    KnobPos('Ω ×1', 300, Mode.ohm, 1),
    KnobPos('BUZZ', 320, Mode.buzz, 1),
  ],
  jacks: [
    JackDef('com', 'COM', 'الأسود'),
    JackDef('v', '+VΩmA', 'الأحمر للجهد والأوم'),
    JackDef('10a', 'DC 10A', 'تيار مستمر كبير'),
  ],
  leads: [LeadDef('red', 'red', 'probe', 'المجس الأحمر'), LeadDef('black', 'black', 'probe', 'المجس الأسود')],
  guide: [
    ('يعني إيه أفوميتر؟', 'الاسم جاي من Ampere-Volt-Ohm: جهاز واحد بيقيس الأمبير والفولت والأوم. النوع التناظري ليه مؤشر بيتحرك على تدريج، وده بيخليك تشوف التغيير والتذبذب بعينك، وهو اللي اتعلمت عليه أجيال الكهربائية في مصر.'),
    ('التوصيل الصح', '1) الكابل الأسود في COM دايمًا.\n2) الكابل الأحمر في +VΩmA للجهد والأوم.\n3) اختار الوظيفة والرينج قبل ما تلمس الدائرة.\n4) الجهد: المجسين على النقطتين (توازي).\n5) التيار: لازم تفتح الدائرة والجهاز يبقى جزء منها (توالي).\n6) الأوم: الدائرة لازم تكون مفصولة تمامًا.'),
    ('إزاي تقرا التدريج؟', 'لو الرينج ACV 250 اقرا على صف 0–250 مباشرة. لو الرينج 50 اقرا على صف 0–50. لو 10 اقرا على 0–10. لو 750 اقرا على صف 0–250 واضرب في 3. الأوم: اقرا الرقم على التدريج الأخضر واضربه في الرينج (×1، ×10، ×1k…).'),
    ('الأمان أولًا', '• متقيسش أوم ولا تيار على دائرة فيها كهربا.\n• متغيرش الرينج والمجسات على الدائرة.\n• مسك المجسات من ورا الحلقة الواقية بس.\n• افحص الكابلات قبل الاستخدام: أي شرخ في العزل يبقى ممنوع.\n• لما تخلص رجّع المفتاح على OFF.'),
  ],
);

const dmm = Instrument(
  key: 'dmm',
  nameAr: 'الأفوميتر الديجيتال',
  nameEn: 'Digital multimeter',
  short: 'شاشة أرقام مع اختيار تلقائي للرينج: جهد، مقاومة، توصيل بصفارة، وتيار لحد 10 أمبير.',
  image: 'assets/images/instruments/dmm.webp',
  mount: 'mount_meter',
  benches: ['board', 'motor'],
  parts: [
    Part('lcd', 'الشاشة', 'بتعرض القيمة والوحدة: V وA وΩ، ونوع التيار AC أو DC، وكلمة AUTO لما الجهاز بيختار الرينج لوحده. OL يعني القيمة أكبر من الرينج (أو مفيش توصيل في الأوم).'),
    Part('knob', 'مفتاح الوظائف', 'V~ جهد متردد، V= جهد مستمر، Ω مقاومة، •))) توصيل بصفارة، mA وA للتيار. مفيش رينجات كتير لأن الديجيتال بيختارها لوحده.'),
    Part('buttons', 'زراير SELECT وHOLD وRANGE', 'HOLD بيثبت القراءة على الشاشة عشان تقراها بعد ما تشيل المجسات. RANGE بيلغي الاختيار التلقائي. SELECT بيبدّل بين وظيفتين على نفس الوضع.'),
    Part('jack_com', 'مدخل COM', 'الكابل الأسود دايمًا.'),
    Part('jack_v', 'مدخل VΩ', 'الأحمر للجهد والمقاومة والتوصيل.'),
    Part('jack_ma', 'مدخل mA', 'للتيار الصغير لحد 400 مللي أمبير، وعليه فيوز صغير.'),
    Part('jack_10a', 'مدخل 10A', 'للتيار الكبير لحد 10 أمبير بفيوز سيراميك. أشهر غلطة: تنسى الأحمر هنا وتقيس جهد، فيبقى قصر والفيوز يضرب.'),
    Part('holster', 'الجراب المطاط', 'بيحمي الجهاز من الوقعة، وفيه حامل ومغناطيس يعلقه على باب اللوحة.'),
    Part('panel', 'لوحة الوظائف وفئة الأمان', 'CAT III 1000V وCAT IV 600V: الجهاز آمن على لوح التوزيع وحتى على مدخل الكهربا من الشبكة.'),
  ],
  knob: [
    KnobPos('OFF', -75, Mode.off),
    KnobPos('V~', -45, Mode.acv, 1000),
    KnobPos('V=', -15, Mode.dcv, 1000),
    KnobPos('Ω', 15, Mode.ohm, 1),
    KnobPos('•)))', 45, Mode.buzz, 1),
    KnobPos('mA', 75, Mode.ma, 400),
    KnobPos('A', 105, Mode.a, 10),
  ],
  jacks: [
    JackDef('10a', '10A', 'تيار كبير'),
    JackDef('ma', 'mA', 'تيار صغير'),
    JackDef('com', 'COM', 'الأسود'),
    JackDef('v', 'VΩ', 'الأحمر'),
  ],
  leads: [LeadDef('red', 'red', 'probe', 'المجس الأحمر'), LeadDef('black', 'black', 'probe', 'المجس الأسود')],
  guide: [
    ('ليه ديجيتال؟', 'القراية رقم مباشر من غير حسابات، ودقته أعلى، وبيختار الرينج لوحده، ومقاومته الداخلية كبيرة جدًا (10 ميجا أوم) فمبيأثرش على الدائرة. عيبه إن التغيير السريع صعب تتابعه على الأرقام.'),
    ('التوصيل الصح', '1) الأسود في COM.\n2) الأحمر في VΩ للجهد والأوم والتوصيل.\n3) للتيار: الأحمر في A أو mA، والجهاز توالي في الدائرة بعد ما تفتحها.\n4) بعد قياس التيار رجّع الأحمر فورًا لـ VΩ.'),
    ('اختبار الاستمرارية •)))', 'بيصفر لو المقاومة أقل من حوالي 30 أوم: سريع لاختبار الأرضي والفيوزات والكابلات، والدائرة مفصولة.'),
    ('الأمان أولًا', '• افحص الجهاز على مصدر معروف قبل وبعد التأكد من الفصل (prove–test–prove).\n• متقيسش تيار بالتوازي أبدًا.\n• لو الفيوز ضرب غيّره بنفس النوع والقيمة.'),
  ],
);

const clampMeter = Instrument(
  key: 'clamp',
  nameAr: 'الكلامب ميتر (كلامب أمبير)',
  nameEn: 'Clamp meter',
  short: 'بيقيس التيار من غير ما تفك السلك: تقفل الفكين حوالين سلك واحد وتقرا. وكمان جهد وأوم بالمجسات.',
  image: 'assets/images/instruments/clamp.webp',
  mount: 'mount_clamp',
  benches: ['board'],
  parts: [
    Part('jaw', 'الفك المتحرك', 'نص حلقة من الحديد السيليكوني بيتفتح بالزناد. المجال المغناطيسي حوالين السلك بيعدي في الحلقة ويتحول لتيار صغير بيقيسه الجهاز (محول تيار).'),
    Part('jaw_fixed', 'الفك الثابت', 'النص التاني من الحلقة. لازم الفكين يقفلوا على بعض كويس من غير وساخة، وإلا القراية تقل.'),
    Part('trigger', 'زناد فتح الفك', 'تدوس عليه يفتح الفك، تدخل السلك، وتسيبه يقفل.'),
    Part('guard', 'حاجز الأصابع', 'الحد اللي إيدك ماتعديهوش ناحية الفكين وأنت ماسك الجهاز على سلك عليه كهربا.'),
    Part('lcd', 'الشاشة', 'القيمة والوحدة (A أو V أو Ω) وعلامة AC.'),
    Part('knob', 'مفتاح الوظائف', '40A~ و400A~ للتيار المتردد (اختار الأصغر اللي يكفي عشان الدقة)، وV~ وV= للجهد، وΩ للمقاومة.'),
    Part('hold', 'زرار HOLD', 'يثبت القراية: مفيد لما السلك في مكان صعب ومش شايف الشاشة.'),
    Part('jack_v', 'مدخل VΩ', 'الكابل الأحمر لقياس الجهد والمقاومة.'),
    Part('jack_com', 'مدخل COM', 'الكابل الأسود.'),
  ],
  knob: [
    KnobPos('OFF', -60, Mode.off),
    KnobPos('40A~', -30, Mode.aca, 40),
    KnobPos('400A~', 0, Mode.aca, 400),
    KnobPos('V~', 30, Mode.acv, 600),
    KnobPos('V=', 60, Mode.dcv, 600),
    KnobPos('Ω', 90, Mode.ohm, 1),
  ],
  jacks: [JackDef('v', 'VΩ', 'الأحمر'), JackDef('com', 'COM', 'الأسود')],
  leads: [LeadDef('red', 'red', 'probe', 'المجس الأحمر'), LeadDef('black', 'black', 'probe', 'المجس الأسود')],
  guide: [
    ('بيقيس إزاي من غير توصيل؟', 'أي سلك بيعدي فيه تيار متردد بيعمل حواليه مجال مغناطيسي متغير. الفكين حلقة حديد بتلم المجال ده، وعليها ملف بيطلع فيه تيار صغير متناسب مع تيار السلك، والجهاز بيحوله لقراية.'),
    ('سلك واحد بس!', 'لو قفلت على الكابل كله (الفازات مع بعض) القراية هتبقى صفر تقريبًا: التيار الرايح والراجع (أو الثلاث فازات) مجموعهم صفر فمجالاتهم بتلغي بعض. علشان كده دايمًا سلك واحد جوه الفك.'),
    ('تيار البدء', 'المحرك وهو بيقوم بيسحب 5 لـ 7 أضعاف تياره العادي لثانية أو اتنين. شوف ده بنفسك: الكلامب على L1 وطفّي Q1 وولّعه تاني.'),
    ('الأمان أولًا', '• امسك الجهاز ورا حاجز الأصابع.\n• متقيسش على سلك عريان من غير عزل لو جهدك أعلى من فئة الجهاز.\n• شيل كابلات المجسات وأنت بتقيس تيار بالفكين.'),
  ],
);

const megger = Instrument(
  key: 'megger',
  nameAr: 'الميجر (جهاز قياس العزل)',
  nameEn: 'Insulation tester (Megger)',
  short: 'بيطلّع جهد DC عالي (250 لـ 1000 فولت) ويقيس مقاومة العزل بالميجا أوم: عزل الملفات للأرضي وبين بعضها وعزل الكابلات.',
  image: 'assets/images/instruments/megger.webp',
  mount: 'mount_box',
  benches: ['motor', 'board'],
  parts: [
    Part('scale', 'تدريج الميجا أوم', 'تدريج لوغاريتمي: من 0 شمال لـ ∞ يمين. الشريط الأحمر تحت 1 ميجا يعني عزل وحش، والأخضر فوقه مقبول. وتحته تدريج أحمر لقياس الجهد المتردد لحد 600 فولت.'),
    Part('needle', 'المؤشر', 'وقت الاختبار بيطلع ببطء: الملفات بتتشحن زي المكثف والقراية بتعلى مع الوقت. استنى لحد ما يثبت (دقيقة في الاختبار الرسمي).'),
    Part('knob', 'مفتاح الجهد والوظيفة', 'BATT لفحص البطاريات، ACV لقياس الجهد قبل الاختبار، و250V أو 500V أو 1000V جهد الاختبار. محرك 400 فولت يتقاس على 500 أو 1000 فولت.'),
    Part('test', 'زرار TEST', 'دوس عليه يبدأ الاختبار وجهد DC العالي يطلع على المجسات. لفّه وهو مدوس يتقفل عشان إيديك تبقى فاضية.'),
    Part('lamp_live', 'لمبة التحذير LIVE', 'بتنور وتزمّر لو المجسات على دائرة فيها كهربا. ساعتها ممنوع تدوس TEST.'),
    Part('jack_line', 'طرف LINE', 'الكابل الأحمر بالمجس: بيتحط على الموصل (الملف أو سلك الكابل).'),
    Part('jack_earth', 'طرف EARTH', 'الكابل الأسود بالماسك (التمساح): بيتمسك في الأرضي أو جسم المحرك.'),
    Part('case', 'الجسم والشنطة', 'جسم متين بحزام للشيل، لأن الجهاز بيتاخد للموقع والماكينات.'),
  ],
  knob: [
    KnobPos('OFF', -60, Mode.off),
    KnobPos('BATT', -30, Mode.batt),
    KnobPos('ACV', 0, Mode.acv, 600),
    KnobPos('250V', 30, Mode.ins, 250),
    KnobPos('500V', 60, Mode.ins, 500),
    KnobPos('1000V', 90, Mode.ins, 1000),
  ],
  jacks: [JackDef('line', 'LINE', 'الأحمر'), JackDef('earth', 'EARTH', 'الأسود')],
  leads: [LeadDef('red', 'red', 'probe', 'كابل LINE (أحمر)'), LeadDef('black', 'black', 'croc', 'كابل EARTH (أسود بماسك)')],
  guide: [
    ('ليه الأفوميتر مينفعش؟', 'الأفوميتر بيقيس بجهد بطارية صغير (3 أو 9 فولت) فالعزل الضعيف بيبان سليم. الميجر بيضغط العزل بجهد قريب من جهد التشغيل أو أعلى (500–1000 فولت) فيكشف الرطوبة والشروخ.'),
    ('خطوات اختبار محرك', '1) افصل الكهربا واقفل المفتاح وعلّق كارت (Lock-out).\n2) اتأكد إن مفيش جهد (ACV).\n3) افتح علبة الترامل، ولو هتختبر بين الملفات فك الكباري.\n4) EARTH على الأرضي أو جسم المحرك، LINE على U1.\n5) اختار 500V أو 1000V ودوس TEST، استنى القراية تثبت.\n6) كرر لـ V1 وW1، وبين U1–V1 وV1–W1 وW1–U1.\n7) بعد الاختبار سيب الماسك ثواني عشان الملف يفرّغ شحنته.'),
    ('القيم المقبولة', 'أقل حاجة مقبولة لمحرك جهد منخفض حوالي 1 ميجا أوم (1 ميجا لكل 1000 فولت + 1). المحرك السليم الناشف بيدي مئات الميجا. لو القراية بين 1 و5 ميجا ابدأ نشّف وراقب، ولو تحت 1 ممنوع التشغيل.'),
    ('الأمان أولًا', '• جهد الميجر بيكهرب: متلمسش المجسات ولا الترامل وقت الاختبار.\n• افصل أي أجهزة إلكترونية (إنفرتر، سوفت ستارتر) قبل الاختبار عشان متتحرقش.\n• فرّغ الشحنة بعد الاختبار.'),
  ],
);

const wattmeter = Instrument(
  key: 'watt',
  nameAr: 'الواتميتر (جهاز قياس القدرة)',
  nameEn: 'Wattmeter',
  short: 'بيقيس القدرة الفعلية بالوات: ملف تيار بيتوصل توالي وملف جهد بيتوصل توازي، والمؤشر بيضرب الاتنين في معامل القدرة.',
  image: 'assets/images/instruments/watt.webp',
  mount: 'mount_box',
  benches: ['board'],
  parts: [
    Part('scale', 'التدريج', '120 قسمة. كل قسمة = 12.5 وات (5 أمبير × 300 فولت ÷ 120). القدرة = عدد الأقسام × 12.5.'),
    Part('needle', 'المؤشر', 'جهاز إلكتروديناميكي: ملف ثابت للتيار وملف متحرك للجهد، والعزم بيتناسب مع V × I × cosφ، فبيقيس القدرة الحقيقية مش الظاهرية.'),
    Part('zero_screw', 'ضبط الصفر', 'قبل التوصيل لف المسمار لحد ما الإبرة تقف على الصفر.'),
    Part('post_ia', 'طرف ± تيار', 'بداية ملف التيار (عليه علامة ±): يتوصل ناحية المصدر.'),
    Part('post_i5', 'طرف 5A', 'نهاية ملف التيار: يتوصل ناحية الحمل. ملف التيار كله توالي مع الحمل.'),
    Part('post_vc', 'طرف ± جهد', 'بداية ملف الجهد (±): يتوصل على نفس الفاز اللي فيها ملف التيار.'),
    Part('post_v300', 'طرف 300V', 'نهاية ملف الجهد: على النيوترال (توازي مع الحمل).'),
    Part('case', 'الصندوق', 'صندوق باكاليت بيد شيل، وجهاز دقيق (Class 0.5) بيستخدم في المعامل والاختبارات.'),
  ],
  knob: [],
  jacks: [
    JackDef('ia', '± A', 'بداية ملف التيار'),
    JackDef('i5', '5 A', 'نهاية ملف التيار'),
    JackDef('vc', '± V', 'بداية ملف الجهد'),
    JackDef('v300', '300 V', 'نهاية ملف الجهد'),
  ],
  leads: [
    LeadDef('ia', 'red', 'croc', 'تيار ± (أحمر)'),
    LeadDef('i5', 'black', 'croc', 'تيار 5A (أسود)'),
    LeadDef('vc', 'red', 'probe', 'جهد ± (أصفر)', cable: 'yellow'),
    LeadDef('v300', 'black', 'probe', 'جهد 300V (أزرق)', cable: 'blue'),
  ],
  guide: [
    ('القدرة الفعلية والظاهرية', 'لو ضربت الجهد في التيار (V × I) هتطلع القدرة الظاهرية بالفولت أمبير. الواتميتر بيقيس القدرة الفعلية P = V × I × cosφ اللي بتتحول شغل وحرارة. في السخان cosφ = 1 فالاتنين زي بعض، في الموتور cosφ أقل من 1 فالوات أقل.'),
    ('التوصيل الصح', '1) افصل القاطع Q3.\n2) فك الكوبري بين X2:L وX2:L\'.\n3) ملف التيار: ± على X2:L (ناحية المصدر)، و5A على X2:L\' (ناحية الحمل).\n4) ملف الجهد: ± على X2:L\'، و300V على X2:N.\n5) رجّع القاطع واقرا.\n6) القدرة = الأقسام × 12.5 وات.'),
    ('المؤشر راح شمال؟', 'يبقى طرفي ملف التيار أو ملف الجهد معكوسين: الطرفين اللي عليهم ± لازم يكونوا على نفس الناحية (المصدر). اقفل القاطع وبدّل طرفين.'),
    ('القدرة في 3 فاز', 'لو الحمل متزن: اقرا فاز واحدة واضرب في 3. لو مش متزن: طريقة الواتميترين (Two-wattmeter) على L1 وL3 مع L2 مرجع، والقدرة = مجموعهم.'),
    ('الأمان أولًا', '• ملف التيار مقاومته شبه صفر: لو اتوصل توازي على الجهد يبقى قصر.\n• متفكش الكوبري والدائرة شغالة: هيعمل شرارة.\n• متعديش 5 أمبير على ملف التيار.'),
  ],
);

const instruments = [avo, dmm, clampMeter, megger, wattmeter];

Instrument instrumentByKey(String k) => instruments.firstWhere((i) => i.key == k);

// ------------------------------------------------------------------ live state of one instrument
class LeadState {
  final LeadDef def;
  String? jack;
  String? at;
  LeadState(this.def);
}

class Lcd {
  final String text, unit;
  final bool ac, dc, auto, hold, beep;
  final String small;
  const Lcd(this.text, this.unit, {this.ac = false, this.dc = false, this.auto = false, this.hold = false, this.beep = false, this.small = ''});
  Map<String, Object?> toJson() => {'on': true, 't': text, 'u': unit, 'ac': ac, 'dc': dc, 'auto': auto, 'hold': hold, 'beep': beep, 'small': small};
}

/// what the instrument shows now
class Reading {
  /// needle position 0..1 (analog), null for digital
  final double? needle;
  final Lcd? lcd;

  /// the reading said in words (shown under the 3D view)
  final String words;

  /// the value in base units (V, A, ohm, MOhm, W) for the guided tasks; NaN when none
  final double value;
  final String unit;
  final bool beep, led, slow;
  final double jitter;

  /// a mistake that would hurt the instrument or the person
  final String? danger;

  /// a hint about how to measure this right
  final String? hint;
  final bool short;
  const Reading({
    this.needle,
    this.lcd,
    this.words = '',
    this.value = double.nan,
    this.unit = '',
    this.beep = false,
    this.led = false,
    this.slow = false,
    this.jitter = 0,
    this.danger,
    this.hint,
    this.short = false,
  });
}

class InstState {
  final Instrument def;
  int knob;
  final List<LeadState> leads;
  String? clampAt;
  bool hold = false, test = false, testLock = false;
  bool ohmZeroed = false;

  /// the probes are touched together (to zero an ohm range)
  bool shorted = false;
  bool fuseBlown = false;
  double testSince = 0;
  Lcd? held;

  InstState(this.def)
      : knob = 0,
        leads = [for (final l in def.leads) LeadState(l)];

  KnobPos? get pos => def.knob.isEmpty ? null : def.knob[knob];
  LeadState lead(String id) => leads.firstWhere((l) => l.def.id == id);
  LeadState? inJack(String jack) {
    for (final l in leads) {
      if (l.jack == jack) return l;
    }
    return null;
  }

  /// the point the lead plugged into [jack] touches
  String? at(String jack) => inJack(jack)?.at;
}

// ------------------------------------------------------------------ formatting
String fmtNum(double v, {int digits = 4}) {
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(0);
  if (a >= 100) return v.toStringAsFixed(1);
  if (a >= 10) return v.toStringAsFixed(2);
  return v.toStringAsFixed(3);
}

String ohmWords(double r) {
  if (!r.isFinite || r > 1e12) return 'ما لا نهاية (مفيش توصيل)';
  if (r >= 1e6) return '${fmtNum(r / 1e6)} ميجا أوم';
  if (r >= 1e3) return '${fmtNum(r / 1e3)} كيلو أوم';
  return '${fmtNum(r)} أوم';
}

String megWords(double m) {
  if (!m.isFinite || m >= 1000) return 'أكبر من 1000 ميجا أوم (∞)';
  return '${fmtNum(m)} ميجا أوم';
}

double ohmF(double r, double rc) => r.isFinite ? rc / (rc + r) : 0;
double megF(double mOhm) => mOhm.isFinite ? math.min(1.0, math.log(1 + mOhm / 0.05) / math.log(1 + 1000 / 0.05)) : 1.0;

// ------------------------------------------------------------------ the readings
final _rnd = math.Random(7);
double _noise(double k) => (_rnd.nextDouble() - 0.5) * 2 * k;

/// what [s] reads on [b] right now
Reading readInstrument(InstState s, Bench b) {
  switch (s.def.key) {
    case 'avo':
      return _avo(s, b);
    case 'dmm':
      return _dmm(s, b);
    case 'clamp':
      return _clamp(s, b);
    case 'megger':
      return _megger(s, b);
    case 'watt':
      return _watt(s, b);
  }
  return const Reading();
}

/// both probe points of a two-lead meter: (plus, com)
(String?, String?) _probes(InstState s, List<String> plusJacks) {
  String? plus;
  for (final j in plusJacks) {
    plus ??= s.at(j);
  }
  return (plus, s.at('com'));
}

const _liveOhm = 'ممنوع تقيس أوم على دائرة فيها كهربا! الجهاز بيقيس ببطاريته هو، والكهربا هتحرق مقاومات الأوم أو الفيوز. افصل الأول واتأكد بالفولت.';
const _shortMsg = 'قصر! الكابل الأحمر في مدخل التيار والمجسات على نقطتين بينهم جهد. مدخل التيار مقاومته شبه صفر، فعدّى تيار قصر وضرب الفيوز. في قياس الجهد الأحمر مكانه VΩ.';

Reading _avo(InstState s, Bench b) {
  final p = s.pos!;
  final red = s.inJack('v') != null ? 'v' : (s.inJack('10a') != null ? '10a' : null);
  final (a, c) = _probes(s, ['v', '10a']);
  final connected = a != null && c != null && s.inJack('com') != null;
  if (red == null || s.inJack('com') == null) {
    if (p.mode == Mode.off) return const Reading(needle: 0, words: 'الجهاز مقفول (OFF)');
    return const Reading(needle: 0, words: 'ركّب الكابلات: الأسود في COM والأحمر في +VΩmA', hint: 'دوس على مدخل في الجهاز يتركب فيه الكابل');
  }
  final v = connected ? b.between(a, c) : Cx.zero;
  final vac = v.abs;
  if (red == '10a') {
    if (connected && vac > 12) {
      return Reading(needle: 1.05, words: 'قصر! الفيوز ضرب', danger: _shortMsg, short: true);
    }
    if (connected) {
      final br = b.bridge(a, c);
      if (br.current.abs > 0.05) {
        return const Reading(needle: 0, jitter: 0.01, words: 'المؤشر بيتهز عند الصفر', hint: 'الأفوميتر التناظري بيقيس تيار DC بس (DC 10A)، وتيار السخان متردد AC. استخدم الكلامب ميتر أو الديجيتال على A.');
      }
    }
    return const Reading(needle: 0, words: 'صفر', hint: 'مدخل 10A للتيار المستمر الكبير بس. للجهد رجّع الأحمر لـ +VΩmA.');
  }
  if (s.fuseBlown && (p.mode == Mode.ohm || p.mode == Mode.buzz || p.mode == Mode.dcma)) {
    return const Reading(needle: 0, words: 'الفيوز ضارب: الجهاز مش بيقيس أوم ولا تيار', hint: 'غيّر الفيوز من زرار "غيّر الفيوز".');
  }
  switch (p.mode) {
    case Mode.off:
      return const Reading(needle: 0, words: 'الجهاز مقفول (OFF)');
    case Mode.acv:
      if (!connected) return Reading(needle: 0, words: 'حط المجسين على نقطتين', unit: 'V', value: double.nan);
      final f = vac / p.range;
      final scale = p.range == 750 ? 'على صف 0–250 واضرب في 3' : (p.range == 10 ? 'على التدريج الأحمر AC10V' : 'على صف 0–${p.range.toInt()}');
      final words = '${vac.toStringAsFixed(0)} فولت متردد  ($scale)';
      if (f > 1.02) {
        return Reading(
            needle: f,
            value: vac,
            unit: 'V',
            words: 'المؤشر خبط في آخر التدريج!',
            danger: f > 1.6 ? 'الجهد ${vac.toStringAsFixed(0)} فولت أكبر بكتير من الرينج ${p.range.toInt()}: الإبرة بتتخبط والملف ممكن يتحرق. ابدأ دايمًا بأعلى رينج (750) وانزل.' : null,
            hint: 'الرينج صغير على الجهد ده: كبّر الرينج.');
      }
      return Reading(needle: f, value: vac, unit: 'V', words: words, hint: f < 0.15 && vac > 1 ? 'المؤشر في أول التدريج: صغّر الرينج عشان القراية تبقى أدق.' : null);
    case Mode.dcv:
      if (!connected) return const Reading(needle: 0, words: 'حط المجسين على نقطتين', unit: 'V');
      if (vac > 12) {
        return Reading(needle: 0.01, jitter: math.min(0.04, vac / p.range * 0.05), value: 0, unit: 'V', words: 'المؤشر بيترعش عند الصفر', hint: 'ده جهد متردد AC والمفتاح على DCV: الجهاز بيشوف متوسط الموجة = صفر. حوّل على ACV.', danger: vac / p.range > 3 ? 'الجهد أعلى بكتير من رينج DC اللي مختاره، والملف بيتحمّل فوق طاقته.' : null);
      }
      return const Reading(needle: 0, value: 0, unit: 'V', words: '0 فولت مستمر');
    case Mode.dcma:
      if (!connected) return const Reading(needle: 0, words: 'التيار بيتقاس توالي: افتح الدائرة والجهاز يقفلها', unit: 'mA');
      if (vac > 12) return Reading(needle: 1.05, words: 'قصر! الفيوز ضرب', danger: 'على وضع التيار الجهاز مقاومته صغيرة جدًا، فلما حطيته على جهد عدّى تيار كبير وضرب الفيوز. التيار يتقاس توالي بس.', short: true);
      final br = b.bridge(a, c);
      if (br.current.abs > 0.05) return const Reading(needle: 1.05, words: 'التيار أكبر من الرينج', danger: 'تيار السخان أمبيرات، والرينج 250 مللي بس: الفيوز ضرب. وكمان ده تيار AC والأفوميتر التناظري بيقيس DC.', short: true);
      return const Reading(needle: 0, words: 'صفر');
    case Mode.ohm:
    case Mode.buzz:
      final rc = 20 * p.range;
      final zero = s.ohmZeroed ? 1.0 : 0.962;
      if (s.shorted) {
        return Reading(needle: zero, value: 0, unit: 'Ω', words: s.ohmZeroed ? 'المؤشر على صفر الأوم: الجهاز مظبوط' : 'المجسين ملموسين: الإبرة مش واصلة للصفر', hint: s.ohmZeroed ? null : 'لف مفتاح 0Ω ADJ لحد ما الإبرة تقف على الصفر يمين.', beep: p.mode == Mode.buzz);
      }
      if (!connected) return const Reading(needle: 0, value: double.infinity, unit: 'Ω', words: 'ما لا نهاية: المجسات مش لامسة حاجة');
      if (vac > 12) return Reading(needle: 1.05, words: 'الإبرة طارت!', danger: _liveOhm, short: true);
      final r = b.resistance(a, c);
      final f = ohmF(r, rc) * zero;
      final scaled = r.isFinite ? r / p.range : double.infinity;
      final beep = p.mode == Mode.buzz && r < 50;
      final rng = p.range >= 1000 ? '×${p.range ~/ 1000}k' : '×${p.range.toInt()}';
      return Reading(
          needle: f,
          value: r,
          unit: 'Ω',
          beep: beep,
          words: r.isFinite && r < 1e8 ? '${ohmWords(r)}  (التدريج ${fmtNum(scaled)} $rng)' : 'ما لا نهاية: مفيش توصيل (أو عزل سليم)',
          hint: !s.ohmZeroed ? 'اضبط صفر الأوم الأول: لمّس المجسين ولف 0Ω ADJ.' : (r.isFinite && f > 0.92 && p.range > 1 ? 'القراية في آخر التدريج: صغّر الرينج.' : (r.isFinite && f < 0.08 && r < 1e8 ? 'القراية مزحومة عند ∞: كبّر الرينج.' : null)));
    default:
      return const Reading(needle: 0);
  }
}

Lcd _lcdOff() => const Lcd('', '');

String _fmt4(double v) {
  // a 4-digit display (6000 counts)
  final a = v.abs();
  String t;
  if (a < 6) {
    t = a.toStringAsFixed(3);
  } else if (a < 60) {
    t = a.toStringAsFixed(2);
  } else if (a < 600) {
    t = a.toStringAsFixed(1);
  } else {
    t = a.toStringAsFixed(0);
  }
  return (v < 0 ? '-' : '') + t;
}

Reading _dmm(InstState s, Bench b) {
  final p = s.pos!;
  if (p.mode == Mode.off) return Reading(lcd: _lcdOff(), words: 'الجهاز مقفول (OFF)');
  final redJack = ['v', 'ma', '10a'].firstWhere((j) => s.inJack(j) != null, orElse: () => '');
  final (a, c) = _probes(s, ['v', 'ma', '10a']);
  final connected = a != null && c != null && s.inJack('com') != null;
  final v = connected ? b.between(a, c) : Cx.zero;
  final vac = v.abs;
  Reading show(Lcd l, String words, {double value = double.nan, String unit = '', bool beep = false, String? hint, String? danger, bool short = false}) {
    final lcd = s.hold ? (s.held ??= l) : l;
    if (!s.hold) s.held = null;
    return Reading(lcd: lcd, words: words, value: value, unit: unit, beep: beep && !s.hold, hint: hint, danger: danger, short: short);
  }

  // the red lead in a current jack across a voltage: a short, whatever the knob says
  if ((redJack == 'ma' || redJack == '10a') && connected && vac > 12) {
    return show(const Lcd('0.000', 'A', ac: true), 'قصر! الفيوز ضرب', danger: _shortMsg, short: true);
  }
  if (s.fuseBlown && (p.mode == Mode.a || p.mode == Mode.ma)) {
    return show(const Lcd('0.000', 'A', ac: true), 'الفيوز ضارب: مفيش قراية تيار', hint: 'غيّر الفيوز من زرار "غيّر الفيوز".');
  }
  switch (p.mode) {
    case Mode.acv:
      if (redJack != 'v') return show(const Lcd('0.0', 'V', ac: true, auto: true), 'صفر', hint: 'لقياس الجهد الكابل الأحمر مكانه VΩ.');
      final val = vac < 0.05 ? 0.0 : vac + _noise(0.15);
      if (val > 1000) return show(const Lcd('OL', 'V', ac: true, auto: true), 'أكبر من رينج الجهاز');
      return show(Lcd(_fmt4(val), 'V', ac: true, auto: true), connected ? '${val.toStringAsFixed(1)} فولت متردد' : 'حط المجسين على نقطتين', value: connected ? vac : double.nan, unit: 'V');
    case Mode.dcv:
      if (redJack != 'v') return show(const Lcd('0.00', 'V', dc: true, auto: true), 'صفر', hint: 'لقياس الجهد الكابل الأحمر مكانه VΩ.');
      final val = connected && vac > 12 ? _noise(0.4) : 0.0;
      return show(Lcd(_fmt4(val), 'V', dc: true, auto: true), connected ? '${val.toStringAsFixed(2)} فولت مستمر' : 'حط المجسين على نقطتين',
          value: 0, unit: 'V', hint: connected && vac > 12 ? 'الجهد ده متردد (AC) والمفتاح على V=، فالقراية قريبة من الصفر. حوّل على V~.' : null);
    case Mode.ohm:
    case Mode.buzz:
      if (redJack != 'v' && redJack != '') return show(const Lcd('OL', 'Ω', auto: true), 'OL', hint: 'للأوم الكابل الأحمر مكانه VΩ.');
      if (s.shorted) return show(const Lcd('0.12', 'Ω', auto: true, beep: true), '0.12 أوم: مقاومة الكابلات نفسها', value: 0.12, unit: 'Ω', beep: true);
      if (!connected) return show(const Lcd('OL', 'MΩ', auto: true), 'OL: مفيش توصيل', value: double.infinity, unit: 'Ω');
      if (vac > 12) return show(Lcd(_fmt4(_noise(300).abs()), 'kΩ', auto: true), 'أرقام عشوائية', danger: _liveOhm.replaceFirst('هتحرق مقاومات الأوم أو الفيوز', 'تبوّظ القراية وممكن تأذي الجهاز (الحماية الداخلية بتشتغل)'));
      final r = b.resistance(a, c) + 0.1;
      final beep = p.mode == Mode.buzz && r < 30;
      Lcd l;
      if (!r.isFinite || r > 60e6) {
        l = Lcd('OL', 'MΩ', auto: true, beep: p.mode == Mode.buzz);
      } else if (r >= 1e6) {
        l = Lcd(_fmt4(r / 1e6), 'MΩ', auto: true);
      } else if (r >= 1e3) {
        l = Lcd(_fmt4(r / 1e3), 'kΩ', auto: true);
      } else {
        l = Lcd(_fmt4(r), 'Ω', auto: true, beep: beep);
      }
      return show(l, r.isFinite && r <= 60e6 ? ohmWords(r) : 'OL: أكبر من 60 ميجا (مفيش توصيل أو عزل سليم)', value: r, unit: 'Ω', beep: beep);
    case Mode.ma:
    case Mode.a:
      final want = p.mode == Mode.a ? '10a' : 'ma';
      if (!connected) return show(Lcd(p.mode == Mode.a ? '0.000' : '000.0', p.mode == Mode.a ? 'A' : 'mA', ac: true), 'التيار بيتقاس توالي: افتح الدائرة وحط الجهاز مكان الكوبري');
      if (redJack == 'v') return show(Lcd('0.000', 'A', ac: true), 'صفر', hint: 'لقياس التيار الأحمر يتنقل لمدخل ${want == '10a' ? '10A' : 'mA'}.');
      final br = b.bridge(a, c);
      final amps = br.current.abs;
      if (redJack == 'ma' && amps > 0.4) {
        return show(const Lcd('0.0', 'mA', ac: true), 'الفيوز ضرب', danger: 'تيار ${amps.toStringAsFixed(2)} أمبير أكبر بكتير من مدخل mA (أقصاه 400 مللي): فيوز الـ mA ضرب. للتيار الكبير استخدم مدخل 10A ووضع A.', short: true);
      }
      if (redJack == '10a' && p.mode == Mode.ma) {
        return show(const Lcd('0.0', 'mA', ac: true), 'صفر', hint: 'الكابل في 10A والمفتاح على mA: حوّل المفتاح على A.');
      }
      final shown = p.mode == Mode.a ? Lcd(_fmt4(amps < 0.005 ? 0 : amps + _noise(0.005)), 'A', ac: true) : Lcd(_fmt4((amps * 1000)), 'mA', ac: true);
      return show(shown, amps < 0.005 ? 'صفر: مفيش تيار ماشي في الجهاز' : '${amps.toStringAsFixed(2)} أمبير متردد', value: amps, unit: 'A',
          hint: amps < 0.05 && b is BoardBench && b.linkX2 && {a, c}.containsAll(['pt_X2_L', 'pt_X2_Lo']) ? 'الكوبري لسه مركّب: التيار كله ماشي فيه مش في الجهاز. فكّه (اقفل Q3 الأول).' : null);
    default:
      return show(_lcdOff(), '');
  }
}

Reading _clamp(InstState s, Bench b) {
  final p = s.pos!;
  if (p.mode == Mode.off) return Reading(lcd: _lcdOff(), words: 'الجهاز مقفول (OFF)');
  Reading show(Lcd l, String words, {double value = double.nan, String unit = '', String? hint, String? danger}) {
    final lcd = s.hold ? (s.held ??= l) : l;
    if (!s.hold) s.held = null;
    return Reading(lcd: Lcd(lcd.text, lcd.unit, ac: lcd.ac, dc: lcd.dc, auto: lcd.auto, hold: s.hold), words: words, value: value, unit: unit, hint: hint, danger: danger);
  }

  if (p.mode == Mode.aca) {
    if (s.clampAt == null) {
      return show(Lcd(p.range == 40 ? '0.00' : '0.0', 'A', ac: true), 'افتح الفك وقفله حوالين سلك واحد', value: 0, unit: 'A');
    }
    final amps = b.clampCurrent(s.clampAt!).abs;
    final v = amps < 0.02 ? 0.0 : amps + _noise(0.01);
    if (v > p.range) return show(const Lcd('OL', 'A', ac: true), 'أكبر من الرينج', hint: 'كبّر الرينج لـ 400A~.');
    final t = p.range == 40 ? v.toStringAsFixed(2) : v.toStringAsFixed(1);
    String? hint;
    if (s.clampAt == 'clamp_CABLE') hint = 'الكابل كله جوه الفك: تيارات الثلاث فازات مجموعها صفر، فالقراية صفر تقريبًا. قيس كل سلك لوحده.';
    if (p.range == 400 && v < 40 && v > 0.5) hint = 'التيار أقل من 40 أمبير: رينج 40A~ أدق.';
    return show(Lcd(t, 'A', ac: true), '${v.toStringAsFixed(2)} أمبير متردد', value: amps, unit: 'A', hint: hint);
  }
  final (a, c) = _probes(s, ['v']);
  final connected = a != null && c != null && s.inJack('com') != null && s.inJack('v') != null;
  final hint0 = s.clampAt != null ? 'الفك مقفول على سلك بس المفتاح مش على الأمبير: حوّل على 40A~.' : null;
  final vac = connected ? b.between(a, c).abs : 0.0;
  switch (p.mode) {
    case Mode.acv:
      final val = vac < 0.05 ? 0.0 : vac + _noise(0.2);
      return show(Lcd(val.toStringAsFixed(1), 'V', ac: true), connected ? '${val.toStringAsFixed(0)} فولت متردد' : 'ركّب الكابلات وحط المجسين', value: connected ? vac : double.nan, unit: 'V', hint: hint0);
    case Mode.dcv:
      return show(const Lcd('0.0', 'V', dc: true), connected ? 'قريب من الصفر' : 'ركّب الكابلات', value: 0, unit: 'V', hint: connected && vac > 12 ? 'ده جهد متردد: حوّل على V~.' : hint0);
    case Mode.ohm:
      if (!connected) return show(const Lcd('OL', 'Ω'), 'OL', hint: hint0);
      if (vac > 12) return show(const Lcd('----', 'Ω'), 'مش هيقيس', danger: _liveOhm);
      final r = b.resistance(a, c) + 0.1;
      if (!r.isFinite || r > 40e6) return show(const Lcd('OL', 'MΩ'), 'OL', value: double.infinity, unit: 'Ω');
      final l = r >= 1e6 ? Lcd(_fmt4(r / 1e6), 'MΩ') : (r >= 1e3 ? Lcd(_fmt4(r / 1e3), 'kΩ') : Lcd(_fmt4(r), 'Ω'));
      return show(l, ohmWords(r), value: r, unit: 'Ω');
    default:
      return show(_lcdOff(), '');
  }
}

Reading _megger(InstState s, Bench b) {
  final p = s.pos!;
  final line = s.at('line'), earth = s.at('earth');
  final connected = line != null && earth != null && s.inJack('line') != null && s.inJack('earth') != null;
  final vac = connected ? b.between(line, earth).abs : 0.0;
  final live = vac > 25 && p.mode != Mode.off;
  switch (p.mode) {
    case Mode.off:
      return const Reading(needle: 0, words: 'الجهاز مقفول (OFF)');
    case Mode.batt:
      return const Reading(needle: 0.88, words: 'البطاريات كويسة (المؤشر في آخر التدريج)', led: false);
    case Mode.acv:
      return Reading(needle: vac / 600, led: live, value: vac, unit: 'V', words: connected ? '${vac.toStringAsFixed(0)} فولت متردد' : 'ركّب الكابلات وحط المجسات', hint: live ? 'في جهد! اقفل المفتاح المحلي واتأكد إن القراية بقت صفر قبل اختبار العزل.' : null);
    case Mode.ins:
      if (live) {
        return Reading(
            needle: s.test ? vac / 600 : 0,
            led: true,
            words: 'تحذير: الدائرة فيها كهربا',
            danger: s.test ? 'دوست TEST والدائرة فيها ${vac.toStringAsFixed(0)} فولت! ده بيبوّظ الميجر وممكن يأذيك. افصل وأمّن الأول.' : null,
            hint: 'لمبة LIVE منورة: ممنوع تدوس TEST.',
            short: s.test);
      }
      if (!s.test) return Reading(needle: 0, words: 'دوس TEST (واستنى القراية تثبت)', hint: !connected ? 'LINE على الملف وEARTH على الأرضي أو الجسم.' : null);
      if (!connected) return const Reading(needle: 1, slow: true, words: '∞: المجسات مش على حاجة', value: double.infinity, unit: 'MΩ');
      final r = b.resistance(line, earth) / 1e6; // MOhm
      // the winding charges like a capacitor: the reading creeps up for a few seconds
      final big = r > 5;
      final k = big ? 1 - 0.75 * math.exp(-s.testSince / 1.4) : 1.0;
      final shown = r.isFinite ? r * k : (s.testSince < 3 ? 400 * k + 2000 * (1 - math.exp(-s.testSince / 0.9)) : double.infinity);
      final verdict = !r.isFinite || r >= 100 ? 'عزل ممتاز' : (r >= 5 ? 'عزل كويس' : (r >= 1 ? 'عزل ضعيف: راقب ونشّف' : 'عزل وحش: ممنوع التشغيل'));
      return Reading(
          needle: megF(shown),
          slow: true,
          value: r.isFinite ? r : double.infinity,
          unit: 'MΩ',
          words: '${megWords(shown)}  ·  $verdict',
          hint: s.testSince < 2.5 && big ? 'القراية بتعلى… استنى لحد ما تثبت.' : (r < 0.01 ? 'القراية صفر تقريبًا: ده توصيل مش عزل. اتأكد إنك مش بتقيس على نفس الملف.' : null));
    default:
      return const Reading(needle: 0);
  }
}

Reading _watt(InstState s, Bench b) {
  final ia = s.at('ia'), i5 = s.at('i5'), vc = s.at('vc'), v3 = s.at('v300');
  final curOk = ia != null && i5 != null && s.inJack('ia') != null && s.inJack('i5') != null;
  final volOk = vc != null && v3 != null && s.inJack('vc') != null && s.inJack('v300') != null;
  if (!curOk && !volOk) return const Reading(needle: 0, words: 'وصّل ملف التيار توالي وملف الجهد توازي', unit: 'W');
  var i = Cx.zero;
  if (curOk) {
    final br = b.bridge(ia, i5);
    if (br.short) {
      return const Reading(needle: -0.03, words: 'قصر على ملف التيار!', danger: 'ملف التيار اتوصل بين نقطتين بينهم جهد (توازي): مقاومته شبه صفر فعدّى تيار قصر. ملف التيار يتوصل توالي مكان الكوبري بس.', short: true);
    }
    i = br.current;
  }
  final v = volOk ? b.between(vc, v3) : Cx.zero;
  final p = v.dotRe(i);
  final q = v.crossIm(i);
  final f = p / 1500;
  final amps = i.abs, volts = v.abs;
  String? hint;
  if (curOk && amps < 0.05 && b is BoardBench && b.linkX2) hint = 'الكوبري لسه مركّب بين L وL\': التيار ماشي فيه مش في الملف. اقفل Q3 وفك الكوبري.';
  if (curOk && !volOk) hint = 'ملف التيار متوصل. وصّل ملف الجهد: ± على X2:L\' و300V على X2:N.';
  if (!curOk && volOk) hint = 'ملف الجهد متوصل. ملف التيار لازم يتوصل توالي مكان الكوبري.';
  if (p < -5) hint = 'المؤشر راح شمال: طرف ± لملف التيار أو الجهد معكوس. اقفل القاطع وبدّل طرفين.';
  if (amps > 6) hint = 'التيار أكبر من 5 أمبير: ملف التيار بيسخن.';
  final div = p / 12.5;
  final words = p.abs() < 2
      ? 'صفر وات'
      : '${p.toStringAsFixed(0)} وات  (${div.toStringAsFixed(0)} قسمة × 12.5)  ·  V=${volts.toStringAsFixed(0)}  I=${amps.toStringAsFixed(2)}A  cosφ=${(volts * amps > 1 ? (p / (volts * amps)) : 0).toStringAsFixed(2)}';
  return Reading(needle: f, value: p, unit: 'W', words: words, hint: hint, danger: p < -5 ? null : null, jitter: q.abs() > 50 ? 0.0 : 0.0);
}
