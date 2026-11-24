import 'package:flutter/material.dart';

import 'about_page.dart';
import 'diagrams_page.dart';
import 'home_page.dart';
import 'icons.dart';
import 'library_page.dart';
import 'theme.dart';

/// Adaptive frame: bottom bar on phones, side rail on wide screens (Windows,
/// tablets, phone landscape).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _Dest {
  final String label;
  final String icon;
  const _Dest(this.label, this.icon);
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _dests = [
    _Dest('الرئيسية', CcIcons.home),
    _Dest('المكتبة', CcIcons.library),
    _Dest('المخططات', CcIcons.diagram),
    _Dest('عن التطبيق', CcIcons.info),
  ];

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onGo: go),
      const LibraryPage(),
      const DiagramsPage(),
      const AboutPage(),
    ];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 720;
      final body = IndexedStack(index: _index, children: pages);
      if (wide) {
        return Scaffold(
          body: Row(children: [
            _Rail(index: _index, onTap: go),
            const VerticalDivider(width: 1, color: CC.line),
            Expanded(child: body),
          ]),
        );
      }
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: _BottomBar(index: _index, onTap: go),
      );
    });
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: CC.nav, border: Border(top: BorderSide(color: Color(0xFF1F2830)))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(children: [
            for (var i = 0; i < _ShellState._dests.length; i++)
              Expanded(child: _NavItem(dest: _ShellState._dests[i], selected: i == index, onTap: () => onTap(i))),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? CC.amber : CC.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: dest.label,
      child: InkWell(
        onTap: onTap,
        child: Stack(alignment: Alignment.center, children: [
          if (selected)
            Positioned(
              top: 0,
              child: Container(
                width: 28,
                height: 3,
                decoration: const BoxDecoration(
                  color: CC.amber,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                ),
              ),
            ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            CcIcon(dest.icon, color: color),
            const SizedBox(height: 4),
            Text(dest.label,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _Rail({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      color: CC.nav,
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo_small.webp', width: 52, height: 52)),
          const SizedBox(height: 18),
          for (var i = 0; i < _ShellState._dests.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
              child: Material(
                color: i == index ? CC.amberBg : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onTap(i),
                  child: SizedBox(
                    height: 62,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      CcIcon(_ShellState._dests[i].icon, color: i == index ? CC.amber : CC.muted),
                      const SizedBox(height: 4),
                      Text(_ShellState._dests[i].label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: i == index ? CC.amber : CC.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
