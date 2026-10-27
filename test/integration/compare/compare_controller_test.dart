@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';
import 'package:waydir/core/fs/file_sort.dart';
import 'package:waydir/core/fs/file_system_service.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/compare/compare_controller.dart';
import 'package:waydir/features/compare/compare_excludes_bar.dart';
import 'package:waydir/features/compare/compare_mode_bar.dart';
import 'package:waydir/core/models/file_operation.dart';
import 'package:waydir/features/compare/compare_diff.dart';
import 'package:waydir/features/compare/compare_sync_plan.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/panes/pane_store.dart';
import 'package:waydir/i18n/strings.g.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      File(p.join(left.path, 'only_left.txt')).writeAsStringSync('x');

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
      'toggle starts in the requested mode and a second press exits',
      () async {
        await controller.toggle(recursive: false);

        expect(controller.recursive.value, isFalse);
        expect(controller.active.value, isTrue);
        final NavigationStore leftStore = paneLeft.tabs.activeTab.value.store;
        final leftTop = p.join(leftStore.currentPath.value, 'top.txt');
        expect(
          controller.leftResults.value[leftTop]?.status,
          CompareStatus.older,
        );
        expect(
          controller.leftResults.value.values.any(
            (r) => r.relativePath.startsWith('nested/'),
          ),
          isFalse,
        );

        await controller.toggle(recursive: false);

        expect(controller.active.value, isFalse);
        expect(controller.leftResults.value, isEmpty);

        await controller.toggle(recursive: true);

        expect(controller.recursive.value, isTrue);
        expect(controller.active.value, isTrue);
        final leftDeep = p.join(
          leftStore.currentPath.value,
          'nested',
          'deep.txt',
        );
        expect(
          controller.leftResults.value[leftDeep]?.status,
          CompareStatus.older,
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

    test('one-sided files appear as ghosts in the other pane', () async {
      await controller.start();

      final leftStore = paneLeft.tabs.activeTab.value.store;
      final rightStore = paneRight.tabs.activeTab.value.store;
      final ghosts = rightStore.ghostFiles.value;

      expect(ghosts.map((g) => g.name), ['only_left.txt']);
      expect(
        ghosts.single.path,
        p.join(rightStore.currentPath.value, 'only_left.txt'),
      );
      expect(
        ghosts.single.ghostOf?.path,
        p.join(leftStore.currentPath.value, 'only_left.txt'),
      );
      expect(leftStore.ghostFiles.value, isEmpty);
      expect(rightStore.visibleFiles.value.where((f) => f.isGhost).length, 1);

      controller.stop();
      expect(rightStore.ghostFiles.value, isEmpty);
    });

    test('right pane follows the left sort, cursor and folder', () async {
      await controller.start();

      final leftStore = paneLeft.tabs.activeTab.value.store;
      final rightStore = paneRight.tabs.activeTab.value.store;
      final leftRoot = leftStore.currentPath.value;
      final rightRoot = rightStore.currentPath.value;
      leftStore.files.value = await FileSystemService.listDirectory(leftRoot);
      rightStore.files.value = await FileSystemService.listDirectory(rightRoot);

      leftStore.setSortKey(SortKey.size);
      expect(rightStore.effectiveSortKey, SortKey.size);
      rightStore.setSortAscending(false);
      expect(leftStore.sortAscending.value, isFalse);
      expect(rightStore.effectiveSortAscending, isFalse);

      final leftFiles = leftStore.visibleFiles.value;
      leftStore.cursorIndex.value = leftFiles.indexWhere(
        (f) => f.name == 'copy.txt',
      );
      expect(rightStore.cursorEntry.value?.name, 'copy.txt');

      final rightFiles = rightStore.visibleFiles.value;
      rightStore.cursorIndex.value = rightFiles.indexWhere(
        (f) => f.name == 'only_left.txt',
      );
      expect(rightStore.cursorEntry.value?.isGhost, isTrue);
      expect(leftStore.cursorEntry.value?.name, 'only_left.txt');

      leftStore.navigateTo(p.join(leftRoot, 'nested'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rightStore.currentPath.value, p.join(rightRoot, 'nested'));

      controller.stop();
      expect(rightStore.sortLeader.value, isNull);
    });

    test('cursor steps through ghost rows one at a time', () async {
      await controller.start();

      final leftStore = paneLeft.tabs.activeTab.value.store;
      final rightStore = paneRight.tabs.activeTab.value.store;
      leftStore.files.value = await FileSystemService.listDirectory(
        leftStore.currentPath.value,
      );
      rightStore.files.value = await FileSystemService.listDirectory(
        rightStore.currentPath.value,
      );
      final count = rightStore.visibleFiles.value.length;
      rightStore.cursorIndex.value = 0;
      final seen = <int>[rightStore.cursorIndex.value];
      for (var i = 1; i < count; i++) {
        rightStore.moveCursor(1);
        await Future<void>.delayed(Duration.zero);
        seen.add(rightStore.cursorIndex.value);
      }
      expect(seen, [for (var i = 0; i < count; i++) i]);
    });

    test(
      'watcher refresh keeps the cursor on the same row past ghosts',
      () async {
        await controller.start();

        final rightStore = paneRight.tabs.activeTab.value.store;
        final listing = await FileSystemService.listDirectory(
          rightStore.currentPath.value,
        );
        rightStore.files.value = listing;
        final visible = rightStore.visibleFiles.value;
        final target = visible.indexWhere((f) => f.name == 'top.txt');
        expect(visible.sublist(0, target).any((f) => f.isGhost), isTrue);
        rightStore.cursorIndex.value = target;

        rightStore.debugApplyExternalChanges(List.of(listing));

        expect(rightStore.cursorEntry.value?.name, 'top.txt');
      },
    );

    test('ghosts are never part of the selection', () async {
      await controller.start();

      final rightStore = paneRight.tabs.activeTab.value.store;
      rightStore.selectAll();
      await Future<void>.delayed(Duration.zero);

      expect(rightStore.selectedEntries.any((e) => e.isGhost), isFalse);
      expect(
        rightStore.selectedPaths.value.intersection(
          rightStore.ghostPaths.value,
        ),
        isEmpty,
      );
    });

    test('sync confirms a summary then overwrites without prompting', () async {
      await controller.start();
      CompareSyncPlan? shown;
      controller.confirmSync = (plan) async {
        shown = plan;

        return true;
      };

      await controller.syncRightToLeft();
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline) &&
          (ops.tasks.value.isEmpty ||
              ops.tasks.value.any(
                (t) =>
                    t.status != TaskStatus.completed &&
                    t.status != TaskStatus.failed,
              ))) {
        expect(
          ops.tasks.value.any((t) => t.status == TaskStatus.waitingConflicts),
          isFalse,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(shown?.updated.map((r) => r.relativePath), [
        'nested/deep.txt',
        'top.txt',
      ]);
      expect(shown?.skipped, isEmpty);
      final leftRoot = paneLeft.tabs.activeTab.value.store.currentPath.value;
      expect(File(p.join(leftRoot, 'top.txt')).readAsStringSync(), 'HELLO');
      expect(
        File(p.join(leftRoot, 'nested', 'deep.txt')).readAsStringSync(),
        'WORLD',
      );
    });

    test('declining the sync summary copies nothing', () async {
      await controller.start();
      controller.confirmSync = (_) async => false;

      await controller.syncRightToLeft();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(ops.tasks.value, isEmpty);
      final leftRoot = paneLeft.tabs.activeTab.value.store.currentPath.value;
      expect(File(p.join(leftRoot, 'top.txt')).readAsStringSync(), 'hello');
    });

    test(
      'excluded patterns hide entries from results, ghosts and sync',
      () async {
        final leftStore = paneLeft.tabs.activeTab.value.store;
        final rightStore = paneRight.tabs.activeTab.value.store;
        final leftRoot = leftStore.currentPath.value;
        final rightRoot = rightStore.currentPath.value;
        final gitDir = Directory(p.join(rightRoot, '.git'))..createSync();
        File(p.join(gitDir.path, 'HEAD')).writeAsStringSync('ref: main');
        File(p.join(rightRoot, 'data.bin')).writeAsStringSync('payload');
        File(
          p.join(rightRoot, 'nested', 'model.bin'),
        ).writeAsStringSync('payload2');

        final settings = SettingsStore.instance;
        final previous = settings.compareExcludePatterns.value;
        settings.compareExcludePatterns.value = '*.bin, .git';
        try {
          await controller.start();

          final rightRel = controller.rightResults.value.values
              .map((r) => r.relativePath)
              .toSet();
          expect(rightRel, isNot(contains('data.bin')));
          expect(rightRel, isNot(contains('nested/model.bin')));
          expect(rightRel, isNot(contains('.git')));
          expect(rightRel, isNot(contains('.git/HEAD')));
          expect(rightRel, contains('top.txt'));
          expect(rightRel, contains('nested/deep.txt'));

          final leftGhosts = leftStore.ghostPaths.value
              .map((path) => p.basename(path))
              .toSet();
          expect(leftGhosts, isNot(contains('data.bin')));
          expect(leftGhosts, isNot(contains('.git')));

          CompareSyncPlan? shown;
          controller.confirmSync = (plan) async {
            shown = plan;

            return true;
          };
          await controller.syncRightToLeft();
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(deadline) &&
              (ops.tasks.value.isEmpty ||
                  ops.tasks.value.any(
                    (t) =>
                        t.status != TaskStatus.completed &&
                        t.status != TaskStatus.failed,
                  ))) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }

          expect(shown, isNotNull);
          expect(shown!.added.map((r) => r.relativePath), isEmpty);
          expect(shown!.updated.map((r) => r.relativePath), [
            'nested/deep.txt',
            'top.txt',
          ]);
          expect(File(p.join(leftRoot, 'data.bin')).existsSync(), isFalse);
          expect(
            File(p.join(leftRoot, 'nested', 'model.bin')).existsSync(),
            isFalse,
          );
          expect(Directory(p.join(leftRoot, '.git')).existsSync(), isFalse);
          expect(File(p.join(leftRoot, 'top.txt')).readAsStringSync(), 'HELLO');
        } finally {
          settings.compareExcludePatterns.value = previous;
        }
      },
    );

    test(
      'per-directory .waydir-sync file overrides the global setting',
      () async {
        final leftStore = paneLeft.tabs.activeTab.value.store;
        final rightStore = paneRight.tabs.activeTab.value.store;
        final leftRoot = leftStore.currentPath.value;
        final rightRoot = rightStore.currentPath.value;
        File(p.join(rightRoot, 'scratch.bin')).writeAsStringSync('scratch');

        final settings = SettingsStore.instance;
        final previous = settings.compareExcludePatterns.value;
        settings.compareExcludePatterns.value = '*.txt, .git';
        try {
          File(
            p.join(leftRoot, '.waydir-sync'),
          ).writeAsStringSync('scratch.bin');
          await controller.start();

          expect(controller.effectiveExcludePatterns.value, 'scratch.bin');

          final rightRel = controller.rightResults.value.values
              .map((r) => r.relativePath)
              .toSet();
          expect(rightRel, isNot(contains('scratch.bin')));
          expect(rightRel, contains('top.txt'));
          expect(rightRel, isNot(contains('.waydir-sync')));
          final leftRel = controller.leftResults.value.values
              .map((r) => r.relativePath)
              .toSet();
          expect(leftRel, isNot(contains('.waydir-sync')));
          expect(
            rightStore.ghostPaths.value.map(p.basename),
            isNot(contains('.waydir-sync')),
          );

          final saved = await controller.saveExcludePatterns('top.txt');
          expect(saved, isTrue);
          expect(
            File(p.join(leftRoot, '.waydir-sync')).readAsStringSync().trim(),
            'top.txt',
          );
          expect(
            File(p.join(rightRoot, '.waydir-sync')).readAsStringSync().trim(),
            'top.txt',
          );
          expect(controller.effectiveExcludePatterns.value, 'top.txt');

          final rightRel2 = controller.rightResults.value.values
              .map((r) => r.relativePath)
              .toSet();
          expect(rightRel2, contains('scratch.bin'));
          expect(rightRel2, isNot(contains('top.txt')));
        } finally {
          settings.compareExcludePatterns.value = previous;
        }
      },
    );

    test('saving empty patterns clears the per-directory marker', () async {
      await controller.start();
      final leftStore = paneLeft.tabs.activeTab.value.store;
      final rightStore = paneRight.tabs.activeTab.value.store;
      final leftMarker = p.join(leftStore.currentPath.value, '.waydir-sync');
      final rightMarker = p.join(rightStore.currentPath.value, '.waydir-sync');

      expect(await controller.saveExcludePatterns('top.txt'), isTrue);
      expect(await controller.saveExcludePatterns(''), isTrue);

      expect(controller.effectiveExcludePatterns.value, '');
      expect(File(leftMarker).readAsStringSync().trim(), '');
      expect(File(rightMarker).readAsStringSync().trim(), '');
      final rightRel = controller.rightResults.value.values
          .map((r) => r.relativePath)
          .toSet();
      expect(rightRel, contains('top.txt'));
    });

    testWidgets(
      'excludes button toggles the inline bar; Enter saves, Esc closes',
      (tester) async {
        await tester.runAsync(() async {
          await controller.start();
          expect(await controller.saveExcludePatterns('top.txt'), isTrue);
        });
        expect(controller.effectiveExcludePatterns.value, 'top.txt');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: Scaffold(body: CompareModeBar(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CompareExcludesBar), findsNothing);

        await tester.tap(find.text(t.compare.excludes));
        await tester.pumpAndSettle();
        expect(find.byType(CompareExcludesBar), findsOneWidget);

        final field = find.byType(TextField);
        expect(find.text('top.txt'), findsOneWidget);
        expect(
          tester.widget<TextField>(field).focusNode!.hasPrimaryFocus,
          isTrue,
        );

        await tester.enterText(field, '*.bin');
        await tester.runAsync(() async {
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        expect(controller.effectiveExcludePatterns.value, '*.bin');
        expect(
          tester.widget<TextField>(field).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        final leftStore = paneLeft.tabs.activeTab.value.store;
        expect(
          File(
            p.join(leftStore.currentPath.value, '.waydir-sync'),
          ).readAsStringSync().trim(),
          '*.bin',
        );
        expect(find.byType(CompareExcludesBar), findsOneWidget);

        await tester.enterText(field, 'scratch.bin');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CompareExcludesBar), findsNothing);
        expect(controller.effectiveExcludePatterns.value, '*.bin');

        await tester.tap(find.text(t.compare.excludes));
        await tester.pumpAndSettle();
        expect(find.byType(CompareExcludesBar), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text(t.compare.excludeClear));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        expect(controller.effectiveExcludePatterns.value, '');
        expect(find.text(t.compare.excludeClear), findsOneWidget);
        await tester.tap(find.text(t.compare.excludes));
        await tester.pumpAndSettle();
        expect(find.byType(CompareExcludesBar), findsNothing);
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
