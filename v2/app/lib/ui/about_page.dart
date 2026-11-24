import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../services/audio_service.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final comps = repo.all;
    final parts = comps.fold<int>(0, (s, c) => s + c.parts.length);
    final lessons = comps.fold<int>(0, (s, c) => s + c.lessons.length);
    final models = comps.fold<int>(0, (s, c) => s + c.variants.length);
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 900 ? 28.0 : 16.0;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 18, pad, 28), children: [
        Row(children: [
          const AppMark(size: 56),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('معمل الكلاسيك كنترول', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              Text('Classic Control Simulation Lab · v2 (نسخة تجريبية)',
                  textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: CC.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: c.maxWidth >= 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            _stat('${comps.length}', 'مكوّن في المكتبة'),
            _stat('$models', 'مجسم 3D'),
            _stat('$parts', 'جزء ليه شرح'),
            _stat('$lessons', 'درس'),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          decoration: panelBox(),
          child: Column(children: [
            SwitchListTile(
              value: AudioService.instance.sfxOn,
              onChanged: (v) => setState(() => AudioService.instance.sfxOn = v),
              title: const Text('المؤثرات الصوتية', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('صوت لمس الأجزاء والفك والتركيب', style: TextStyle(color: CC.muted, fontSize: 12.5)),
            ),
            const Divider(height: 1, color: CC.line),
            ListTile(
              leading: const CcIcon(CcIcons.audio, color: CC.cyan),
              title: const Text('الشرح الصوتي', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                repo.recordedClips == 0
                    ? 'التسجيلات بالعامية المصرية لسه بتتجهز، والشرح المكتوب موجود كامل.'
                    : 'متضاف ${repo.recordedClips} تسجيل لحد دلوقتي.',
                style: const TextStyle(color: CC.muted, fontSize: 12.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        const SafetyStrip(text: 'التطبيق للتعليم. أي شغل على لوحة حقيقية يكون بعد فصل الكهربا وتحت إشراف مدرب.'),
        const SizedBox(height: 18),
        const SectionTitle('المواصفات المرجعية'),
        const SizedBox(height: 6),
        const Text(
          'IEC 60947 · IEC 60898-1 · IEC 61008-1 · IEC 60204-1 · IEC 60617 · IEC 81346-2 · IEC 60445 · IEC 60073 · IEC 60034',
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12.5, color: CC.text2, fontFamily: CC.mono, height: 1.7),
        ),
        const SizedBox(height: 18),
        const Text('مركز التدريب · ترسانة الإسكندرية', style: TextStyle(fontSize: 13, color: CC.muted)),
      ]);
    });
  }

  Widget _stat(String n, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: panelBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: CC.amber, fontFamily: CC.mono)),
        Text(label, style: const TextStyle(fontSize: 12.5, color: CC.text2)),
      ]),
    );
  }
}
