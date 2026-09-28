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
  late Signal<int> anchorIndex;
  late Signal<int> gridColumns;
  late UpstreamSelectionController controller;

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
    anchorIndex = signal(-1);
    gridColumns = signal(4);
    controller = UpstreamSelectionController(
      selectedPaths: selectedPaths,
      cursorIndex: cursorIndex,
      anchorIndex: anchorIndex,
      gridColumns: gridColumns,
      visibleFiles: () => files,
    );
  });

  group('UpstreamSelectionController.moveCursor (plain, no Shift)', () {
    test('collapses the selection to the single destination file, moving '
        'the anchor with it', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;

      controller.moveCursor(1);

      expect(
        selectedPaths.value,
        {'/dir/b.txt'},
        reason:
            'unlike the personal scheme, plain arrow-move always '
            'collapses to the single destination file',
      );
      expect(cursorIndex.value, 1);
      expect(anchorIndex.value, 1);
    });
  });

  group('UpstreamSelectionController._applyCursorMove (Shift extend)', () {
    testWidgets('extends the marked range from the anchor to the new '
        'position', (tester) async {
      selectedPaths.value = {'/dir/a.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.moveCursor(2); // a -> c

      expect(selectedPaths.value, {
        '/dir/a.txt',
        '/dir/b.txt',
        '/dir/c.txt',
      }, reason: 'extends [anchor..next] as a whole, not a per-cell toggle');
      expect(cursorIndex.value, 2);
      expect(anchorIndex.value, 0, reason: 'the anchor never moves by itself');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets(
      'a known upstream quirk: extending from an unmarked cursor cell '
      'grows the selection without moving the cursor',
      (tester) async {
        // Reachable via Ctrl+click removing the cursor's own cell without
        // moving it (see the onSelect group below) — reproduced directly
        // here for a focused, minimal repro.
        selectedPaths.value = {'/dir/a.txt', '/dir/b.txt', '/dir/c.txt'};
        cursorIndex.value = 3; // d.txt, not currently marked
        anchorIndex.value = 2; // c.txt
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

        controller.moveCursor(1); // attempted d -> e

        expect(selectedPaths.value, {
          '/dir/a.txt',
          '/dir/b.txt',
          '/dir/c.txt',
          '/dir/d.txt',
        });
        expect(
          cursorIndex.value,
          3,
          reason:
              'upstream returns from inside the batch before reassigning '
              'cursorIndex in this specific case — the cursor visibly '
              'stays put even though the mark set grew',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      },
    );
  });

  group('UpstreamSelectionController.deselectAll', () {
    test('resets both the cursor and the anchor to -1', () {
      selectedPaths.value = {'/dir/a.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;

      controller.deselectAll();

      expect(selectedPaths.value, isEmpty);
      expect(cursorIndex.value, -1);
      expect(anchorIndex.value, -1);
    });
  });

  group('UpstreamSelectionController.toggleSelectAndAdvance', () {
    test('refuses to deselect the last remaining selected item', () {
      selectedPaths.value = {'/dir/b.txt'};
      cursorIndex.value = 1;

      controller.toggleSelectAndAdvance();

      expect(
        selectedPaths.value,
        {'/dir/b.txt'},
        reason:
            'the personal scheme allows emptying the mark set; upstream '
            'never lets the last item go',
      );
      expect(cursorIndex.value, 2);
    });

    test('does deselect when at least one other item stays selected', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
      cursorIndex.value = 1;

      controller.toggleSelectAndAdvance();

      expect(selectedPaths.value, {'/dir/a.txt'});
      expect(cursorIndex.value, 2);
    });
  });

  group('UpstreamSelectionController.onContextMenu', () {
    test('collapses to the target and moves the anchor when it was '
        'unmarked', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;

      controller.onContextMenu(FileSelectionEvent(entry: files[2], index: 2));

      expect(selectedPaths.value, {'/dir/c.txt'});
      expect(cursorIndex.value, 2);
      expect(anchorIndex.value, 2);
    });

    test('does nothing at all when the target is already part of a '
        'multi-selection', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;

      controller.onContextMenu(FileSelectionEvent(entry: files[1], index: 1));

      expect(
        selectedPaths.value,
        {'/dir/a.txt', '/dir/b.txt'},
        reason:
            'right-clicking within an existing multi-selection must '
            'preserve it, unlike the personal scheme which always moves '
            'the cursor',
      );
      expect(
        cursorIndex.value,
        0,
        reason: 'the cursor does not move either in this case',
      );
    });
  });

  group('UpstreamSelectionController.onSelect (mouse)', () {
    test('a plain click collapses the selection and sets the anchor', () {
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};

      controller.onSelect(FileSelectionEvent(entry: files[2], index: 2));

      expect(selectedPaths.value, {'/dir/c.txt'});
      expect(cursorIndex.value, 2);
      expect(anchorIndex.value, 2);
    });

    testWidgets(
      'Ctrl+click removing the selected cursor cell recomputes the anchor '
      'to the last remaining selected file, without moving the cursor off '
      'the now-unmarked target',
      (tester) async {
        selectedPaths.value = {'/dir/a.txt', '/dir/b.txt', '/dir/d.txt'};
        cursorIndex.value = 3;
        anchorIndex.value = 3;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

        controller.onSelect(FileSelectionEvent(entry: files[3], index: 3));

        expect(selectedPaths.value, {'/dir/a.txt', '/dir/b.txt'});
        expect(
          anchorIndex.value,
          1,
          reason: 'recomputed to the last remaining selected file (b.txt)',
        );
        expect(cursorIndex.value, 3);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      },
    );

    testWidgets('Shift+click marks the inclusive range from the anchor', (
      tester,
    ) async {
      selectedPaths.value = {'/dir/a.txt'};
      cursorIndex.value = 0;
      anchorIndex.value = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      controller.onSelect(FileSelectionEvent(entry: files[3], index: 3));

      expect(selectedPaths.value, {
        '/dir/a.txt',
        '/dir/b.txt',
        '/dir/c.txt',
        '/dir/d.txt',
      });
      expect(cursorIndex.value, 3);
      expect(anchorIndex.value, 0);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });
  });
}
