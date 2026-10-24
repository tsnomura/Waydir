import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../launchers/launcher_runner.dart';

/// Opens the in-app tutorial in a standalone `--app-tutorial` window (a
/// separate Waydir process), for the Help dialog's pop-out action.
class AppTutorialPopOut {
  AppTutorialPopOut._();

  static Future<bool> open() async {
    try {
      await Process.start(LauncherRunner.waydirExecutable, [
        '--app-tutorial',
      ], mode: ProcessStartMode.detached);

      return true;
    } catch (error, stack) {
      log.warn(
        'help',
        'failed to open the tutorial in a separate window',
        error: error,
        stack: stack,
      );

      return false;
    }
  }
}
