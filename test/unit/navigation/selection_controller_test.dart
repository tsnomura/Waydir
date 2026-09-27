import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/navigation/selection_controller.dart';

FileEntry _entry(String name) => FileEntry.raw(
  name: name,
  path: '/dir/$name',
  type: FileItemType.file,
  size: 1,
  modifiedMs: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FileEntry> files;
  late Signal<Set<String>> selectedPaths;
  late Signal<int> cursorIndex;
  late Signal<int> gridColumns;
  late SelectionController controller;

  setUp(() {
    files = [
      _entry('a.txt'),
      _entry('b.txt'),
      _entry('c.txt'),
      _entry('d.txt'),
      _entry('e.txt'),
    ];
    selectedPaths = signal(<String>{});
    cursorIndex = signal(-1);
    gridColumns = signal(4);
    controller = SelectionController(
      selectedPaths: selectedPaths,
      cursorIndex: cursorIndex,
      gridColumns: gridColumns,
      visibleFiles: () => files,
    );
  });

  group('SelectionController.moveCursor with an already-tracked cursor', () {
    test('steps forward/backward, leaving marks untouched', () {
      cursorIndex.value = 1;
      selectedPaths.value = {'/dir/b.txt'};

      controller.moveCursor(1);

      expect(cursorIndex.value, 2);
      expect(selectedPaths.value, {
        '/dir/b.txt',
      }, reason: 'a plain (unmodified) move must never touch marks');
    });
  });

  group('SelectionController.moveCursor with an untracked cursor '
      '(regression: Quick Look opened on a file selected some other way)', () {
    test('steps forward from the selected file, not to the list end', () {
      // Exactly Quick Look's post-open state: a single file is selected
      // (it's the one being previewed) but cursorIndex was never set
      // through cursor-based navigation, so it's still -1.
      cursorIndex.value = -1;
      selectedPaths.value = {'/dir/c.txt'}; // index 2 of 5

      controller.moveCursor(1);

      expect(
        cursorIndex.value,
        3,
        reason:
            'should land one past the selected file (index 3), not '
            'jump to the last index in the list',
      );
      expect(selectedPaths.value, {'/dir/c.txt'});
    });

    test('steps backward from the selected file, not to the list start', () {
      cursorIndex.value = -1;
      selectedPaths.value = {'/dir/c.txt'}; // index 2 of 5

      controller.moveCursor(-1);

      expect(cursorIndex.value, 1);
      expect(selectedPaths.value, {'/dir/c.txt'});
    });

    test('falls back to jumping to the start/end when nothing is selected', () {
      cursorIndex.value = -1;
      selectedPaths.value = {};

      controller.moveCursor(1);

      expect(cursorIndex.value, 0);
      expect(selectedPaths.value, isEmpty);
    });

    test('falls back to jumping to the start/end when multiple files are '
        'selected', () {
      cursorIndex.value = -1;
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};

      controller.moveCursor(-1);

      expect(cursorIndex.value, files.length - 1);
      expect(selectedPaths.value, {'/dir/a.txt', '/dir/b.txt'});
    });
  });

  group('SelectionController.onSelect', () {
    testWidgets('plain click toggles the clicked mark in place, preserving '
        'every other mark', (tester) async {
      selectedPaths.value = {'/dir/a.txt', '/dir/c.txt'};
      cursorIndex.value = 0;

      controller.onSelect(FileSelectionEvent(entry: files[1], index: 1));
      expect(selectedPaths.value, {
        '/dir/a.txt',
        '/dir/b.txt',
        '/dir/c.txt',
      }, reason: 'clicking an unmarked item adds it without disturbing others');
      expect(cursorIndex.value, 1);

      controller.onSelect(FileSelectionEvent(entry: files[1], index: 1));
      expect(selectedPaths.value, {
        '/dir/a.txt',
        '/dir/c.txt',
      }, reason: 'clicking an already-marked item removes just that one');
    });

    testWidgets('Ctrl+click behaves identically to plain click (pure alias)', (
      tester,
    ) async {
      selectedPaths.value = {'/dir/a.txt'};
      cursorIndex.value = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      controller.onSelect(FileSelectionEvent(entry: files[2], index: 2));

      expect(selectedPaths.value, {'/dir/a.txt', '/dir/c.txt'});
      expect(cursorIndex.value, 2);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('Shift+click toggles the inclusive cursor..click range '
        '(both endpoints), unlike keyboard Shift+move', (tester) async {
      selectedPaths.value = {'/dir/c.txt', '/dir/e.txt'};
      cursorIndex.value = 1; // b.txt
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.onSelect(FileSelectionEvent(entry: files[3], index: 3));

      expect(
        selectedPaths.value,
        {'/dir/b.txt', '/dir/d.txt', '/dir/e.txt'},
        reason:
            'toggles [cursor..click] = {b,c,d}: b and d (unmarked) turn on, '
            'c (already marked) turns off; e survives outside the range',
      );
      expect(cursorIndex.value, 3);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });

  group('SelectionController move with Shift / Ctrl+Shift', () {
    testWidgets('Shift+move toggles the old cursor..new cursor range, '
        'excluding the destination cell', (tester) async {
      selectedPaths.value = {'/dir/e.txt'};
      cursorIndex.value = 1; // b.txt
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.moveCursor(2); // -> index 3 (d.txt)

      expect(
        selectedPaths.value,
        {'/dir/b.txt', '/dir/c.txt', '/dir/e.txt'},
        reason:
            'toggles [old cursor..new cursor) = {b.txt, c.txt}; the '
            'destination (d.txt) is left to the cursor highlight instead',
      );
      expect(cursorIndex.value, 3);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('Ctrl+move (no Shift) jumps by a page-sized step instead of '
        'one row, marks untouched', (tester) async {
      controller.setPageRows(4); // pageStep = (4*0.8).floor().clamp(1,4) = 3
      cursorIndex.value = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      controller.moveCursor(1);

      expect(cursorIndex.value, 3);
      expect(selectedPaths.value, isEmpty);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('Ctrl+Shift+move toggles the bigger (page-sized) swept '
        'range, excluding the destination', (tester) async {
      controller.setPageRows(4); // pageStep = 3
      selectedPaths.value = {'/dir/b.txt'};
      cursorIndex.value = 0; // a.txt
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      controller.moveCursor(1); // step 3 -> index 3 (d.txt)

      expect(
        selectedPaths.value,
        {'/dir/a.txt', '/dir/c.txt'},
        reason:
            'toggles [a,b,c) = {a.txt, b.txt, c.txt}: a and c (unmarked) '
            'turn on, b (already marked) turns off; d is the destination',
      );
      expect(cursorIndex.value, 3);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });

  group('Shift+move at a boundary (cursor can\'t actually move)', () {
    testWidgets('a fresh press still toggles the current cell', (tester) async {
      cursorIndex.value = 4; // last index, nothing selected
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.moveCursor(1);

      expect(cursorIndex.value, 4);
      expect(selectedPaths.value, {'/dir/e.txt'});

      controller.moveCursor(1);

      expect(
        selectedPaths.value,
        isEmpty,
        reason: 'each fresh (non-repeat) press toggles exactly one item',
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('auto-repeat is suppressed once stuck (no flicker)', (
      tester,
    ) async {
      cursorIndex.value = 4;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.moveCursor(1);
      expect(selectedPaths.value, {'/dir/e.txt'});

      controller.moveCursor(1, isRepeat: true);
      controller.moveCursor(1, isRepeat: true);

      expect(
        selectedPaths.value,
        {'/dir/e.txt'},
        reason:
            'repeat events while stuck at the boundary must not toggle '
            'again',
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });

  group('SelectionController.deselectAll', () {
    test('clears marks but leaves the cursor position untouched', () {
      selectedPaths.value = {'/dir/b.txt', '/dir/c.txt'};
      cursorIndex.value = 2;

      controller.deselectAll();

      expect(selectedPaths.value, isEmpty);
      expect(
        cursorIndex.value,
        2,
        reason:
            'previously reset the cursor to -1, which then made the next '
            'arrow press jump to the start/end of the list instead of '
            'stepping from where the cursor visibly was',
      );
    });
  });

  group(
    'SelectionController.markCursorAndAdvance / unmarkCursorAndAdvance',
    () {
      test('markCursorAndAdvance force-marks even if already marked, then '
          'advances', () {
        selectedPaths.value = {'/dir/a.txt'};
        cursorIndex.value = 0;

        controller.markCursorAndAdvance();

        expect(selectedPaths.value, {'/dir/a.txt'});
        expect(cursorIndex.value, 1);
      });

      test('markCursorAndAdvance adds an unmarked item', () {
        selectedPaths.value = {};
        cursorIndex.value = 0;

        controller.markCursorAndAdvance();

        expect(selectedPaths.value, {'/dir/a.txt'});
        expect(cursorIndex.value, 1);
      });

      test('unmarkCursorAndAdvance force-unmarks even if already unmarked, '
          'then advances', () {
        selectedPaths.value = {};
        cursorIndex.value = 0;

        controller.unmarkCursorAndAdvance();

        expect(selectedPaths.value, isEmpty);
        expect(cursorIndex.value, 1);
      });

      test('unmarkCursorAndAdvance removes an existing mark', () {
        selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
        cursorIndex.value = 0;

        controller.unmarkCursorAndAdvance();

        expect(selectedPaths.value, {'/dir/b.txt'});
        expect(cursorIndex.value, 1);
      });
    },
  );

  group('SelectionController.toggleSelectAndAdvance', () {
    test('can empty the mark set entirely (no "last item" guard)', () {
      selectedPaths.value = {'/dir/b.txt'};
      cursorIndex.value = 1;

      controller.toggleSelectAndAdvance();

      expect(selectedPaths.value, isEmpty);
      expect(cursorIndex.value, 2);
    });

    test('adds the cursor item and advances when it was unmarked', () {
      selectedPaths.value = {};
      cursorIndex.value = 0;

      controller.toggleSelectAndAdvance();

      expect(selectedPaths.value, {'/dir/a.txt'});
      expect(cursorIndex.value, 1);
    });
  });

  group('SelectionController.onContextMenu', () {
    test('always moves the cursor, even onto an already-marked item', () {
      selectedPaths.value = {'/dir/b.txt'};
      cursorIndex.value = 0;

      controller.onContextMenu(FileSelectionEvent(entry: files[1], index: 1));

      expect(
        cursorIndex.value,
        1,
        reason:
            'previously did nothing at all when the target was already '
            'marked',
      );
      expect(selectedPaths.value, {'/dir/b.txt'});
    });

    test(
      'overwrites the mark to just the clicked item when it was unmarked',
      () {
        selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
        cursorIndex.value = 0;

        controller.onContextMenu(FileSelectionEvent(entry: files[2], index: 2));

        expect(selectedPaths.value, {'/dir/c.txt'});
        expect(cursorIndex.value, 2);
      },
    );
  });

  group('SelectionController.onRectSelect', () {
    test('replaces the mark set wholesale with the given set', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/e.txt'};

      controller.onRectSelect({'/dir/b.txt', '/dir/c.txt'});

      expect(selectedPaths.value, {'/dir/b.txt', '/dir/c.txt'});
    });

    test('moves the cursor to the first enclosed file', () {
      cursorIndex.value = -1;

      controller.onRectSelect({'/dir/c.txt', '/dir/d.txt'});

      expect(cursorIndex.value, 2);
    });
  });
}
