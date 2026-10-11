import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';
import 'launcher_def.dart';

class LauncherRegistry {
  LauncherRegistry._();

  static final LauncherRegistry instance = LauncherRegistry._();

  final _launchers = <LauncherDef>[];

  List<LauncherDef> forOpen(String extension) => [
    for (final l in _launchers)
      if (l.context == LauncherContext.open && l.matchesExtension(extension)) l,
  ];

  LauncherDef? defaultForOpen(String extension) {
    for (final l in forOpen(extension)) {
      if (l.isDefault) return l;
    }

    return null;
  }

  List<LauncherDef> forCompare(String extension) => [
    for (final l in _launchers)
      if (l.context == LauncherContext.compare && l.matchesExtension(extension))
        l,
  ];

  LauncherDef? defaultForCompare(String extension) {
    final matches = forCompare(extension);
    for (final l in matches) {
      if (l.isDefault) return l;
    }

    return matches.isEmpty ? null : matches.first;
  }

  LauncherDef? byId(String id) {
    for (final l in _launchers) {
      if (l.id == id) return l;
    }

    return null;
  }

  Future<void> load() async {
    _launchers.clear();
    final dir = Directory(await AppDirs.launchers());
    try {
      if (!await dir.exists()) return;
      final files = <File>[
        await for (final entity in dir.list())
          if (entity is File &&
              p.extension(entity.path).toLowerCase() == '.json')
            entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        await _loadFile(file);
      }
    } catch (error, stack) {
      log.warn(
        'launchers',
        'failed to load launchers',
        error: error,
        stack: stack,
      );
    }
  }

  Future<void> _loadFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('launcher file must contain a JSON object');
      }
      final def = LauncherDef.fromJson(decoded);
      if (byId(def.id) != null) {
        log.warn('launchers', 'duplicate launcher id "${def.id}" skipped');

        return;
      }
      _launchers.add(def);
    } catch (error, stack) {
      log.warn(
        'launchers',
        'skipping invalid launcher file ${file.path}',
        error: error,
        stack: stack,
      );
    }
  }
}
