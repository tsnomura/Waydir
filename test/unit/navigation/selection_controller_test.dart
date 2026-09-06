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
    anchorIndex = signal(-1);
    gridColumns = signal(4);
    controller = SelectionController(
      selectedPaths: selectedPaths,
      cursorIndex: cursorIndex,
      anchorIndex: anchorIndex,
      gridColumns: gridColumns,
      visibleFiles: () => files,
    );
  });

  group('SelectionController.moveCursor with an already-tracked cursor', () {
    test('steps forward/backward from the current index as usual', () {
      cursorIndex.value = 1;
      selectedPaths.value = {'/dir/b.txt'};

      controller.moveCursor(1);

      expect(cursorIndex.value, 2);
      expect(selectedPaths.value, {'/dir/c.txt'});
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
      expect(selectedPaths.value, {'/dir/d.txt'});
    });

    test('steps backward from the selected file, not to the list start', () {
      cursorIndex.value = -1;
      selectedPaths.value = {'/dir/c.txt'}; // index 2 of 5

      controller.moveCursor(-1);

      expect(cursorIndex.value, 1);
      expect(selectedPaths.value, {'/dir/b.txt'});
    });

    test('falls back to jumping to the start/end when nothing is selected', () {
      cursorIndex.value = -1;
      selectedPaths.value = {};

      controller.moveCursor(1);

      expect(cursorIndex.value, 0);
      expect(selectedPaths.value, {'/dir/a.txt'});
    });

    test('falls back to jumping to the start/end when multiple files are '
        'selected', () {
      cursorIndex.value = -1;
      selectedPaths.value = {'/dir/a.txt', '/dir/b.txt'};

      controller.moveCursor(-1);

      expect(cursorIndex.value, files.length - 1);
    });
  });
}
