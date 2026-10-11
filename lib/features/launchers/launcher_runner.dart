import 'dart:io';

import 'package:path/path.dart' as p;

import 'launcher_def.dart';

class LauncherRunner {
  LauncherRunner._();

  static List<List<String>> commandLines(
    LauncherDef def, {
    List<String> files = const [],
    String? left,
    String? right,
  }) {
    List<String> substitute(String? file) {
      final out = <String>[];
      for (final arg in def.args) {
        if (arg == '%FILES%') {
          out.addAll(files);
          continue;
        }
        final dir = file != null
            ? p.dirname(file)
            : files.isNotEmpty
            ? p.dirname(files.first)
            : left != null
            ? p.dirname(left)
            : '';
        out.add(
          arg
              .replaceAll('%FILES%', files.join(' '))
              .replaceAll('%FILE%', file ?? (files.isEmpty ? '' : files.first))
              .replaceAll('%DIR%', dir)
              .replaceAll('%LEFT%', left ?? '')
              .replaceAll('%RIGHT%', right ?? ''),
        );
      }

      return out;
    }

    if (def.context == LauncherContext.compare || def.takesAllFiles) {
      return [substitute(null)];
    }

    return [for (final file in files) substitute(file)];
  }

  static Future<void> run(
    LauncherDef def, {
    List<String> files = const [],
    String? left,
    String? right,
  }) async {
    for (final args in commandLines(
      def,
      files: files,
      left: left,
      right: right,
    )) {
      await Process.start(def.cmd, args, mode: ProcessStartMode.detached);
    }
  }
}
