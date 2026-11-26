import 'package:flutter/material.dart';

import 'about_page.dart';
import '../schem/ready_page.dart';
import 'home_page.dart';
import 'icons.dart';
import 'library_page.dart';
import '../meters/meters_page.dart';
import 'theme.dart';
import 'update_ui.dart';

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
    _Dest('أجهزة القياس', CcIcons.meter),
    _Dest('عن التطبيق', CcIcons.info),
  ];

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onGo: go),
      const LibraryPage(),
      const ReadyDiagramsPage(),
      const MetersPage(),
      const AboutPage(),
    ];
    return UpdateWatcher(child: LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 720;
      final body = IndexedStack(index: _index, children: pages);
      if (wide) {
        return Scaffold(
          body: Row(children: [
            _Rail(index: _index, onTap: go),
            Expanded(child: body),
          ]),
        );
      }
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: _BottomBar(index: _index, onTap: go),
      );
    }));
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Glass(
        radius: 30,
        child: SizedBox(
          height: 70,
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
    return Semantics(
      selected: selected,
      button: true,
      label: dest.label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: selected ? 46 : 34,
            height: selected ? 46 : 34,
            margin: EdgeInsets.only(bottom: selected ? 0 : 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5AA0FF), Color(0xFF2563EB)]) : null,
              boxShadow: selected ? glow(CC.amber, 1.2) : null,
            ),
            child: Center(child: CcIcon(dest.icon, size: selected ? 22 : 22, color: selected ? Colors.white : CC.muted)),
          ),
          if (!selected) Text(dest.label, style: const TextStyle(fontSize: 11, color: CC.muted, fontWeight: FontWeight.w600)),
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
      width: 92,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)]),
        border: BorderDirectional(end: BorderSide(color: CC.glassBorder)),
      ),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/logo_small.webp', width: 52, height: 52)),
          const SizedBox(height: 18),
          for (var i = 0; i < _ShellState._dests.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
              child: Material(
                color: i == index ? const Color(0x333D8BFF) : Colors.transparent,
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
