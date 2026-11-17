import 'package:signals/signals.dart';

/// The cursor and marks of a file view, handed to the view as signals so a
/// change rebuilds only the rows it affects instead of the whole list.
class FileListSelection {
  final ReadonlySignal<int> cursorIndex;
  final ReadonlySignal<Set<String>> selectedPaths;

  FileListSelection({required this.cursorIndex, required this.selectedPaths});

  FileListSelection.fixed({
    int cursorIndex = -1,
    Set<String> selectedPaths = const {},
  }) : cursorIndex = signal(cursorIndex),
       selectedPaths = signal(selectedPaths);

  static final none = FileListSelection.fixed();

  ReadonlySignal<bool> cursorAt(int index) =>
      computed(() => cursorIndex.value == index);

  ReadonlySignal<bool> marked(String path) =>
      computed(() => selectedPaths.value.contains(path));
}
