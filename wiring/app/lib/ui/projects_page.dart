import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/circuits.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../sim/model.dart';
import '../theme.dart';
import 'calc_page.dart';
import 'circuits_page.dart';
import 'lab/lab_page.dart';
import 'lab/painters.dart';
import 'viewer3d.dart';

/// What the site project adds on top of its circuit: the board schedule and the work order.
class ProjectInfo {
  final String cover; // render
  final List<(String, String, String, String, String)> schedule; // line, what it feeds, breaker, cable, why
  final List<String> stages;
  const ProjectInfo(this.cover, this.schedule, this.stages);
}

const projectInfo = <String, ProjectInfo>{
  'p1': ProjectInfo('jbox6', [
    ('R1', 'كل الغرفة', 'RCCB 25 A / 30 mA', '—', 'بيفصل لو فيه تيار بيهرب لجسم إنسان أو للأرض أكتر من 30 مللي.'),
    ('Q1', 'لمبة السقف', 'MCB 10 A  B', '1.5 مم²', 'الإنارة حمل صغير، و1.5 مم² بيستحمل حوالي 16 أمبير فالقاطع 10 أقل منه.'),
    ('Q2', 'البريزتين', 'MCB 16 A  B', '2.5 مم²', 'البريزة ممكن يتوصل فيها مكواة أو دفاية 2 كيلو، فبنحتاج 16 أمبير وسلك 2.5.'),
  ], [
    'ارسم المسقط وحدد مكان البواطة في نص السقف، والمفتاح جنب الباب على ارتفاع 1.20 م، والبرايز على 30 سم من الأرض.',
    'ركّب علب المفاتيح والبرايز والبواطة، ومد المواسير في خطوط رأسية وأفقية بس (عشان أي حد بعدك يعرف مكان السلك).',
    'اسحب الأسلاك من اللوحة للبواطة: فاز إنارة 1.5، فاز برايز 2.5، نيوترال، أرضي.',
    'من البواطة للمفتاح سلكين، وللمبة سلكين، ولكل بريزة 3 أسلاك.',
    'اربط في البواطة نقطة نقطة بالترتيب واكتب الأرقام.',
    'قبل ما تقفل: اختبار الاستمرارية والعزل بالميجر (أكبر من 1 ميجا أوم).',
    'ركّب الأجهزة، شغّل، واضغط TEST في مفتاح التسريب.',
  ]),
  'p2': ProjectInfo('sw2_1', [
    ('Q1', 'لمبة الطرقة والجرس', 'MCB 10 A  B', '1.5 مم²', 'اللمبة والجرس مع بعض أقل من 100 وات، و10 أمبير كفاية جداً.'),
  ], [
    'مفتاح دفياتير في أول الطرقة وواحد في آخرها، واللمبة في النص، والضاغط برا باب الشقة.',
    'من البواطة لكل مفتاح دفياتير 3 أسلاك (مشترك + متنقلين)، وللضاغط سلكين، وللجرس سلكين.',
    'المتنقلين لونهم رمادي ومتعلمين، والفاز بني.',
    'جرّب الأربع حالات للمفتاحين: كل تغيير في أي مفتاح لازم يغيّر حالة اللمبة.',
  ]),
  'p3': ProjectInfo('ledpanel_1', [
    ('R1', 'كل المطبخ', 'RCCB 25 A / 30 mA', '—', 'المطبخ فيه مية، والتسريب هنا خطر حقيقي.'),
    ('Q1', 'اللمبة والكشاف', 'MCB 10 A  B', '1.5 مم²', 'اللمبة 60 وات والكشاف حوالي 36 وات، يعني أقل من نص أمبير.'),
    ('Q2', 'البريزتين', 'MCB 16 A  B', '2.5 مم²', 'غلاية أو ميكروويف ممكن يسحبوا 1.5 لـ 2 كيلو.'),
  ], [
    'حدد مكان الكشاف تحت الدولاب العلوي، والدرايفر جنبه في مكان يتفتح للصيانة.',
    'برايز الرخامة على ارتفاع 1.10 م وبعيد عن الحوض 60 سم على الأقل.',
    'من البواطة للمفتاح المزدوج 3 أسلاك (فاز + راجعين).',
    'بين الدرايفر والكشاف سلك تيار مستمر بقطبية: أحمر موجب وأسود سالب.',
    'اختبر كل زرار لوحده، وجرّب مفتاح التسريب بزرار TEST.',
  ]),
};

class Study {
  final String title;
  final String model;
  final String brief;
  final List<(String, String, String, String)> schedule; // circuit, load, cable, breaker
  final List<String> steps;
  const Study(this.title, this.model, this.brief, this.schedule, this.steps);
}

const studies = <Study>[
  Study('شقة 3 غرف', 'kwh_meter', 'تأسيس كامل لشقة 120 م²: 3 غرف وصالة ومطبخ وحمامين، بلوحة 12 خط ومفتاح تسريب.', [
    ('إنارة 1 (الغرف)', '800 W', '1.5 مم²', '10 A'),
    ('إنارة 2 (الصالة والمطبخ)', '900 W', '1.5 مم²', '10 A'),
    ('برايز الغرف', '2.5 kW', '2.5 مم²', '16 A'),
    ('برايز الصالة', '2.5 kW', '2.5 مم²', '16 A'),
    ('برايز المطبخ', '3 kW', '2.5 مم²', '16 A'),
    ('غسالة', '2 kW', '2.5 مم²', '16 A'),
    ('سخان', '3 kW', '4 مم²', '20 A'),
    ('تكييف غرفة النوم', '1.5 HP', '4 مم²', '20 A'),
    ('تكييف الصالة', '2.25 HP', '4 مم²', '25 A'),
  ], [
    'استلام المخطط المعماري وتوزيع النقط بالرموز على المسقط.',
    'حصر الخامات: مواسير، علب، أسلاك، لوحة، قواطع.',
    'التكسير وتثبيت العلب والمواسير (أفقي ورأسي بس).',
    'سحب الأسلاك بالألوان الصح وترك 20 سم في كل علبة.',
    'تركيب اللوحة وتوصيل القواطع والقضبان.',
    'اختبار العزل والاستمرارية قبل التشطيب.',
    'التشطيب: مفاتيح وبرايز ووحدات إنارة، ثم تجربة مفتاح التسريب.',
  ]),
  Study('فيلا دورين', 'rccb', 'لوحة رئيسية ولوحة فرعية لكل دور، وإنارة سلم بماكينة، وإنارة خارجية بحساس.', [
    ('تغذية لوحة الدور الأرضي', '12 kW', '10 مم²', '50 A'),
    ('تغذية لوحة الدور الأول', '10 kW', '10 مم²', '40 A'),
    ('إنارة السلم (ماكينة)', '300 W', '1.5 مم²', '10 A'),
    ('إنارة الحديقة', '600 W', '2.5 مم²', '10 A'),
    ('طلمبة المية', '1 HP', '2.5 مم²', '16 A (C)'),
    ('جراج وبوابة', '1.5 kW', '2.5 مم²', '16 A'),
  ], [
    'تصميم لوحة رئيسية تغذي لوحات فرعية (توزيع شجري).',
    'حساب هبوط الجهد لخطوط الحديقة الطويلة.',
    'ماكينة سلم بضاغط في كل دور.',
    'أرضي مستقل بإلكترودين ومقاومة أقل من 5 أوم.',
  ]),
  Study('ورشة صغيرة', 'tube_1', 'ورشة بماكينات أحادية الوجه وإنارة فلورسنت ولوحة معدنية IP54.', [
    ('إنارة فلورسنت (10 × 36W)', '400 W', '1.5 مم²', '10 A'),
    ('برايز الشغل', '3.5 kW', '4 مم²', '20 A'),
    ('مكنة لحام', '5 kW', '6 مم²', '32 A (C)'),
    ('كمبروسر', '2 HP', '4 مم²', '20 A (C)'),
  ], [
    'لوحة معدنية مؤرّضة بمفتاح تسريب 30mA للبرايز.',
    'مواسير ظاهرة معدنية أو PVC تقيلة.',
    'زراير طوارئ قريبة من الماكينات.',
  ]),
  Study('لوحة رئيسية لعمارة', 'mcb_2p', 'غرفة عدادات لعمارة 8 شقق، كل شقة بعدادها وقاطعها، وخدمات مشتركة.', [
    ('كل شقة (8)', '10 kW', '16 مم²', '63 A'),
    ('أسانسير', '7.5 kW', '10 مم² (3 فاز)', '32 A'),
    ('طلمبات المية', '2 HP', '4 مم²', '20 A (C)'),
    ('إنارة السلم', '500 W', '1.5 مم²', '10 A'),
  ], [
    'كابل التغذية الرئيسي من الكشك.',
    'توزيع الشقق على الـ3 فازات بالتساوي.',
    'عداد خدمات للأسانسير والسلم والطلمبات.',
  ]),
];

void _go(BuildContext c, Widget w) {
  Sound.play(Sfx.tap);
  Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage();
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'المشروعات العملية',
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              const Text('مشروعات موقع حقيقية: لوحة وبواطة وكل نقط الغرفة. افتح أي مشروع تلاقي التوصيل الحقيقي والرسومات الأربعة، ووصّله بإيدك وشغّله واكتشف أعطاله.', style: TextStyle(color: C.dim, height: 1.5)),
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth > 900 ? 3 : box.maxWidth > 560 ? 2 : 1;
                final w = (box.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final c in projectCircuits) SizedBox(width: w, child: _ProjectCard(c)),
                ]);
              }),
              const SizedBox(height: 12),
              GlowCard(
                border: C.gold,
                onTap: () => _go(context, const ApartmentPage()),
                child: const Row(children: [
                  Icon(Icons.house_rounded, color: C.gold, size: 40),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('الشقة التفاعلية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('لف في الشقة واضغط على أي أوضة تلاقي دوايرها. كل دايرة تخلصها بتنوّر أوضتها.', style: TextStyle(color: C.dim, fontSize: 12)),
                  ])),
                  Icon(Icons.chevron_left),
                ]),
              ),
              const SectionTitle('دراسات تصميم (جدول أحمال ولوحة)'),
              for (final p in studies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlowCard(
                    padding: const EdgeInsets.all(8),
                    onTap: () => _go(context, StudyPage(p)),
                    child: Row(children: [
                      Container(width: 96, height: 80, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: kRenderBg), child: ModelPicture(p.model)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(p.brief, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 12, height: 1.4)),
                      ])),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class _ProjectCard extends StatelessWidget {
  final CircuitDef c;
  const _ProjectCard(this.c);
  @override
  Widget build(BuildContext context) {
    final done = Progress.i.stars[c.id] ?? 0;
    return GlowCard(
      padding: const EdgeInsets.all(8),
      onTap: () => _go(context, ProjectPage(c)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: boardSize.width / boardSize.height,
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(color: const Color(0xFFDDE2E8), child: CircuitPreview(c, skin: Skin.board, lit: true))),
        ),
        const SizedBox(height: 6),
        Text(c.title.replaceFirst('مشروع: ', ''), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(c.brief, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 12, height: 1.4)),
        const SizedBox(height: 4),
        Row(children: [
          _chip(Icons.cable, '${c.steps.length} سلك'),
          _chip(Icons.widgets_outlined, '${c.parts().where((p) => p.kind != Kind.supply).length} جهاز'),
          const Spacer(),
          for (var i = 0; i < 3; i++) Icon(i < done ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: C.gold),
        ]),
      ]),
    );
  }

  Widget _chip(IconData i, String t) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: C.goldHi), const SizedBox(width: 3), Text(t, style: const TextStyle(fontSize: 11.5))]),
      );
}

/// Bill of materials: every device, and each wire colour with its length estimated from the routes
/// (the training board stands for a 5 m wall, plus 20 cm spare in every box).
List<(String, String)> billOf(CircuitDef c) {
  final s = c.buildDone();
  final count = <String, int>{};
  for (final p in s.parts) {
    if (p.kind == Kind.supply) continue;
    final n = p.kind == Kind.mcb ? '${p.type.name} ${p.rating} A' : p.type.name;
    count[n] = (count[n] ?? 0) + 1;
  }
  final metres = <WireColor, double>{};
  final pre = c.preWires().length;
  for (var i = pre; i < s.wires.length; i++) {
    final pts = wirePoints(s, i);
    if (pts == null) continue;
    var l = 0.0;
    for (var k = 1; k < pts.length; k++) {
      l += (pts[k] - pts[k - 1]).distance;
    }
    final w = s.wires[i];
    metres[w.color] = (metres[w.color] ?? 0) + l / 1000 * 5 + .4;
  }
  return [
    for (final e in count.entries) (e.key, '${e.value}'),
    for (final e in metres.entries) ('سلك ${wireColorNames[e.key]}', '≈ ${e.value.ceil()} م'),
  ];
}

class ProjectPage extends StatelessWidget {
  final CircuitDef c;
  const ProjectPage(this.c);

  @override
  Widget build(BuildContext context) {
    final info = projectInfo[c.id];
    final wide = isWide(context);
    void lab(LabMode m) => _go(context, LabPage(circuit: c, mode: m));
    final board = Container(color: const Color(0xFFDDE2E8), child: CircuitPreview(c, skin: Skin.board, lit: true));
    final left = <Widget>[
      Stack(children: [
        AspectRatio(
          aspectRatio: boardSize.width / boardSize.height,
          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: ZoomBox(child: board)),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'ملء الشاشة',
            onPressed: () => _go(context, FullDrawing(title: c.title, child: board)),
            icon: const Icon(Icons.fullscreen_rounded),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: () => _go(context, CircuitPage(c)),
        icon: const Icon(Icons.layers_outlined),
        label: const Text('الرسومات الأربعة: مجسم، توصيل، وظيفي، مسقط'),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _btn(Icons.play_circle_fill_rounded, 'شغّل المشروع', () => lab(LabMode.demo)),
        _btn(Icons.route_rounded, 'وصّل خطوة بخطوة', () => lab(LabMode.guide)),
        _btn(Icons.emoji_events_rounded, 'وصّل لوحدك', () => lab(LabMode.challenge)),
        _btn(Icons.build_circle_rounded, 'اكتشف العطل', () => lab(LabMode.faults)),
      ]),
    ];
    final right = <Widget>[
      Text(c.brief, style: const TextStyle(fontSize: 14.5, height: 1.6)),
      if (info != null) ...[
        const SectionTitle('جدول اللوحة وسبب كل اختيار'),
        for (final r in info.schedule)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: glowCard(r: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(6)), child: Text(r.$1, style: const TextStyle(color: C.navy0, fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Expanded(child: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${r.$3}   ${r.$4}', textDirection: TextDirection.ltr, style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
              const SizedBox(height: 4),
              Text(r.$5, style: const TextStyle(color: C.dim, fontSize: 12.5, height: 1.5)),
            ]),
          ),
      ],
      if (c.tips.isNotEmpty) ...[
        const SectionTitle('نقط البواطة ونصايح الموقع'),
        for (final t in c.tips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.lightbulb_outline, size: 18, color: C.gold), const SizedBox(width: 6), Expanded(child: Text(t, style: const TextStyle(height: 1.5)))]),
          ),
      ],
      const SectionTitle('حصر الخامات'),
      Container(
        decoration: glowCard(r: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(children: [
          for (final b in billOf(c))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [Expanded(child: Text(b.$1)), Text(b.$2, style: const TextStyle(color: C.goldHi, fontWeight: FontWeight.w700))]),
            ),
        ]),
      ),
      const Padding(padding: EdgeInsets.only(top: 4), child: Text('أطوال الأسلاك تقريبية من مسارها على اللوحة، على اعتبار إن الحيطة 5 متر و20 سم زيادة في كل علبة.', style: TextStyle(fontSize: 11.5, color: C.dim))),
      if (info != null) ...[
        const SectionTitle('مراحل التنفيذ في الموقع'),
        for (var i = 0; i < info.stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 12, backgroundColor: C.gold, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: C.navy0, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Expanded(child: Text(info.stages[i], style: const TextStyle(height: 1.5))),
            ]),
          ),
      ],
      const SizedBox(height: 24),
    ];
    return PageFrame(
      title: c.title,
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: ListView(padding: const EdgeInsets.all(16), children: left)),
              Expanded(flex: 2, child: ListView(padding: const EdgeInsets.all(16), children: right)),
            ])
          : ListView(padding: const EdgeInsets.all(12), children: [...left, const SizedBox(height: 8), ...right]),
    );
  }

  Widget _btn(IconData i, String t, VoidCallback f) => OutlinedButton.icon(onPressed: f, icon: Icon(i, color: C.gold), label: Text(t));
}

class StudyPage extends StatelessWidget {
  final Study p;
  const StudyPage(this.p);
  @override
  Widget build(BuildContext context) => PageFrame(
        title: p.title,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              Text(p.brief, style: const TextStyle(fontSize: 15, height: 1.6)),
              const SectionTitle('جدول اللوحة (Schedule)'),
              Container(
                decoration: glowCard(r: 12),
                child: Table(
                  columnWidths: const {0: FlexColumnWidth(2.2)},
                  border: TableBorder(horizontalInside: BorderSide(color: Colors.white.withValues(alpha: .1))),
                  children: [
                    TableRow(decoration: BoxDecoration(color: C.gold.withValues(alpha: .15)), children: [for (final h in ['الدايرة', 'الحمل', 'السلك', 'القاطع']) _cell(h, bold: true)]),
                    for (final r in p.schedule) TableRow(children: [_cell(r.$1), _cell(r.$2), _cell(r.$3), _cell(r.$4)]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _go(context, const PageFrame(title: 'حساب الأحمال', body: LoadCalc())),
                icon: const Icon(Icons.functions, color: C.gold),
                label: const Text('احسب الأحمال بنفسك بالقوانين'),
              ),
              const SectionTitle('مراحل التنفيذ'),
              for (var i = 0; i < p.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 12, backgroundColor: C.gold, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: C.navy0, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.steps[i], style: const TextStyle(height: 1.5))),
                  ]),
                ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      );

  Widget _cell(String s, {bool bold = false}) => Padding(padding: const EdgeInsets.all(8), child: Text(s, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 12.5)));
}

// ------------------------------------------------------------- apartment
const _rooms = <String, Rect>{
  'غرفة النوم': Rect.fromLTWH(140, 0, 340, 300),
  'الحمام': Rect.fromLTWH(480, 0, 180, 300),
  'المطبخ': Rect.fromLTWH(660, 0, 340, 300),
  'الطرقة': Rect.fromLTWH(140, 300, 160, 140),
  'باب الشقة': Rect.fromLTWH(140, 440, 160, 180),
  'الصالة': Rect.fromLTWH(300, 300, 460, 320),
  'الورشة': Rect.fromLTWH(760, 300, 240, 320),
  'السلم': Rect.fromLTWH(0, 0, 140, 620),
};

class ApartmentPage extends StatefulWidget {
  const ApartmentPage();
  @override
  State<ApartmentPage> createState() => _ApartmentPageState();
}

class _ApartmentPageState extends State<ApartmentPage> {
  bool night = true;
  String? sel;

  void _tap(Offset p) {
    for (final e in _rooms.entries) {
      if (e.value.contains(p)) {
        Sound.play(Sfx.click);
        setState(() => sel = e.key);
        _sheet(e.key);
        return;
      }
    }
  }

  void _sheet(String room) {
    final list = circuits.where((c) => c.room == room).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.navy1,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          SectionTitle('دواير $room (${list.length})'),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('مفيش دواير هنا لسه', style: TextStyle(color: C.dim))),
          for (final c in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(height: 130, child: CircuitCard(c))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'الشقة التفاعلية',
        actions: [
          IconButton(
            tooltip: night ? 'نهار' : 'ليل',
            onPressed: () => setState(() => night = !night),
            icon: Icon(night ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: C.goldHi),
          ),
        ],
        body: ListenableBuilder(
          listenable: Progress.i,
          builder: (context, _) => Column(children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1000 / 620,
                    child: LayoutBuilder(
                      builder: (context, box) => GestureDetector(
                        onTapUp: (d) => _tap(d.localPosition * (1000 / box.maxWidth)),
                        child: CustomPaint(size: Size.infinite, painter: _AptPainter(night, sel)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('اضغط على أي أوضة. الأوض اللي خلصت دوايرها في التحدي بتنوّر بالليل.', style: TextStyle(color: C.dim, fontSize: 12.5), textAlign: TextAlign.center),
            ),
          ]),
        ),
      );
}

class _AptPainter extends CustomPainter {
  final bool night;
  final String? sel;
  _AptPainter(this.night, this.sel);

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / 1000;
    c.scale(k);
    final floor = {
      'السلم': const Color(0xFFBDB7AB),
      'الحمام': const Color(0xFFB9D7E6),
      'المطبخ': const Color(0xFFE3D5B8),
      'الورشة': const Color(0xFFA9A9A9),
    };
    for (final e in _rooms.entries) {
      final r = e.value;
      final list = circuits.where((x) => x.room == e.key).toList();
      final done = list.where((x) => Progress.i.stars.containsKey(x.id)).length;
      final lit = list.isNotEmpty && done > 0;
      c.drawRect(r, Paint()..color = floor[e.key] ?? const Color(0xFFD9B98B));
      if (floor[e.key] == null) {
        // parquet
        final g = Paint()
          ..color = Colors.black.withValues(alpha: .06)
          ..strokeWidth = 1;
        for (var y = r.top + 20; y < r.bottom; y += 20) {
          c.drawLine(Offset(r.left, y), Offset(r.right, y), g);
        }
      }
      if (night) {
        c.drawRect(r, Paint()..color = const Color(0xFF050B1E).withValues(alpha: lit ? .25 : .72));
        if (lit) {
          final ctr = r.center;
          final rad = math.max(r.width, r.height) * .7;
          c.drawCircle(ctr, rad, Paint()
            ..shader = RadialGradient(colors: [const Color(0xFFFFE6A0).withValues(alpha: .55 * done / list.length + .15), Colors.transparent]).createShader(Rect.fromCircle(center: ctr, radius: rad)));
        }
      }
      if (sel == e.key) {
        c.drawRect(r.deflate(4), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = C.gold);
      }
      // lamp symbol in the middle of the ceiling
      final lamp = r.center - const Offset(0, 30);
      c.drawCircle(lamp, 12, Paint()..color = lit && night ? const Color(0xFFFFF3C4) : Colors.white70);
      text(c, e.key, r.center + const Offset(0, 6), size: 18, color: night && !lit ? Colors.white70 : const Color(0xFF1B2A4A), w: FontWeight.w700);
      text(c, list.isEmpty ? '' : '$done / ${list.length} دواير', r.center + const Offset(0, 30), size: 13, color: night && !lit ? Colors.white60 : const Color(0xFF37474F));
    }
    // walls
    final wall = Paint()
      ..color = const Color(0xFF263238)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    for (final r in _rooms.values) {
      c.drawRect(r, wall);
    }
    // doors (gaps)
    final gap = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = 10;
    for (final d in [
      [const Offset(140, 500), const Offset(140, 560)],
      [const Offset(220, 300), const Offset(280, 300)],
      [const Offset(300, 340), const Offset(300, 400)],
      [const Offset(560, 300), const Offset(620, 300)],
      [const Offset(700, 300), const Offset(750, 300)],
      [const Offset(760, 420), const Offset(760, 480)],
    ]) {
      c.drawLine(d[0], d[1], gap);
    }
  }

  @override
  bool shouldRepaint(_AptPainter o) => true;
}
