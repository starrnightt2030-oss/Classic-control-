import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';
import 'circuits_page.dart';
import 'home_page.dart';
import 'lab/lab_page.dart';
import 'learn_page.dart';
import 'more_page.dart';

/// Bottom navigation on phones, a side rail on the big board / desktop.
class Shell extends StatefulWidget {
  const Shell();
  static _ShellState? of(BuildContext c) => c.findAncestorStateOfType<_ShellState>();
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  static const _items = [
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.electrical_services_rounded, 'الدوائر'),
    (Icons.science_rounded, 'المعمل'),
    (Icons.menu_book_rounded, 'التعلم'),
    (Icons.apps_rounded, 'المزيد'),
  ];

  void go(int i) {
    if (i == 2) {
      Sound.play(Sfx.tap);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LabPage()));
      return;
    }
    Sound.play(Sfx.tap, volume: .5);
    setState(() => tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [HomePage(onTab: go), const CircuitsPage(), const SizedBox(), const LearnPage(), const MorePage()];
    final body = IndexedStack(index: tab, children: pages);
    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          Container(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.navy2, C.navy0])),
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: tab,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              indicatorColor: C.gold.withValues(alpha: .25),
              selectedIconTheme: const IconThemeData(color: C.goldHi, size: 30),
              unselectedIconTheme: const IconThemeData(color: C.dim, size: 28),
              selectedLabelTextStyle: const TextStyle(fontFamily: 'Cairo', color: C.goldHi, fontWeight: FontWeight.w700),
              unselectedLabelTextStyle: const TextStyle(fontFamily: 'Cairo', color: C.dim),
              leading: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/logo.webp', width: 56))),
              destinations: [for (final it in _items) NavigationRailDestination(icon: Icon(it.$1), label: Text(it.$2))],
            ),
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.navy1, C.navy2]),
          border: Border(top: BorderSide(color: C.glow.withValues(alpha: .4))),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: tab,
          onDestinationSelected: go,
          height: 66,
          indicatorColor: C.gold.withValues(alpha: .25),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final it in _items)
              NavigationDestination(icon: Icon(it.$1, color: C.dim), selectedIcon: Icon(it.$1, color: C.goldHi), label: it.$2),
          ],
        ),
      ),
    );
  }
}
