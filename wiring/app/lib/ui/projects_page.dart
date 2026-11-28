import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/circuits.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'circuits_page.dart';
import 'lab/painters.dart' show text;

class Project {
  final String title;
  final String image;
  final String brief;
  final List<(String, String, String, String)> schedule; // circuit, load, cable, breaker
  final List<String> steps;
  const Project(this.title, this.image, this.brief, this.schedule, this.steps);
}

const projects = <Project>[
  Project('شقة 3 غرف', 'assets/images/proj1.webp', 'تأسيس كامل لشقة 120 م²: 3 غرف وصالة ومطبخ وحمامين، بلوحة 12 خط ومفتاح تسريب.', [
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
  Project('فيلا دورين', 'assets/images/proj2.webp', 'لوحة رئيسية ولوحة فرعية لكل دور، وإنارة سلم بماكينة، وإنارة خارجية بحساس.', [
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
  Project('ورشة صغيرة', 'assets/images/proj3.webp', 'ورشة بماكينات أحادية الوجه وإنارة فلورسنت ولوحة معدنية IP54.', [
    ('إنارة فلورسنت (10 × 36W)', '400 W', '1.5 مم²', '10 A'),
    ('برايز الشغل', '3.5 kW', '4 مم²', '20 A'),
    ('مكنة لحام', '5 kW', '6 مم²', '32 A (C)'),
    ('كمبروسر', '2 HP', '4 مم²', '20 A (C)'),
  ], [
    'لوحة معدنية مؤرّضة بمفتاح تسريب 30mA للبرايز.',
    'مواسير ظاهرة معدنية أو PVC تقيلة.',
    'زراير طوارئ قريبة من الماكينات.',
  ]),
  Project('لوحة رئيسية لعمارة', 'assets/images/proj4.webp', 'غرفة عدادات لعمارة 8 شقق، كل شقة بعدادها وقاطعها، وخدمات مشتركة.', [
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

class ProjectsPage extends StatelessWidget {
  const ProjectsPage();
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'المشروعات العملية',
        body: ListView(padding: const EdgeInsets.all(12), children: [
          GlowCard(
            border: C.gold,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApartmentPage())),
            child: Row(children: [
              const Icon(Icons.house_rounded, color: C.gold, size: 40),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الشقة التفاعلية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('لف في الشقة واضغط على أي أوضة تلاقي دوايرها. كل دايرة تخلصها بتنوّر أوضتها.', style: TextStyle(color: C.dim, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_left),
            ]),
          ),
          const SizedBox(height: 10),
          for (final p in projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlowCard(
                padding: const EdgeInsets.all(8),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectPage(p))),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(p.image, width: 120, height: 90, fit: BoxFit.cover)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(p.brief, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 12, height: 1.4)),
                  ])),
                ]),
              ),
            ),
        ]),
      );
}

class ProjectPage extends StatelessWidget {
  final Project p;
  const ProjectPage(this.p);
  @override
  Widget build(BuildContext context) => PageFrame(
        title: p.title,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: AspectRatio(aspectRatio: 1.9, child: Image.asset(p.image, fit: BoxFit.cover))),
              const SizedBox(height: 10),
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
