// Web preview entry used by CI to screenshot the Panel Lab (not shipped in the apps).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'lab/lab_page.dart';
import 'schem/schem_page.dart';
import 'ui/theme.dart';

void main() {
  final q = Uri.base.queryParameters;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: CC.theme(),
    locale: const Locale('ar', 'EG'),
    supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: q['page'] == 'schem' ? SchemPage(demo: int.tryParse(q['demo'] ?? '') ?? 0) : LabPage(demo: int.tryParse(q['demo'] ?? '') ?? 0),
  ));
}
