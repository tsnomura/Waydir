import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/app_dirs.dart';
import 'player_config.dart';

/// Loads the user-configured Quick Look audio player from `player.json` in
/// Waydir's application support directory, the same place `compare_diff.json`
/// and preview generators live. Unlike the diff command, there is no sensible
/// universal default — playback stays off ([config] is null) until the user
/// opts in by adding this file. Same trust model as preview generators and
/// the diff command: this runs an arbitrary command with the user's full
/// privileges.
class PlayerRegistry {
  PlayerRegistry._();

  static final PlayerRegistry instance = PlayerRegistry._();

  PlayerConfig? _config;

  PlayerConfig? get config => _config;

  Future<void> load() async {
    _config = null;
    try {
      final dir = await AppDirs.support();
      final file = File(p.join(dir, 'player.json'));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('player.json must be a JSON object');
      }
      _config = PlayerConfig.fromJson(decoded);
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'failed to load player.json, audio playback stays off',
        error: error,
        stack: stack,
      );
      _config = null;
    }
  }
}
