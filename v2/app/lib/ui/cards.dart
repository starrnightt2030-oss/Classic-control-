import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/audio_service.dart';
import 'component_page.dart';
import 'icons.dart';
import 'theme.dart';

/// A card that grows into its page (Material container transform) when tapped,
/// with a press-down scale for feel.
class OpenCard extends StatefulWidget {
  final Widget Function(BuildContext context) closed;
  final Widget Function(BuildContext context) open;
  final double radius;
  final VoidCallback? onClosed;
  const OpenCard({super.key, required this.closed, required this.open, this.radius = 22, this.onClosed});

  @override
  State<OpenCard> createState() => _OpenCardState();
}

class _OpenCardState extends State<OpenCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: OpenContainer<void>(
          transitionType: ContainerTransitionType.fadeThrough,
          transitionDuration: const Duration(milliseconds: 520),
          closedColor: CC.surface,
          openColor: CC.bg,
          middleColor: CC.bg,
          closedElevation: 0,
          openElevation: 0,
          closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.radius)),
          tappable: false,
          onClosed: (_) => widget.onClosed?.call(),
          closedBuilder: (context, open) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AudioService.instance.sfx('ui_tap');
              open();
            },
            child: widget.closed(context),
          ),
          openBuilder: (context, _) => widget.open(context),
        ),
      ),
    );
  }
}

/// Big illustrated section card (home carousel).
class SectionCard extends StatelessWidget {
  final String image;
  final String title;
  final String subtitle;
  final String icon;
  final Color accent;
  final bool soon;
  const SectionCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accent = CC.amber,
    this.soon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(image, fit: BoxFit.cover, alignment: const Alignment(0, -0.3)),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.45, 0.72, 1],
            colors: [Color(0x000A111B), Color(0xCC0A111B), Color(0xFA0A111B)],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      PositionedDirectional(
        top: 14,
        start: 14,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xCC0A111B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.6)),
          ),
          child: Center(child: CcIcon(icon, color: accent, size: 22)),
        ),
      ),
      if (soon)
        PositionedDirectional(
          top: 18,
          end: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xCC0A111B), borderRadius: BorderRadius.circular(99), border: Border.all(color: CC.line2)),
            child: const Text('قريبًا', style: TextStyle(fontSize: 11.5, color: CC.text2, fontWeight: FontWeight.w600)),
          ),
        ),
      PositionedDirectional(
        start: 18,
        end: 18,
        bottom: 18,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, height: 1.25, color: Colors.white)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: CC.text2, height: 1.5)),
          const SizedBox(height: 10),
          Row(children: [
            Container(height: 3, width: 34, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(soon ? 'المرحلة الجاية' : 'افتح', style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    ]);
  }
}

/// Horizontally swipeable cards with depth (scale/tilt) and a dots indicator.
class CardCarousel extends StatefulWidget {
  final int count;
  final double height;
  final double viewportFraction;
  final Widget Function(BuildContext context, int index) builder;
  const CardCarousel({super.key, required this.count, required this.builder, this.height = 380, this.viewportFraction = 0.78});

  @override
  State<CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<CardCarousel> {
  late PageController _pc = PageController(viewportFraction: widget.viewportFraction);
  double _page = 0;

  @override
  void didUpdateWidget(covariant CardCarousel old) {
    super.didUpdateWidget(old);
    if (old.viewportFraction != widget.viewportFraction) {
      final p = _pc.hasClients ? (_pc.page ?? 0).round() : 0;
      _pc.dispose();
      _pc = PageController(viewportFraction: widget.viewportFraction, initialPage: p);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (_pc.hasClients && _pc.page != null) setState(() => _page = _pc.page!);
            return false;
          },
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.count,
            padEnds: true,
            itemBuilder: (context, i) {
              final d = (i - _page).clamp(-1.5, 1.5).toDouble();
              final scale = 1 - 0.08 * d.abs();
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(-d * 0.22),
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: (1 - 0.35 * d.abs()).clamp(0.4, 1.0).toDouble(),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: widget.builder(context, i)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < widget.count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: (i - _page).abs() < 0.5 ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: (i - _page).abs() < 0.5 ? CC.amber : CC.line2,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]),
    ]);
  }
}

/// Component card (thumbnail + names) that opens the 3D page.
class ComponentCard extends StatelessWidget {
  final Component component;
  final double width;
  final AutoAction action;
  final VoidCallback? onClosed;
  const ComponentCard({super.key, required this.component, this.width = 170, this.action = AutoAction.none, this.onClosed});

  @override
  Widget build(BuildContext context) {
    final seen = Repository.instance.seenParts(component.id).length;
    final total = component.parts.length;
    return SizedBox(
      width: width,
      child: OpenCard(
        radius: 20,
        onClosed: onClosed,
        open: (_) => ComponentPage(componentId: component.id, autoAction: action),
        closed: (_) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CC.line),
            gradient: const RadialGradient(
              center: Alignment(0, -0.35),
              radius: 0.95,
              colors: [Color(0xFF1B2D45), CC.surface],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Center(
                child: Image.asset(Repository.instance.thumbFor(component.id), fit: BoxFit.contain),
              ),
            ),
            Text(component.nameAr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(
                child: Text(component.nameEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: CC.muted)),
              ),
              if (action == AutoAction.video) const CcIcon(CcIcons.film, size: 16, color: CC.amber),
              if (action == AutoAction.sheet) const CcIcon(CcIcons.sheet, size: 16, color: CC.amber),
              if (action == AutoAction.none && total > 0 && seen >= total) const Icon(Icons.check_circle_rounded, size: 16, color: CC.green),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Horizontal swipe row of component cards with a section title.
class ComponentRow extends StatelessWidget {
  final String title;
  final List<Component> items;
  final AutoAction action;
  final double cardWidth;
  final VoidCallback? onChanged;
  const ComponentRow({super.key, required this.title, required this.items, this.action = AutoAction.none, this.cardWidth = 168, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final h = cardWidth * 1.22;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: CC.amber, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('${items.length}', style: const TextStyle(fontSize: 12, color: CC.muted, fontFamily: CC.mono)),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) => ComponentCard(component: items[i], width: cardWidth, action: action, onClosed: onChanged),
        ),
      ),
    ]);
  }
}

double carouselFraction(double width) => width >= 1200 ? 0.30 : (width >= 900 ? 0.4 : (width >= 600 ? 0.55 : 0.8));
double carouselHeight(double width) => math.min(460, math.max(330, width * (width >= 900 ? 0.32 : 1.0)));
