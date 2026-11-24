import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/repository.dart';
import 'services/asset_server.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AssetServer.instance.start();
  await Repository.instance.load();
  runApp(const ClassicControlApp());
}

class ClassicControlApp extends StatelessWidget {
  const ClassicControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'معمل الكلاسيك كنترول',
      debugShowCheckedModeBanner: false,
      theme: CC.theme(),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Shell(),
    );
  }
}
