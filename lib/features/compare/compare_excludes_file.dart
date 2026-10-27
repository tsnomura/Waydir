import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/archive/archive_path.dart';
import '../../core/platform/platform_paths.dart';
import 'compare_excludes.dart';

class CompareExcludesFile {
  static bool isCapable(String root) =>
      !PlatformPaths.isRemoteUri(root) && ArchivePath.resolve(root) == null;

  static String markerPath(String root) =>
      p.join(root, CompareExcludes.markerFileName);

  static Future<String?> read(String root) async {
    if (!isCapable(root)) return null;
    try {
      final file = File(markerPath(root));
      if (!await file.exists()) return null;
      return CompareExcludes.splitPatterns(
        await file.readAsString(),
      ).join(', ');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> write(String root, String value) async {
    if (!isCapable(root)) return false;
    try {
      final patterns = CompareExcludes.splitPatterns(value);
      final content = patterns.isEmpty ? '' : '${patterns.join('\n')}\n';
      await File(markerPath(root)).writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }
}
