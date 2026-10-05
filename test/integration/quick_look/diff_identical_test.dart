@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/diff/diff_runner.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('waydir_ql_diff_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FileEntry write(String name, String content, DateTime modified) {
    final file = File(p.join(tmp.path, name))
      ..writeAsStringSync(content)
      ..setLastModifiedSync(modified);

    return FileEntry.fromFileSystemEntity(file);
  }

  test(
    'byte-identical pair resolves to identical without running diff',
    () async {
      final left = write('a.m', 'x = 1;\n', DateTime.utc(2020));
      final right = write('b.m', 'x = 1;\n', DateTime.utc(2021));

      final result = await DiffRunner.run(left, right);

      expect(result.identical, isTrue);
      expect(result.available, isFalse);
    },
  );

  test('same size but different content is not identical', () async {
    final left = write('a.m', 'x = 1;\n', DateTime.utc(2020));
    final right = write('b.m', 'x = 2;\n', DateTime.utc(2021));

    final result = await DiffRunner.run(left, right);

    expect(result.identical, isFalse);
  });
}
