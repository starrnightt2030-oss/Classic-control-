import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_info.dart';
import '../services/asset_server.dart';
import '../services/audio_service.dart';
import 'shell.dart';
import 'theme.dart';

/// Animated intro: Blender-rendered clip (cables → terminals → sparks → energised)
/// with the logo reveal, version and developer, and its soundtrack.
class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  bool _left = false;
  Timer? _safety;

  @override
  void initState() {
    super.initState();
    _safety = Timer(const Duration(seconds: 13), _finish);
  }

  @override
  void dispose() {
    _safety?.cancel();
    super.dispose();
  }

  void _finish() {
    if (_left || !mounted) return;
    _left = true;
    AudioService.instance.stopIntro();
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, __, ___) => const Shell(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final q = Uri(queryParameters: {
      'ar': AppInfo.brandAr,
      'en': AppInfo.product.toUpperCase(),
      'dev': AppInfo.developer,
      'ver': 'الإصدار ${AppInfo.version} · ${AppInfo.build}',
    }).query;
    final url = '${AssetServer.instance.origin}/assets/web/intro.html?$q';
    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: Stack(children: [
        Positioned.fill(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              transparentBackground: false,
              supportZoom: false,
              disableContextMenu: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
              useHybridComposition: true,
              isInspectable: kDebugMode,
            ),
            onWebViewCreated: (c) {
              c.addJavaScriptHandler(handlerName: 'started', callback: (args) {
                AudioService.instance.playIntro();
                return null;
              });
              c.addJavaScriptHandler(handlerName: 'ended', callback: (args) {
                _finish();
                return null;
              });
            },
          ),
        ),
        PositionedDirectional(
          top: MediaQuery.paddingOf(context).top + 10,
          end: 14,
          child: TextButton(
            onPressed: _finish,
            style: TextButton.styleFrom(
              foregroundColor: CC.text2,
              backgroundColor: const Color(0x66000000),
              minimumSize: const Size(64, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('تخطي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
