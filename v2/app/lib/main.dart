import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/repository.dart';
import 'services/asset_server.dart';
import 'services/update_service.dart';
import 'app_info.dart';
import 'ui/intro_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AssetServer.instance.start();
  await Repository.instance.load();
  // look for a new build while the intro plays, so its screen is ready right after
  UpdateService.instance.start();
  runApp(const ClassicControlApp());
}

class ClassicControlApp extends StatelessWidget {
  const ClassicControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.brandEn,
      debugShowCheckedModeBanner: false,
      theme: CC.theme(),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const IntroPage(),
    );
  }
}
