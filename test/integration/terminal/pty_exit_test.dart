@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/fs/waydir_core_loader.dart';
import 'package:waydir/core/terminal/pty_session.dart';

void main() {
  test('PtySession reports exit once the shell process exits', () async {
    expect(WaydirCoreLoader.load(), isNotNull);
    expect(WaydirCoreLoader.supportsPty(), isTrue);

    final session = PtySession();
    final shell = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final started = session.start(cwd: Directory.systemTemp.path, shell: shell);
    expect(started, isTrue);

    try {
      final startDeadline = DateTime.now().add(const Duration(seconds: 3));
      while (!session.hasExited && DateTime.now().isBefore(startDeadline)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      session.writeInput('exit\r\n');

      final exitDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (!session.hasExited && DateTime.now().isBefore(exitDeadline)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(
        session.hasExited,
        isTrue,
        reason:
            'PtySession should detect the shell process exiting shortly '
            'after it does, instead of reporting it alive indefinitely',
      );
    } finally {
      session.dispose();
    }
  });
}
