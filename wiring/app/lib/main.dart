import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_info.dart';
import 'services/progress.dart';
import 'services/sound.dart';
import 'services/sprites.dart';
import 'theme.dart';
import 'data/circuits.dart';
import 'ui/lab/lab_page.dart';
import 'ui/lab/painters.dart';
import 'ui/calc_page.dart';
import 'ui/circuits_page.dart';
import 'ui/learn_page.dart';
import 'ui/more_page.dart';
import 'ui/projects_page.dart';
import 'ui/quiz_page.dart';
import 'ui/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Progress.i.load();
  Sound.enabled = Progress.i.sound;
  await Sound.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  Sprites.i.load();
  runApp(const WiringApp());
}

class WiringApp extends StatelessWidget {
  const WiringApp();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Progress.i,
        builder: (context, _) => MaterialApp(
          title: AppInfo.nameAr,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          builder: (context, child) {
            // teacher mode on the big board: everything 25% larger
            final mq = MediaQuery.of(context);
            final scale = Progress.i.bigUi ? 1.25 : 1.0;
            return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child!);
          },
          home: _deepLink() ?? const SplashPage(),
        ),
      );
}

/// Web preview only: `?c=c08&m=guide&skin=schematic` opens a lab page directly (used for screenshots).
Widget? _deepLink() {
  final q = Uri.base.queryParameters;
  final c = circuitById(q['c'] ?? '');
  switch (q['p']) {
    case 'circuits':
      return const Scaffold(body: CircuitsPage());
    case 'circuit':
      return CircuitPage(c ?? circuits.first);
    case 'learn':
      return Scaffold(body: LearnPage(), backgroundColor: C.navy0);
    case 'calc':
      return const CalcPage();
    case 'load':
      return const PageFrame(title: 'حساب الأحمال', body: LoadCalc());
    case 'projects':
      return const ProjectsPage();
    case 'apt':
      return const ApartmentPage();
    case 'quiz':
      return const QuizHome();
    case 'more':
      return const Scaffold(body: MorePage());
    case 'cert':
      return const QuizResult(title: 'الاختبار الشامل', score: 18, total: 20);
  }
  if (!q.containsKey('m')) return null;
  final mode = LabMode.values.where((m) => m.name == q['m']).firstOrNull ?? LabMode.free;
  return LabPage(circuit: c, mode: mode, skin: q['skin'] == 'schematic' ? Skin.schematic : Skin.board);
}
