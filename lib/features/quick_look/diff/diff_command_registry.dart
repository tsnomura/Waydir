import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/app_dirs.dart';
import 'diff_command_config.dart';

/// Loads the user-configurable compare-diff command from
/// `compare_diff.json` in Waydir's application support directory, the same
/// place custom themes and preview generators live. Falls back to
/// [DiffCommandConfig.fallback] (plain `diff -y`) when the file is missing
/// or invalid — same trust model as preview generators: this runs an
/// arbitrary command with the user's full privileges.
class DiffCommandRegistry {
  DiffCommandRegistry._();

  static final DiffCommandRegistry instance = DiffCommandRegistry._();

  DiffCommandConfig _config = DiffCommandConfig.fallback;

  DiffCommandConfig get config => _config;

  Future<void> load() async {
    _config = DiffCommandConfig.fallback;
    try {
      final dir = await AppDirs.support();
      final file = File(p.join(dir, 'compare_diff.json'));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('compare_diff.json must be a JSON object');
      }
      _config = DiffCommandConfig.fromJson(decoded);
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'failed to load compare_diff.json, using default "diff -y"',
        error: error,
        stack: stack,
      );
      _config = DiffCommandConfig.fallback;
    }
  }
}
