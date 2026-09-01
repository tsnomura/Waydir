import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/app_dirs.dart';
import 'generator_def.dart';

/// Loads user-defined preview generators from `.json` files in the
/// generators support directory. Each generator maps a set of extensions to
/// an external command that renders a preview image for them.
///
/// These configs run arbitrary commands with the user's full privileges, the
/// same trust model as Waydir's Lua plugins: only extensions with a generator
/// you wrote or trust should be added here.
class GeneratorRegistry {
  GeneratorRegistry._();

  static final GeneratorRegistry instance = GeneratorRegistry._();

  final _byExtension = <String, GeneratorDef>{};

  GeneratorDef? forExtension(String extension) =>
      _byExtension[extension.toLowerCase()];

  Future<void> load() async {
    _byExtension.clear();
    final dirPath = await AppDirs.generators();
    final dir = Directory(dirPath);
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File ||
            p.extension(entity.path).toLowerCase() != '.json') {
          continue;
        }
        await _loadFile(entity);
      }
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'failed to load preview generators',
        error: error,
        stack: stack,
      );
    }
  }

  Future<void> _loadFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'generator file must contain a JSON object',
        );
      }
      final def = GeneratorDef.fromJson(decoded);
      for (final ext in def.extensions) {
        final existing = _byExtension[ext];
        if (existing != null) {
          log.warn(
            'quick-look',
            'generator "${def.id}" skipped for .$ext: already handled by '
                '"${existing.id}"',
          );
          continue;
        }
        _byExtension[ext] = def;
      }
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'skipping invalid generator file ${file.path}',
        error: error,
        stack: stack,
      );
    }
  }
}
