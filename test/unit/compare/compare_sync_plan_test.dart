import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/compare/compare_diff.dart';
import 'package:waydir/features/compare/compare_sync_plan.dart';

void main() {
  FileEntry entry(
    String path, {
    int size = 1,
    int ms = 10000,
    FileItemType type = FileItemType.file,
  }) {
    return FileEntry.raw(
      name: path.split('/').last,
      path: path,
      type: type,
      size: size,
      modifiedMs: ms,
    );
  }

  CompareDiffResult diff() => buildCompareDiff(
    leftRoot: '/left',
    rightRoot: '/right',
    leftEntries: [
      entry('/left/new.txt', size: 3),
      entry('/left/newer.txt', size: 5, ms: 20000),
      entry('/left/older.txt', ms: 10000),
      entry('/left/differ.txt', size: 2, ms: 30000),
      entry('/left/same.txt', size: 7, ms: 30000),
      entry('/left/dir', type: FileItemType.folder),
      entry('/left/dir/inner.txt', size: 11),
    ],
    rightEntries: [
      entry('/right/newer.txt', size: 4, ms: 10000),
      entry('/right/older.txt', ms: 20000),
      entry('/right/differ.txt', size: 9, ms: 30000),
      entry('/right/same.txt', size: 7, ms: 30000),
    ],
  );

  test('summarises what a sync will add, overwrite and skip', () {
    final plan = buildCompareSyncPlan(
      sourceRoot: '/left',
      destinationRoot: '/right',
      sourceResults: diff().left.values,
    );

    expect(plan.added.map((r) => r.relativePath), [
      'dir',
      'dir/inner.txt',
      'new.txt',
    ]);
    expect(plan.addedFiles, 2);
    expect(plan.addedFolders, 1);
    expect(plan.addedBytes, 14);
    expect(plan.updated.map((r) => r.relativePath), ['newer.txt']);
    expect(plan.differing.map((r) => r.relativePath), ['differ.txt']);
    expect(plan.skipped.map((r) => r.relativePath), ['older.txt']);
    expect(plan.totalBytes, 21);
    expect(plan.overwrites, {'/left/newer.txt', '/left/differ.txt'});
    expect(plan.groups.keys, ['/right']);
    expect(plan.groups['/right'], [
      '/left/differ.txt',
      '/left/dir',
      '/left/new.txt',
      '/left/newer.txt',
    ]);
  });

  test('limits the plan to the selected scope', () {
    final plan = buildCompareSyncPlan(
      sourceRoot: '/left',
      destinationRoot: '/right',
      sourceResults: diff().left.values,
      scope: {'dir/inner.txt', 'older.txt'},
    );

    expect(plan.added.map((r) => r.relativePath), ['dir/inner.txt']);
    expect(plan.updated, isEmpty);
    expect(plan.skipped.map((r) => r.relativePath), ['older.txt']);
    expect(plan.overwrites, isEmpty);
    expect(plan.groups.keys, [p.join('/right', 'dir')]);
  });

  test('is empty when nothing needs copying', () {
    final plan = buildCompareSyncPlan(
      sourceRoot: '/right',
      destinationRoot: '/left',
      sourceResults: diff().right.values.where(
        (r) =>
            r.status != CompareStatus.newer && r.status != CompareStatus.differ,
      ),
    );

    expect(plan.isEmpty, isTrue);
  });
}
