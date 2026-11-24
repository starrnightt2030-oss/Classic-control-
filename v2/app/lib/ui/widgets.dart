import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/audio_service.dart';
import 'icons.dart';
import 'theme.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CC.text2));
}

class SquareButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const SquareButton({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: active ? CC.amberBg : CC.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: active ? CC.amberLine : CC.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: CcIcon(icon, size: 20, color: active ? CC.amber : CC.text)),
            ),
          ),
        ),
      ),
    );
  }
}

class Thumb extends StatelessWidget {
  final String componentId;
  final double size;
  const Thumb(this.componentId, {super.key, this.size = 120});
  @override
  Widget build(BuildContext context) => Image.asset(
        Repository.instance.thumbFor(componentId),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size, child: const Center(child: CcIcon(CcIcons.library, color: CC.line2, size: 40))),
      );
}

class ContinueCard extends StatelessWidget {
  final Component component;
  final int seen;
  final VoidCallback onOpen;
  const ContinueCard({super.key, required this.component, required this.seen, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final total = component.parts.length;
    final frac = total == 0 ? 0.0 : (seen / total).clamp(0.0, 1.0);
    return Container(
      decoration: panelBox(radius: 22),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: CC.amber, borderRadius: BorderRadius.circular(99)),
              child: Text(seen > 0 ? 'كمّل من حيث وقفت' : 'ابدأ بيه',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: CC.bg)),
            ),
            const SizedBox(height: 8),
            Text(component.nameAr, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
            Text(component.nameEn,
                textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: CC.muted, fontFamily: CC.mono)),
            const SizedBox(height: 8),
            if (total > 0) ...[
              Text('شفت $seen من $total جزء', style: const TextStyle(fontSize: 13, color: CC.text2)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  width: 150,
                  height: 6,
                  child: LinearProgressIndicator(value: frac, backgroundColor: CC.line, color: CC.amber),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: CC.amber,
                foregroundColor: CC.bg,
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('افتح الشرح'),
            ),
          ]),
        ),
        Thumb(component.id, size: 150),
      ]),
    );
  }
}

class ActionTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool soon;
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.soon = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accent == CC.amber ? CC.amberBg : CC.cyanBg;
    return Material(
      color: CC.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: CC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Center(child: CcIcon(icon, size: 22, color: soon ? CC.muted : accent)),
              ),
              const Spacer(),
              if (soon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: CC.line2), borderRadius: BorderRadius.circular(99)),
                  child: const Text('قريبًا', style: TextStyle(fontSize: 10.5, color: CC.muted)),
                ),
            ]),
            const Spacer(),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: soon ? CC.text2 : CC.text)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: CC.muted)),
          ]),
        ),
      ),
    );
  }
}

class SafetyStrip extends StatelessWidget {
  final String text;
  const SafetyStrip({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: panelBox(color: const Color(0xFF1E1A0E), border: CC.amberLine, radius: 14),
      child: Row(children: [
        const CcIcon(CcIcons.warning, color: CC.amber, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'قاعدة السلامة: ', style: TextStyle(color: CC.amber, fontWeight: FontWeight.w700)),
            TextSpan(text: text),
          ]), style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFFF3E3BE))),
        ),
      ]),
    );
  }
}

class CircuitCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;
  const CircuitCard({super.key, required this.title, required this.subtitle, required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CC.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: CC.line)),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 118,
          child: Row(children: [
            Image.asset('assets/images/panel.webp', width: 130, height: 118, fit: BoxFit.cover, alignment: const Alignment(0.4, -0.1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5, color: CC.muted, fontFamily: CC.mono)),
                  const Spacer(),
                  Text(tag, style: const TextStyle(fontSize: 12, color: CC.cyan)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Round play button for a narration clip; shows a hint if not recorded yet.
class VoiceButton extends StatelessWidget {
  final String? audioRef;
  final double size;
  const VoiceButton({super.key, required this.audioRef, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final audio = AudioService.instance;
    final available = Repository.instance.audioAsset(audioRef) != null;
    return ValueListenableBuilder<String?>(
      valueListenable: audio.playing,
      builder: (context, playing, _) {
        final isOn = playing != null && playing == audioRef;
        return Tooltip(
          message: available ? (isOn ? 'إيقاف' : 'اسمع الشرح') : 'الصوت لسه بيتسجل',
          child: Material(
            color: available ? CC.cyan : CC.surface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                if (isOn) {
                  await audio.stopVoice();
                  return;
                }
                final ok = await audio.playVoice(audioRef);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('التسجيل الصوتي للجزء ده لسه مش متضاف. اقرا الشرح لحد ما يوصل.')),
                  );
                }
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(isOn ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: available ? CC.bg : CC.muted, size: size * 0.55),
              ),
            ),
          ),
        );
      },
    );
  }
}

class Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const Pill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected ? CC.amber : CC.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? CC.amber : CC.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? CC.bg : CC.text2)),
          ),
        ),
      ),
    );
  }
}
