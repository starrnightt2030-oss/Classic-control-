import 'package:classic_control/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> rel(String tag, List<String> assets, {bool draft = false}) => {
      'tag_name': tag,
      'draft': draft,
      'assets': [for (final a in assets) {'name': a, 'browser_download_url': 'https://example/$tag/$a'}],
    };

void main() {
  test('the newest build that carries update.json wins', () {
    final got = UpdateService.pickLatest([
      rel('v2-app-build-41', ['ClassicControl-Android.apk']), // before the updater: skipped
      rel('v2-app-build-44', ['update.json']),
      rel('v2-app-build-46', ['update.json'], draft: true),
      rel('v1-build-99', ['update.json']),
      rel('v2-app-build-45', ['update.json', 'ClassicControl-Android.apk']),
    ]);
    expect(got?.$1, 'v2-app-build-45');
    expect(got?.$2, 45);
    expect(got?.$3, 'https://example/v2-app-build-45/update.json');
    expect(UpdateService.pickLatest([rel('v2-app-build-41', ['x.apk'])]), isNull);
  });

  final info = UpdateInfo.fromJson({
    'build': 45,
    'version': '2.4.0',
    'sha': 'abc123',
    'repo': 'o/r',
    'notes': 'machines',
    'android': {'name': 'ClassicControl-Android.apk', 'size': 60000000, 'sha': 'a1'},
    'windows': {
      'name': 'ClassicControl-Windows.zip',
      'size': 40000000,
      'sha': 'w1',
      'patch': {'name': 'ClassicControl-Windows-patch.zip', 'size': 9000000, 'sha': 'p1', 'from': 44, 'files': 6},
    },
    'files': {
      'assets/content/contactor.json': {'sha': 's1', 'size': 1000, 'src': 'v2/content/contactor.json'},
      'assets/audio/contactor/intro.mp3': {'sha': 's2', 'size': 50000, 'src': 'v2/assets/audio/contactor/intro.mp3'},
      'assets/models/contactor.glb': {'sha': 's3', 'size': 900000, 'src': 'v2/assets/models/contactor.glb'},
    },
  }, tag: 'v2-app-build-45');

  test('update.json is read whole', () {
    expect(info.build, 45);
    expect(info.android!.size, 60000000);
    expect(info.windowsPatch!.name, 'ClassicControl-Windows-patch.zip');
    expect(info.patchFrom, 44);
    expect(info.asset('ClassicControl-Android.apk').toString(), 'https://github.com/o/r/releases/download/v2-app-build-45/ClassicControl-Android.apk');
    expect(info.raw('v2/content/contactor.json').toString(), 'https://raw.githubusercontent.com/o/r/abc123/v2/content/contactor.json');
  });

  test('Windows downloads only the changed files when coming from the previous build', () {
    expect(info.windowsFor(44)!.name, 'ClassicControl-Windows-patch.zip');
    expect(info.windowsFor(43)!.name, 'ClassicControl-Windows.zip');
    expect(info.windowsFor(0)!.name, 'ClassicControl-Windows.zip');
  });

  test('content packs fetch only what differs', () {
    final have = {'assets/content/contactor.json': 's1', 'assets/models/contactor.glb': 'old'};
    final todo = info.changedFiles(have);
    expect(todo.toSet(), {'assets/audio/contactor/intro.mp3', 'assets/models/contactor.glb'});
    expect(info.sizeOf(todo), 950000);
    expect(info.changedFiles({'assets/content/contactor.json': 's1', 'assets/audio/contactor/intro.mp3': 's2', 'assets/models/contactor.glb': 's3'}), isEmpty);
  });

  test('the Windows updater script waits, unpacks over the folder and reopens', () {
    final s = UpdateService.windowsScript();
    expect(s, contains('Wait-Process -Id \$ProcId'));
    expect(s, contains('Expand-Archive -LiteralPath \$Zip -DestinationPath \$Dest -Force'));
    expect(s, contains('Start-Process -FilePath \$Exe'));
  });
}
