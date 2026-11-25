import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/repository.dart';
import '../services/update_service.dart';
import 'theme.dart';

String mb(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} ميجا' : '${(bytes / 1024).ceil()} كيلو';

/// Watches for new builds while the app is open: offers the app update once per
/// build (again a day later if the user chose «بعدين»), and says when new
/// lessons or recordings arrived.
class UpdateWatcher extends StatefulWidget {
  final Widget child;
  const UpdateWatcher({super.key, required this.child});
  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> {
  final _svc = UpdateService.instance;
  int _offered = 0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _svc.status.addListener(_onStatus);
    _svc.contentArrived.addListener(_onContent);
    // after the first frame, so the intro and the home page come first
    WidgetsBinding.instance.addPostFrameCallback((_) => _svc.start());
  }

  @override
  void dispose() {
    _svc.status.removeListener(_onStatus);
    _svc.contentArrived.removeListener(_onContent);
    super.dispose();
  }

  Future<void> _onStatus() async {
    final s = _svc.status.value;
    final i = s.info;
    if (s.phase != UpdatePhase.available || i == null || _open || _offered == i.build) return;
    _offered = i.build;
    if (await _svc.snoozed(i.build) || !mounted) return;
    _open = true;
    await showUpdateDialog(context, i);
    _open = false;
  }

  Future<void> _onContent() async {
    await Repository.instance.reloadContent();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('وصل محتوى جديد (${_svc.contentArrived.value} ملف): دروس أو تسجيلات أو مجسمات. هيظهر لما تفتح الصفحة تاني.'),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  final svc = UpdateService.instance;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ValueListenableBuilder<UpdateStatus>(
      valueListenable: svc.status,
      builder: (ctx, s, _) {
        final busy = s.phase == UpdatePhase.downloading || s.phase == UpdatePhase.installing;
        final size = svc.downloadSize(info);
        final android = Theme.of(ctx).platform == TargetPlatform.android;
        return AlertDialog(
          title: const Text('نسخة جديدة متاحة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('النسخة ${info.build}${info.version.isEmpty ? '' : ' (${info.version})'} · إنت على النسخة ${AppInfo.buildNumber}', style: const TextStyle(color: CC.text2)),
              if (info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('الجديد', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(info.notes.trim(), style: const TextStyle(height: 1.5)),
              ],
              const SizedBox(height: 10),
              Text(
                svc.isPatch(info)
                    ? 'هينزل ${mb(size)} بس: الملفات اللي اتغيرت من نسختك.'
                    : 'حجم التحميل ${mb(size)}.',
                style: const TextStyle(color: CC.muted),
              ),
              Text(
                android
                    ? 'أندرويد بيحتاج النسخة كاملة، وبعد التحميل هيفتح شاشة التثبيت وتدوس «تثبيت». بياناتك ومشاريعك مش هتتمسح.'
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
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      unawaited(svc.snooze(info.build));
                      Navigator.pop(ctx);
                    },
              child: const Text('بعدين'),
            ),
            FilledButton(
              onPressed: busy ? null : () => svc.install(info),
              child: Text(s.phase == UpdatePhase.failed ? 'جرّب تاني' : 'حدّث دلوقتي'),
            ),
          ],
        );
      },
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
          UpdatePhase.downloading => 'بينزل… ${(s.progress * 100).round()}%',
          UpdatePhase.installing => 'بيجهّز التثبيت…',
          UpdatePhase.failed => s.message ?? 'ما قدرش يوصل للتحديثات.',
          UpdatePhase.idle => svc.supported ? 'التطبيق بيدوّر لوحده كل ساعة وهو مفتوح.' : 'التحديث التلقائي على أندرويد وويندوز بس.',
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
