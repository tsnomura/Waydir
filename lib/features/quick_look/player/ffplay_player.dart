import 'dart:async';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../generators/generator_runner.dart';
import 'player_registry.dart';
import 'quick_look_player.dart';

/// Runs the user-configured player command (`player.json`, typically
/// `ffplay`) to actually produce sound. Stays a no-op throughout when no
/// player is configured.
///
/// No shell is involved (same as every other external command Quick Look
/// runs), so there's no wrapping shell process to leave behind — killing the
/// spawned process directly is enough, on every platform.
class FfplayPlayer implements QuickLookPlayer {
  Process? _process;

  @override
  Future<void> play(String path, double startSeconds) async {
    await stop();
    final config = PlayerRegistry.instance.config;
    if (config == null) return;
    final start = GeneratorRunner.formatSeek(startSeconds);
    final args = config.args
        .map(
          (arg) => arg.replaceAll('%INPUT%', path).replaceAll('%START%', start),
        )
        .toList();
    try {
      _process = await Process.start(config.cmd, args);
      // Drained, not read: nothing downstream needs ffplay's own
      // stdout/stderr, but an unread pipe fills up and blocks the child
      // process forever once the OS buffer is full.
      unawaited(_process!.stdout.drain<void>());
      unawaited(_process!.stderr.drain<void>());
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'player command "${config.cmd}" failed to start for $path',
        error: error,
        stack: stack,
      );
      _process = null;
    }
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
  }
}
