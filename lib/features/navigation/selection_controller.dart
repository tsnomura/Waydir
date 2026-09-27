import 'package:signals/signals.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/settings/settings_store.dart';

class SelectionController {
  final Signal<Set<String>> selectedPaths;
  final Signal<int> cursorIndex;
  final Signal<int> gridColumns;
  final List<FileEntry> Function() visibleFiles;

  int _pageRows = 10;

  SelectionController({
    required this.selectedPaths,
    required this.cursorIndex,
    required this.gridColumns,
    required this.visibleFiles,
  });

  List<FileEntry> get _vf => visibleFiles();

  /// Click (and Ctrl+click, a deliberate alias) toggles the clicked item's
  /// mark in place and moves the cursor there — every other mark is left
  /// untouched. Shift+click toggles the inclusive range from the cursor's
  /// position *before this click* to the clicked item (both endpoints), then
  /// moves the cursor. Neither depends on any state beyond what's currently
  /// visible (the existing marks, the current cursor).
  void onSelect(FileSelectionEvent event) {
    final shift = AppShortcuts.isShift;

    batch(() {
      if (shift) {
        final start = cursorIndex.value >= 0 && cursorIndex.value < _vf.length
            ? cursorIndex.value
            : event.index;
        final end = event.index;
        final lo = start < end ? start : end;
        final hi = start < end ? end : start;
        final paths = Set<String>.from(selectedPaths.value);
        for (int i = lo; i <= hi; i++) {
          final p = _vf[i].path;
          if (!paths.remove(p)) paths.add(p);
        }
        selectedPaths.value = paths;
      } else {
        final paths = Set<String>.from(selectedPaths.value);
        if (!paths.remove(event.entry.path)) paths.add(event.entry.path);
        selectedPaths.value = paths;
      }
      cursorIndex.value = event.index;
    });
  }

  void selectAll() {
    selectedPaths.value = Set<String>.from(_vf.map((f) => f.path));
  }

  List<String> selectedNamesForFile() {
    final selected = selectedPaths.value;
    if (selected.isEmpty) return const [];

    return [
      for (final entry in _vf)
        if (selected.contains(entry.path)) entry.name,
    ];
  }

  int selectNamesFromFile(Iterable<String> names) {
    final wanted = names
        .map(
          (name) =>
              name.endsWith('\r') ? name.substring(0, name.length - 1) : name,
        )
        .map((name) => name.startsWith('\uFEFF') ? name.substring(1) : name)
        .where((name) => name.isNotEmpty)
        .toSet();
    if (wanted.isEmpty) {
      deselectAll();

      return 0;
    }
    final matched = <String>{};
    var cursor = -1;
    for (var i = 0; i < _vf.length; i++) {
      final entry = _vf[i];
      if (!wanted.contains(entry.name)) continue;
      matched.add(entry.path);
      cursor = cursor < 0 ? i : cursor;
    }
    batch(() {
      selectedPaths.value = matched;
      cursorIndex.value = cursor;
    });

    return matched.length;
  }

  int selectByPattern(String pattern) {
    final globs = pattern
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
    if (globs.isEmpty) return 0;
    final alternatives = globs.map((glob) {
      final buf = StringBuffer();
      for (final ch in glob.split('')) {
        switch (ch) {
          case '*':
            buf.write('.*');
          case '?':
            buf.write('.');
          case '[':
          case ']':
            buf.write(ch);
          default:
            buf.write(RegExp.escape(ch));
        }
      }

      return buf.toString();
    });
    final RegExp re;
    try {
      re = RegExp('^(?:${alternatives.join('|')})\$', caseSensitive: false);
    } catch (e) {
      return 0;
    }
    final matched = _vf.where((f) => re.hasMatch(f.name)).toList();
    selectedPaths.value = Set<String>.from(matched.map((f) => f.path));

    return matched.length;
  }

  void deselectAll() {
    selectedPaths.value = {};
  }

  void invertSelection() {
    final selected = selectedPaths.value;
    selectedPaths.value = Set<String>.from(
      _vf.where((f) => !selected.contains(f.path)).map((f) => f.path),
    );
  }

  void toggleSelectAndAdvance() {
    batch(() {
      if (cursorIndex.value >= 0 && cursorIndex.value < _vf.length) {
        final path = _vf[cursorIndex.value].path;
        final paths = Set<String>.from(selectedPaths.value);
        if (!paths.remove(path)) paths.add(path);
        selectedPaths.value = paths;
      }
      if (cursorIndex.value < _vf.length - 1) {
        cursorIndex.value++;
      }
    });
  }

  void markCursorAndAdvance() {
    batch(() {
      if (cursorIndex.value >= 0 && cursorIndex.value < _vf.length) {
        final path = _vf[cursorIndex.value].path;
        if (!selectedPaths.value.contains(path)) {
          selectedPaths.value = {...selectedPaths.value, path};
        }
      }
      if (cursorIndex.value < _vf.length - 1) {
        cursorIndex.value++;
      }
    });
  }

  void unmarkCursorAndAdvance() {
    batch(() {
      if (cursorIndex.value >= 0 && cursorIndex.value < _vf.length) {
        final path = _vf[cursorIndex.value].path;
        if (selectedPaths.value.contains(path)) {
          selectedPaths.value = selectedPaths.value.difference({path});
        }
      }
      if (cursorIndex.value < _vf.length - 1) {
        cursorIndex.value++;
      }
    });
  }

  /// Rubber-band result: [paths] is the complete resulting mark set to
  /// apply — a wholesale replace, not a delta — since the rubber-band layer
  /// already computed it as a snapshot-XOR-rectangle each frame.
  void onRectSelect(Set<String> paths) {
    batch(() {
      selectedPaths.value = paths;
      if (paths.isNotEmpty) {
        final idx = _vf.indexWhere((f) => paths.contains(f.path));
        if (idx >= 0) cursorIndex.value = idx;
      }
    });
  }

  List<FileEntry> get selectedEntries {
    final paths = selectedPaths.value;

    return _vf.where((f) => paths.contains(f.path)).toList();
  }

  void onContextMenu(FileSelectionEvent event) {
    batch(() {
      if (!selectedPaths.value.contains(event.entry.path)) {
        selectedPaths.value = {event.entry.path};
      }
      cursorIndex.value = event.index;
    });
  }

  void jumpToIndex(int index) {
    batch(() {
      if (_vf.isEmpty) return;
      if (index < 0 || index >= _vf.length) return;
      cursorIndex.value = index;
      selectedPaths.value = {_vf[index].path};
    });
  }

  void setPageRows(int rows) {
    if (rows > 0) _pageRows = rows;
  }

  /// [cursorIndex] as-is when valid, otherwise resolved from the single
  /// selected file if there is exactly one (e.g. right after Quick Look
  /// opens on a file that was selected without going through cursor-based
  /// navigation — a reveal/jump, a stats-panel click, ...). Falling back to
  /// jumping to the very start/end of the list in that case, as every
  /// `cursorIndex.value < 0` branch below used to do unconditionally,
  /// ignored what's actually selected/shown, so the first arrow press
  /// after such a jump landed on the wrong file instead of stepping from
  /// the one already on screen.
  int _resolvedCursorIndex() {
    final idx = cursorIndex.value;
    if (idx >= 0) return idx;
    final sel = selectedPaths.value;
    if (sel.length == 1) {
      final found = _vf.indexWhere((f) => f.path == sel.first);
      if (found >= 0) return found;
    }

    return -1;
  }

  int get _pageStep => (_pageRows * 0.8).floor().clamp(1, _pageRows);

  void moveCursorHorizontally(int delta, {bool isRepeat = false}) {
    final settings = SettingsStore.instance;
    if (settings.fileViewMode.value != 'grid') {
      moveCursor(delta, isRepeat: isRepeat);

      return;
    }
    if (_vf.isEmpty || delta == 0) return;
    final current = _resolvedCursorIndex();
    if (current < 0) {
      _initCursor(delta > 0 ? 0 : _vf.length - 1);

      return;
    }
    final columns = gridColumns.value.clamp(1, 1000);
    final col = current % columns;
    final atEdge = delta < 0 ? col == 0 : col == columns - 1;
    if (atEdge) {
      if (isRepeat) return;
      _applyCursorMove(current);

      return;
    }
    final ctrl = AppShortcuts.isControl;
    final next = ctrl
        ? (delta < 0 ? current - col : current + (columns - 1 - col))
        : current + delta;
    _applyCursorMove(next.clamp(0, _vf.length - 1));
  }

  void moveCursor(int delta, {bool isRepeat = false}) {
    final settings = SettingsStore.instance;
    final rowStep = AppShortcuts.isControl ? _pageStep : 1;
    final step = settings.fileViewMode.value == 'grid' && delta.abs() == 1
        ? delta * gridColumns.value.clamp(1, 1000) * rowStep
        : delta * rowStep;
    if (_vf.isEmpty) return;
    final current = _resolvedCursorIndex();
    if (current < 0) {
      _initCursor(step > 0 ? 0 : _vf.length - 1);

      return;
    }
    final next = (current + step).clamp(0, _vf.length - 1);
    if (isRepeat && next == current) return;
    _applyCursorMove(next);
  }

  void moveCursorByPage(int dir, {bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    final current = _resolvedCursorIndex();
    if (current < 0) {
      _initCursor(dir > 0 ? 0 : _vf.length - 1);

      return;
    }
    final next = (current + dir * _pageStep).clamp(0, _vf.length - 1);
    if (isRepeat && next == current) return;
    _applyCursorMove(next);
  }

  void moveCursorToStart({bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    if (cursorIndex.value < 0) {
      _initCursor(0);

      return;
    }
    if (isRepeat && cursorIndex.value == 0) return;
    _applyCursorMove(0);
  }

  void moveCursorToEnd({bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    final last = _vf.length - 1;
    if (cursorIndex.value < 0) {
      _initCursor(last);

      return;
    }
    if (isRepeat && cursorIndex.value == last) return;
    _applyCursorMove(last);
  }

  void _initCursor(int index) {
    cursorIndex.value = index;
  }

  /// Plain move: cursor only, marks untouched. Shift+move toggles the range
  /// between the *old* cursor position and [next], excluding [next] itself
  /// (the destination cell is left to the cursor highlight to indicate, not
  /// double-encoded as a mark too) — unless the cursor couldn't actually
  /// move ([next] equals the old position), in which case the old position
  /// itself is toggled, so a boundary Shift+move still changes exactly one
  /// item. Ctrl no longer changes which set operation this is — Ctrl only
  /// ever picks a bigger step, before this method is even called. Either way
  /// the range is derived purely from the current (visible) cursor
  /// position, never a persisted anchor.
  void _applyCursorMove(int next) {
    final shift = AppShortcuts.isShift;
    batch(() {
      if (shift) {
        final cur = cursorIndex.value >= 0 && cursorIndex.value < _vf.length
            ? cursorIndex.value
            : next;
        final lo = cur < next ? cur : next;
        final hi = cur < next ? next : cur;
        final paths = Set<String>.from(selectedPaths.value);
        for (int i = lo; i <= hi; i++) {
          if (i == cur || i != next) {
            final p = _vf[i].path;
            if (!paths.remove(p)) paths.add(p);
          }
        }
        selectedPaths.value = paths;
      }
      cursorIndex.value = next;
    });
  }
}
