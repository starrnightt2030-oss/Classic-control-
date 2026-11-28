import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/progress.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'calc_page.dart';
import 'lab/lab_page.dart';
import 'lab/painters.dart';
import 'projects_page.dart';
import 'quiz_page.dart';

class MorePage extends StatelessWidget {
  const MorePage();
  void _push(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) => NavyBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Progress.i,
            builder: (context, _) => ListView(padding: const EdgeInsets.all(12), children: [
              const Padding(padding: EdgeInsets.fromLTRB(4, 2, 4, 10), child: GoldText('المزيد', size: 22)),
              _tile(Icons.quiz_rounded, 'الاختبارات وبنك الأسئلة', 'أسئلة بالأبواب وانترفيو وشهادة', () => _push(context, const QuizHome())),
              _tile(Icons.calculate_rounded, 'الحاسبات الهندسية', 'أحمال، كابلات، مواسير، قواطع، أرضي، هبوط جهد', () => _push(context, const CalcPage())),
              _tile(Icons.apartment_rounded, 'المشروعات والشقة التفاعلية', 'شقة، فيلا، ورشة، لوحة عمارة', () => _push(context, const ProjectsPage())),
              _tile(Icons.schema_rounded, 'رسم الدوائر بالرموز', 'ارسم دايرتك بالمخطط الخطي وحاكيها', () => _push(context, const LabPage(skin: Skin.schematic))),
              const SectionTitle('الإعدادات'),
              Container(
                decoration: glowCard(r: 14),
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: C.gold),
                    title: const Text('اسمك (بيظهر في الشهادة)'),
                    subtitle: Text(Progress.i.studentName.isEmpty ? 'اضغط واكتب اسمك' : Progress.i.studentName),
                    onTap: () => _name(context),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_outlined, color: C.gold),
                    title: const Text('الأصوات'),
                    value: Progress.i.sound,
                    onChanged: (v) {
                      Progress.i.setSound(v);
                      Sound.enabled = v;
                      if (!v) Sound.loop(null);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.cast_for_education_outlined, color: C.gold),
                    title: const Text('وضع السبورة التفاعلية'),
                    subtitle: const Text('خط وأزرار أكبر للشاشات الكبيرة 75 بوصة'),
                    value: Progress.i.bigUi,
                    onChanged: Progress.i.setBigUi,
                  ),
                ]),
              ),
              const SectionTitle('عن التطبيق'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: glowCard(r: 14, border: C.gold),
                child: Column(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/logo.webp', width: 96)),
                  const SizedBox(height: 8),
                  const GoldText(AppInfo.nameAr, size: 20),
                  const Text(AppInfo.nameEn, style: TextStyle(color: C.dim)),
                  const Text('الإصدار ${AppInfo.version}', style: TextStyle(color: C.dim, fontSize: 12)),
                  const Divider(color: Colors.white24, height: 24),
                  const Text('تطوير وإعداد', style: TextStyle(color: C.dim, fontSize: 12)),
                  const Text(AppInfo.developer, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Text(AppInfo.role, style: TextStyle(color: C.dim)),
                  const SizedBox(height: 8),
                  const Text('معمل افتراضي لتعليم التمديدات الكهربية السكنية: 21 دايرة تفاعلية بالدليل والتحدي والأعطال، ومعمل حر بالرسم والمحاكاة، ومكتبة ودروس وحاسبات وبنك أسئلة.', textAlign: TextAlign.center, style: TextStyle(height: 1.6, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      );

  Widget _tile(IconData i, String t, String s, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlowCard(
          onTap: f,
          child: Row(children: [
            Icon(i, color: C.gold, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), Text(s, style: const TextStyle(color: C.dim, fontSize: 12))])),
            const Icon(Icons.chevron_left, color: C.dim),
          ]),
        ),
      );

  Future<void> _name(BuildContext context) async {
    final ctl = TextEditingController(text: Progress.i.studentName);
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسمك'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('حفظ'))],
      ),
    );
    if (n != null) Progress.i.setName(n);
  }
}
