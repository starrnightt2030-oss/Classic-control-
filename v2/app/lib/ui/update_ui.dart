import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/repository.dart';
import '../services/update_service.dart';
import 'theme.dart';

String mb(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} ميجا' : '${(bytes / 1024).ceil()} كيلو';

/// Shows what the updater found, as soon as the home screen is up:
/// * a new program: a screen that cannot be dismissed until it is installed;
/// * new content (lessons, recordings, 3D models): a progress screen while only the
///   changed files download, then the app goes on with them.
class UpdateWatcher extends StatefulWidget {
  final Widget child;
  const UpdateWatcher({super.key, required this.child});
  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> {
  final _svc = UpdateService.instance;
  bool _open = false, _syncOpen = false;

  @override
  void initState() {
    super.initState();
    _svc.status.addListener(_onStatus);
    _svc.contentArrived.addListener(_onContent);
    // started in main(); this also covers a check that finished during the intro
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _svc.start();
      _onStatus();
    });
  }

  @override
  void dispose() {
    _svc.status.removeListener(_onStatus);
    _svc.contentArrived.removeListener(_onContent);
    super.dispose();
  }

  Future<void> _onStatus() async {
    if (!mounted) return;
    final s = _svc.status.value;
    final i = s.info;
    if (s.phase == UpdatePhase.syncing && !_syncOpen && !_open) {
      _syncOpen = true;
      await showContentSyncDialog(context);
      _syncOpen = false;
      return;
    }
    if (s.phase != UpdatePhase.available || i == null || _open) return;
    _open = true;
    await showUpdateDialog(context, i);
    _open = false;
  }

  Future<void> _onContent() async {
    await Repository.instance.reloadContent();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('اتحدّث المحتوى (${_svc.contentArrived.value} ملف): دروس أو تسجيلات أو مجسمات.'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// new lessons, recordings or models downloading: the app waits for them
Future<void> showContentSyncDialog(BuildContext context) {
  final svc = UpdateService.instance;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<UpdateStatus>(
        valueListenable: svc.status,
        builder: (ctx, s, _) {
          if (s.phase != UpdatePhase.syncing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.of(ctx).pop();
            });
          }
          final i = s.info;
          final parts = (s.message ?? '').split('|');
          final files = int.tryParse(parts.first) ?? 0;
          final bytes = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          return AlertDialog(
            title: const Text('بيحدّث المحتوى'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'بينزّل الملفات اللي اتغيرت بس من النسخة ${i?.build ?? ''}${files > 0 ? ': $files ملف، ${mb(bytes)}' : ''}.',
                style: const TextStyle(color: CC.text2, height: 1.5),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: s.progress > 0 ? s.progress : null),
              const SizedBox(height: 6),
              Text('${(s.progress * 100).round()}%', style: const TextStyle(color: CC.muted)),
            ]),
          );
        },
      ),
    ),
  );
}

/// a new program: the app cannot be used until it is installed
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  final svc = UpdateService.instance;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<UpdateStatus>(
        valueListenable: svc.status,
        builder: (ctx, s, _) {
          final info0 = s.info ?? info;
          final busy = s.phase == UpdatePhase.downloading || s.phase == UpdatePhase.installing;
          final size = svc.downloadSize(info0);
          final android = Theme.of(ctx).platform == TargetPlatform.android;
          return AlertDialog(
            title: const Text('تحديث مطلوب'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('النسخة ${info0.build}${info0.version.isEmpty ? '' : ' (${info0.version})'} · إنت على النسخة ${AppInfo.buildNumber}', style: const TextStyle(color: CC.text2)),
                const SizedBox(height: 6),
                const Text('لازم تحدّث عشان تكمّل.', style: TextStyle(fontWeight: FontWeight.w700)),
                if (info0.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('الجديد', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(info0.notes.trim(), style: const TextStyle(height: 1.5)),
                ],
                const SizedBox(height: 10),
                Text(
                  svc.isPatch(info0) ? 'هينزل ${mb(size)} بس: الملفات اللي اتغيرت من نسختك.' : 'حجم التحميل ${mb(size)}.',
                  style: const TextStyle(color: CC.muted),
                ),
                Text(
                  android
                      ? 'البرنامج نفسه اتغير، وأندرويد ما بيسمحش بتحديث جزء من تطبيق متثبت من برّه المتجر، فلازم النسخة كاملة. بعد التحميل هتفتح شاشة التثبيت وتدوس «تثبيت». بياناتك ومشاريعك مش هتتمسح.'
                      : 'البرنامج هيتقفل ويركّب الملفات الجديدة ويفتح تاني لوحده. مشاريعك مش هتتمسح.',
                  style: const TextStyle(color: CC.muted, height: 1.5),
                ),
                if (busy) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: s.phase == UpdatePhase.installing ? null : s.progress),
                  const SizedBox(height: 6),
                  Text(s.phase == UpdatePhase.installing ? 'بيجهّز التثبيت…' : 'بينزل… ${(s.progress * 100).round()}%', style: const TextStyle(color: CC.muted)),
                ],
                if (s.message != null && !busy) ...[
                  const SizedBox(height: 10),
                  Text(s.message!, style: TextStyle(color: s.phase == UpdatePhase.failed ? CC.red : CC.green)),
                ],
              ]),
            ),
            actions: [
              FilledButton(
                onPressed: busy ? null : () => svc.install(info0),
                child: Text(s.phase == UpdatePhase.failed ? 'جرّب تاني' : 'حدّث دلوقتي'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// «التحديثات» in the about page: this build, and a button to look now
class UpdateTile extends StatelessWidget {
  const UpdateTile({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = UpdateService.instance;
    return ValueListenableBuilder<UpdateStatus>(
      valueListenable: svc.status,
      builder: (context, s, _) {
        final i = s.info;
        final sub = switch (s.phase) {
          UpdatePhase.checking => 'بيدوّر…',
          UpdatePhase.upToDate => 'عندك آخر نسخة${i != null ? ' (${i.build})' : ''}.',
          UpdatePhase.available => 'فيه نسخة جديدة (${i?.build}).',
          UpdatePhase.syncing => 'بيحدّث المحتوى… ${(s.progress * 100).round()}%',
          UpdatePhase.downloading => 'بينزل… ${(s.progress * 100).round()}%',
          UpdatePhase.installing => 'بيجهّز التثبيت…',
          UpdatePhase.failed => s.message ?? 'ما قدرش يوصل للتحديثات.',
          UpdatePhase.idle => svc.supported ? 'التطبيق بيدوّر لوحده كل ما تفتحه، وكل ساعة وهو مفتوح.' : 'التحديث التلقائي على أندرويد وويندوز بس.',
        };
        return ListTile(
          leading: const Icon(Icons.system_update_alt_rounded, color: CC.accentSoft),
          title: Text('التحديثات · النسخة ${AppInfo.buildNumber == 0 ? 'تجريبية محلية' : AppInfo.buildNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: const TextStyle(color: CC.muted, fontSize: 12.5)),
          trailing: !svc.supported
              ? null
              : s.phase == UpdatePhase.available && i != null
                  ? FilledButton(onPressed: () => showUpdateDialog(context, i), child: const Text('حدّث'))
                  : TextButton(onPressed: s.phase == UpdatePhase.checking ? null : () => svc.check(manual: true), child: const Text('دوّر دلوقتي')),
        );
      },
    );
  }
}
