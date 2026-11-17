import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';
import 'package:waydir/features/quick_look/generators/generator_runner.dart';
import 'package:waydir/utils/cancel_token.dart';

Map<String, dynamic> _slowGenerator() => Platform.isWindows
    ? {
        'cmd': 'powershell',
        'args': [
          '-NoProfile',
          '-Command',
          'Start-Sleep -Seconds 30; Set-Content -Path "%OUTPUT%" -Value x',
        ],
      }
    : {
        'cmd': 'sh',
        'args': ['-c', 'sleep 30; echo x > "%OUTPUT%"'],
      };

void main() {
  late Directory tmp;
  late Future<String> Function() savedCache;
  late FileEntry entry;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('generator_cancel_test');
    savedCache = GeneratorRunner.cacheDirectory;
    GeneratorRunner.cacheDirectory = () async => tmp.path;
    final input = File(p.join(tmp.path, 'input.slow'))..writeAsStringSync('x');
    entry = FileEntry.fromFileSystemEntity(input);
    GeneratorRegistry.instance.registerForTesting(
      GeneratorDef.fromJson({
        'id': 'slow',
        'extensions': ['slow'],
        'timeoutSeconds': 60,
        ..._slowGenerator(),
      }),
    );
  });

  tearDown(() async {
    GeneratorRunner.cacheDirectory = savedCache;
    GeneratorRegistry.instance.clearForTesting();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('cancelling the only waiter stops a running generator', () async {
    final cancel = CancelToken();
    final watch = Stopwatch()..start();
    final pending = GeneratorRunner.preview(entry, cancel: cancel);
    await Future<void>.delayed(const Duration(seconds: 2));
    cancel.cancel();

    expect(await pending, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
  });

  test('a cancelled run is not remembered as a failure', () async {
    final first = CancelToken();
    final pending = GeneratorRunner.preview(entry, cancel: first);
    await Future<void>.delayed(const Duration(seconds: 1));
    first.cancel();
    await pending;

    final second = CancelToken();
    var finished = false;
    final retry = GeneratorRunner.preview(
      entry,
      cancel: second,
    ).whenComplete(() => finished = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(finished, isFalse);
    second.cancel();
    await retry;
  });
}
