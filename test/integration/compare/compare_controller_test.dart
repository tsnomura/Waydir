@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';
import 'package:waydir/features/compare/compare_controller.dart';
import 'package:waydir/features/compare/compare_diff.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/panes/pane_store.dart';

void main() {
  group('CompareController recursive real-disk regression', () {
    late Directory tmpDir;
    late OperationStore ops;
    late PaneStore paneLeft;
    late PaneStore paneRight;
    late CompareController controller;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('waydir_compare_');
      final left = Directory(p.join(tmpDir.path, 'left'))..createSync();
      final right = Directory(p.join(tmpDir.path, 'right'))..createSync();
      Directory(p.join(left.path, 'nested')).createSync();
      Directory(p.join(right.path, 'nested')).createSync();

      // Same size but different content on both sides, and the right copies are made
      // (and explicitly stamped) noticeably newer than the left copies, at
      // both the top level and one level of nesting — this is exactly the
      // shape that the metadata-free native `waydir_enumerate` fast path
      // could never detect, since it reports size/mtime as 0 for every
      // entry regardless of depth.
      final older = DateTime.utc(2020);
      final newer = DateTime.utc(2020, 1, 2);

      File(p.join(left.path, 'top.txt'))
        ..writeAsStringSync('hello')
        ..setLastModifiedSync(older);
      File(p.join(right.path, 'top.txt'))
        ..writeAsStringSync('HELLO')
        ..setLastModifiedSync(newer);
      File(p.join(left.path, 'nested', 'deep.txt'))
        ..writeAsStringSync('world')
        ..setLastModifiedSync(older);
      File(p.join(right.path, 'nested', 'deep.txt'))
        ..writeAsStringSync('WORLD')
        ..setLastModifiedSync(newer);
      File(p.join(left.path, 'copy.txt'))
        ..writeAsStringSync('same')
        ..setLastModifiedSync(older);
      File(p.join(right.path, 'copy.txt'))
        ..writeAsStringSync('same')
        ..setLastModifiedSync(newer);

      ops = OperationStore();
      paneLeft = PaneStore(operationStore: ops, initialPath: left.path);
      paneRight = PaneStore(operationStore: ops, initialPath: right.path);
      controller = CompareController(
        panes: signal<List<PaneStore>>([paneLeft, paneRight]),
        isDual: signal(true),
        operationStore: ops,
      );
    });

    tearDown(() {
      controller.dispose();
      paneLeft.dispose();
      paneRight.dispose();
      ops.dispose();
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test(
      'detects newer/older for both top-level and nested files when recursive',
      () async {
        expect(controller.recursive.value, isTrue);
        expect(controller.canStart, isTrue);

        await controller.start();

        final NavigationStore leftStore = paneLeft.tabs.activeTab.value.store;
        final NavigationStore rightStore = paneRight.tabs.activeTab.value.store;

        final leftTop = p.join(leftStore.currentPath.value, 'top.txt');
        final rightTop = p.join(rightStore.currentPath.value, 'top.txt');
        final leftDeep = p.join(
          leftStore.currentPath.value,
          'nested',
          'deep.txt',
        );
        final rightDeep = p.join(
          rightStore.currentPath.value,
          'nested',
          'deep.txt',
        );

        expect(
          controller.leftResults.value[leftTop]?.status,
          CompareStatus.older,
        );
        expect(
          controller.rightResults.value[rightTop]?.status,
          CompareStatus.newer,
        );
        expect(
          controller.leftResults.value[leftDeep]?.status,
          CompareStatus.older,
        );
        expect(
          controller.rightResults.value[rightDeep]?.status,
          CompareStatus.newer,
        );
      },
    );

    test(
      'same content with skewed mtime is identical on local drives',
      () async {
        await controller.start();

        final leftStore = paneLeft.tabs.activeTab.value.store;
        final rightStore = paneRight.tabs.activeTab.value.store;
        final leftCopy = p.join(leftStore.currentPath.value, 'copy.txt');
        final rightCopy = p.join(rightStore.currentPath.value, 'copy.txt');

        expect(
          controller.leftResults.value[leftCopy]?.status,
          CompareStatus.identical,
        );
        expect(
          controller.rightResults.value[rightCopy]?.status,
          CompareStatus.identical,
        );
      },
    );

    test('diffPairFor pairs files by relative path left then right', () async {
      await controller.start();

      final leftStore = paneLeft.tabs.activeTab.value.store;
      final rightStore = paneRight.tabs.activeTab.value.store;
      final leftDeep = p.join(
        leftStore.currentPath.value,
        'nested',
        'deep.txt',
      );
      final rightDeep = p.join(
        rightStore.currentPath.value,
        'nested',
        'deep.txt',
      );

      final fromRight = controller.diffPairFor(rightDeep);
      expect(fromRight?.$1.path, leftDeep);
      expect(fromRight?.$2.path, rightDeep);
      expect(controller.diffPairFor(leftDeep)?.$2.path, rightDeep);
      expect(
        controller.diffPairFor(p.join(leftStore.currentPath.value, 'nested')),
        isNull,
      );
    });
  });
}
