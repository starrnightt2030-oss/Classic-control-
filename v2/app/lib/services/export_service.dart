import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XTypeGroup, getSaveLocation;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

/// Hands an exported file to the user: a Save-As dialog on desktop, the share
/// sheet on Android (save to Files/Drive/Gallery or send on WhatsApp…).
class ExportService {
  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Returns where it went (desktop path) or 'shared'; null when cancelled.
  static Future<String?> deliverBytes(Uint8List bytes, String fileName, {String mime = 'application/octet-stream', String? text}) async {
    if (_desktop) {
      final path = await _askPath(fileName);
      if (path == null) return null;
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$fileName');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], text: text));
    return 'shared';
  }

  static Future<String?> deliverFile(File file, String fileName, {String mime = 'application/octet-stream', String? text}) async {
    if (_desktop) {
      final path = await _askPath(fileName);
      if (path == null) return null;
      await file.copy(path);
      return path;
    }
    final dir = await getTemporaryDirectory();
    final f = await file.copy('${dir.path}${Platform.pathSeparator}$fileName');
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], text: text));
    return 'shared';
  }

  static Future<String?> _askPath(String fileName) async {
    final ext = fileName.contains('.') ? fileName.split('.').last : '';
    final loc = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: ext.isEmpty ? const [] : [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
    );
    if (loc == null) return null;
    var p = loc.path;
    if (ext.isNotEmpty && !p.toLowerCase().endsWith('.$ext')) p = '$p.$ext';
    return p;
  }

  static String safeName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
}
