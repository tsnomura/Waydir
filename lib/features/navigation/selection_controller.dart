import 'package:flutter/services.dart';
import 'package:signals/signals.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/settings/settings_store.dart';

abstract class SelectionController {
  final Signal<Set<String>> selectedPaths;
  final Signal<int> cursorIndex;
  final Signal<int> anchorIndex;
  final Signal<int> gridColumns;
  final List<FileEntry> Function() visibleFiles;

  int _pageRows = 10;

  SelectionController({
    required this.selectedPaths,
    required this.cursorIndex,
    required this.anchorIndex,
    required this.gridColumns,
    required this.visibleFiles,
  });

  List<FileEntry> get _vf => visibleFiles();

  int get pageStep => (_pageRows * 0.8).floor().clamp(1, _pageRows);

  void onSelect(FileSelectionEvent event);

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

  int selectNamesFromFile(Iterable<String> names);

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

  void deselectAll();

  void invertSelection() {
    final selected = selectedPaths.value;
    selectedPaths.value = Set<String>.from(
      _vf.where((f) => !selected.contains(f.path)).map((f) => f.path),
    );
  }

  void toggleSelectAndAdvance();

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

  void onRectSelect(Set<String> paths, {bool additive = false});

  List<FileEntry> get selectedEntries {
    final paths = selectedPaths.value;

    return _vf.where((f) => paths.contains(f.path)).toList();
  }

  void onContextMenu(FileSelectionEvent event);

  void jumpToIndex(int index);

  void setPageRows(int rows) {
    if (rows > 0) _pageRows = rows;
  }

  void moveCursorHorizontally(int delta, {bool isRepeat = false});

  void moveCursor(int delta, {bool isRepeat = false});

  void moveCursorByPage(int dir, {bool isRepeat = false});

  void moveCursorToStart({bool isRepeat = false});

  void moveCursorToEnd({bool isRepeat = false});
}

class PersonalSelectionController extends SelectionController {
  PersonalSelectionController({
    required super.selectedPaths,
    required super.cursorIndex,
    required super.anchorIndex,
    required super.gridColumns,
    required super.visibleFiles,
  });

  String? _rangeOriginPath;
  bool _rangeAdd = true;
  Set<String> _rangeSnapshot = const {};
  Set<String>? _rangeResult;
  int _rangeCursor = -1;

  /// Click just moves the cursor, touching no marks at all — the mouse
  /// equivalent of an arrow key. Ctrl+click toggles the clicked item's mark
  /// in place and moves the cursor there, every other mark left untouched.
  /// Shift+click paints the inclusive range from an origin to the clicked
  /// item and moves the cursor there; see [_shiftClick].
  @override
  void onSelect(FileSelectionEvent event) {
    if (AppShortcuts.isShift) {
      _shiftClick(event);

      return;
    }
    _rangeOriginPath = null;
    final ctrl = AppShortcuts.isControl;

    batch(() {
      if (ctrl) {
        final paths = Set<String>.from(selectedPaths.value);
        if (!paths.remove(event.entry.path)) paths.add(event.entry.path);
        selectedPaths.value = paths;
      }
      cursorIndex.value = event.index;
    });
  }

  /// The first Shift+click of a session fixes the origin at the cursor and
  /// snapshots the marks; mark vs. unmark is decided once, from the origin
  /// cell. Each Shift+click in the same session recomputes
  /// `snapshot ∪ [origin..click]` (or `−` when unmarking) from that
  /// snapshot, so clicking back toward the origin shrinks the range and
  /// restores whatever was outside it. Any other change to the cursor or
  /// the marks in between (a plain click, an arrow key, ...) ends the
  /// session, so the next Shift+click starts from wherever the cursor is.
  void _shiftClick(FileSelectionEvent event) {
    final files = _vf;
    var origin = _rangeOriginPath == null
        ? -1
        : files.indexWhere((f) => f.path == _rangeOriginPath);
    final continuing =
        origin >= 0 &&
        identical(selectedPaths.value, _rangeResult) &&
        cursorIndex.value == _rangeCursor;
    if (!continuing) {
      final cursor = _resolvedCursorIndex();
      origin = cursor >= 0 && cursor < files.length ? cursor : event.index;
      _rangeOriginPath = files[origin].path;
      _rangeSnapshot = selectedPaths.value;
      _rangeAdd = !_rangeSnapshot.contains(_rangeOriginPath);
    }
    final lo = origin < event.index ? origin : event.index;
    final hi = origin < event.index ? event.index : origin;
    final range = {for (var i = lo; i <= hi; i++) files[i].path};
    final result = _rangeAdd
        ? _rangeSnapshot.union(range)
        : _rangeSnapshot.difference(range);
    _rangeResult = result;
    _rangeCursor = event.index;
    batch(() {
      selectedPaths.value = result;
      cursorIndex.value = event.index;
    });
  }

  @override
  int selectNamesFromFile(Iterable<String> names) {
    final wanted = names
        .map(
          (name) =>
              name.endsWith('\r') ? name.substring(0, name.length - 1) : name,
        )
        .map(
          (name) => name.startsWith(String.fromCharCode(0xFEFF))
              ? name.substring(1)
              : name,
        )
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

  @override
  void deselectAll() {
    selectedPaths.value = {};
  }

  @override
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

  /// Rubber-band result: [paths] is the complete resulting mark set to
  /// apply — a wholesale replace, not a delta — since the rubber-band layer
  /// already computed it as a snapshot-XOR-rectangle each frame. [additive]
  /// is ignored: the personal scheme never reads it (the rubber-band layer
  /// only takes that path under the upstream scheme).
  @override
  void onRectSelect(Set<String> paths, {bool additive = false}) {
    batch(() {
      selectedPaths.value = paths;
      if (paths.isNotEmpty) {
        final idx = _vf.indexWhere((f) => paths.contains(f.path));
        if (idx >= 0) cursorIndex.value = idx;
      }
    });
  }

  @override
  void onContextMenu(FileSelectionEvent event) {
    batch(() {
      if (!selectedPaths.value.contains(event.entry.path)) {
        selectedPaths.value = {event.entry.path};
      }
      cursorIndex.value = event.index;
    });
  }

  @override
  void jumpToIndex(int index) {
    batch(() {
      if (_vf.isEmpty) return;
      if (index < 0 || index >= _vf.length) return;
      cursorIndex.value = index;
      selectedPaths.value = {_vf[index].path};
    });
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

  @override
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

  @override
  void moveCursor(int delta, {bool isRepeat = false}) {
    final settings = SettingsStore.instance;
    final rowStep = AppShortcuts.isControl ? pageStep : 1;
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

  @override
  void moveCursorByPage(int dir, {bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    final current = _resolvedCursorIndex();
    if (current < 0) {
      _initCursor(dir > 0 ? 0 : _vf.length - 1);

      return;
    }
    final next = (current + dir * pageStep).clamp(0, _vf.length - 1);
    if (isRepeat && next == current) return;
    _applyCursorMove(next);
  }

  @override
  void moveCursorToStart({bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    if (cursorIndex.value < 0) {
      _initCursor(0);

      return;
    }
    if (isRepeat && cursorIndex.value == 0) return;
    _applyCursorMove(0);
  }

  @override
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

  /// Paint mode for the current Shift+move "session" — decided once, from
  /// whichever cell the cursor was on when a Shift+move session starts (the
  /// first Shift+move after a plain, unmodified move), and reused for every
  /// further Shift+move until a plain move ends the session. `true` = every
  /// cell in the swept range gets marked; `false` = every cell gets
  /// unmarked. Deliberately not per-keystroke: an origin-cell-only decision
  /// would punch holes wherever the swept range crosses an already-marked
  /// cell instead of painting a uniform run.
  bool? _keyboardPaintAdd;

  /// Plain move: cursor only, marks untouched (this also ends any in-progress
  /// paint session). Shift+move paints the range between the *old* cursor
  /// position and [next], excluding [next] itself (the destination cell is
  /// left to the cursor highlight to indicate, not double-encoded as a mark
  /// too) — unless the cursor couldn't actually move ([next] equals the old
  /// position), in which case the old position itself is painted, so a
  /// boundary Shift+move still changes exactly one item. Ctrl never changes
  /// which set operation this is — Ctrl only ever picks a bigger step,
  /// before this method is even called.
  void _applyCursorMove(int next) {
    final shift = AppShortcuts.isShift;
    if (!shift) _keyboardPaintAdd = null;
    batch(() {
      if (shift) {
        final cur = cursorIndex.value >= 0 && cursorIndex.value < _vf.length
            ? cursorIndex.value
            : next;
        final add = _keyboardPaintAdd ??= !selectedPaths.value.contains(
          _vf[cur].path,
        );
        final lo = cur < next ? cur : next;
        final hi = cur < next ? next : cur;
        final paths = Set<String>.from(selectedPaths.value);
        for (int i = lo; i <= hi; i++) {
          if (i == cur || i != next) {
            final p = _vf[i].path;
            if (add) {
              paths.add(p);
            } else {
              paths.remove(p);
            }
          }
        }
        selectedPaths.value = paths;
      }
      cursorIndex.value = next;
    });
  }
}

/// Reproduces `origin/main`'s classic anchor-based selection model, for
/// users who prefer it over [PersonalSelectionController]'s redesign.
/// Ported near-verbatim from upstream so its quirks (e.g. [_applyCursorMove]
/// reading `HardwareKeyboard` directly instead of [AppShortcuts], or a
/// Shift+move that extends the selection without moving the cursor when the
/// current cursor cell isn't marked) are preserved exactly, not "improved."
class UpstreamSelectionController extends SelectionController {
  UpstreamSelectionController({
    required super.selectedPaths,
    required super.cursorIndex,
    required super.anchorIndex,
    required super.gridColumns,
    required super.visibleFiles,
  });

  @override
  void onSelect(FileSelectionEvent event) {
    final ctrl = AppShortcuts.isControl;
    final shift = AppShortcuts.isShift;

    batch(() {
      if (ctrl && !shift) {
        final paths = Set<String>.from(selectedPaths.value);
        if (paths.contains(event.entry.path)) {
          paths.remove(event.entry.path);
          if (paths.isNotEmpty) {
            final lastSelected = _vf.lastWhere(
              (f) => paths.contains(f.path),
              orElse: () => event.entry,
            );
            anchorIndex.value = _vf.indexOf(lastSelected);
          } else {
            anchorIndex.value = -1;
          }
        } else {
          paths.add(event.entry.path);
          anchorIndex.value = event.index;
        }
        selectedPaths.value = paths;
        cursorIndex.value = event.index;
      } else if (shift && !ctrl) {
        int start;
        if (anchorIndex.value >= 0 &&
            anchorIndex.value < _vf.length &&
            selectedPaths.value.contains(_vf[anchorIndex.value].path)) {
          start = anchorIndex.value;
        } else if (cursorIndex.value >= 0 &&
            cursorIndex.value < _vf.length &&
            selectedPaths.value.contains(_vf[cursorIndex.value].path)) {
          start = cursorIndex.value;
          anchorIndex.value = start;
        } else {
          start = event.index;
          anchorIndex.value = event.index;
        }
        final end = event.index;
        final lo = start < end ? start : end;
        final hi = start < end ? end : start;
        final paths = <String>{};
        for (int i = lo; i <= hi; i++) {
          paths.add(_vf[i].path);
        }
        selectedPaths.value = paths;
        cursorIndex.value = event.index;
      } else {
        selectedPaths.value = {event.entry.path};
        cursorIndex.value = event.index;
        anchorIndex.value = event.index;
      }
    });
  }

  @override
  int selectNamesFromFile(Iterable<String> names) {
    final wanted = names
        .map(
          (name) =>
              name.endsWith('\r') ? name.substring(0, name.length - 1) : name,
        )
        .map(
          (name) => name.startsWith(String.fromCharCode(0xFEFF))
              ? name.substring(1)
              : name,
        )
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
      anchorIndex.value = cursor;
    });

    return matched.length;
  }

  @override
  void deselectAll() {
    batch(() {
      selectedPaths.value = {};
      cursorIndex.value = -1;
      anchorIndex.value = -1;
    });
  }

  @override
  void toggleSelectAndAdvance() {
    batch(() {
      if (cursorIndex.value >= 0 && cursorIndex.value < _vf.length) {
        final path = _vf[cursorIndex.value].path;
        final paths = Set<String>.from(selectedPaths.value);
        if (paths.contains(path) && paths.length > 1) {
          paths.remove(path);
        } else {
          paths.add(path);
        }
        selectedPaths.value = paths;
      }
      if (cursorIndex.value < _vf.length - 1) {
        cursorIndex.value++;
      }
    });
  }

  @override
  void onRectSelect(Set<String> paths, {bool additive = false}) {
    batch(() {
      if (additive) {
        selectedPaths.value = {...selectedPaths.value, ...paths};
      } else {
        selectedPaths.value = paths;
      }
      if (paths.isNotEmpty) {
        final idx = _vf.indexWhere((f) => paths.contains(f.path));
        if (idx >= 0) cursorIndex.value = idx;
      } else if (!additive) {
        cursorIndex.value = -1;
        anchorIndex.value = -1;
      }
    });
  }

  @override
  void onContextMenu(FileSelectionEvent event) {
    if (!selectedPaths.value.contains(event.entry.path)) {
      batch(() {
        selectedPaths.value = {event.entry.path};
        cursorIndex.value = event.index;
        anchorIndex.value = event.index;
      });
    }
  }

  @override
  void jumpToIndex(int index) {
    batch(() {
      if (_vf.isEmpty) return;
      if (index < 0 || index >= _vf.length) return;
      cursorIndex.value = index;
      anchorIndex.value = index;
      selectedPaths.value = {_vf[index].path};
    });
  }

  @override
  void moveCursorHorizontally(int delta, {bool isRepeat = false}) {
    final settings = SettingsStore.instance;
    if (settings.fileViewMode.value != 'grid') {
      moveCursor(delta);

      return;
    }
    if (_vf.isEmpty || delta == 0) return;
    if (cursorIndex.value < 0) {
      _initCursor(delta > 0 ? 0 : _vf.length - 1);

      return;
    }
    final columns = gridColumns.value.clamp(1, 1000);
    final col = cursorIndex.value % columns;
    if (delta < 0 && col == 0) return;
    if (delta > 0 && col == columns - 1) return;
    final next = cursorIndex.value + delta;
    if (next < 0 || next >= _vf.length) return;
    _applyCursorMove(next);
  }

  @override
  void moveCursor(int delta, {bool isRepeat = false}) {
    final settings = SettingsStore.instance;
    final step = settings.fileViewMode.value == 'grid' && delta.abs() == 1
        ? delta * gridColumns.value.clamp(1, 1000)
        : delta;
    if (_vf.isEmpty) return;
    if (cursorIndex.value < 0) {
      _initCursor(step > 0 ? 0 : _vf.length - 1);

      return;
    }
    final next = cursorIndex.value + step;
    if (next < 0 || next >= _vf.length) return;
    _applyCursorMove(next);
  }

  @override
  void moveCursorByPage(int dir, {bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    if (cursorIndex.value < 0) {
      _initCursor(dir > 0 ? 0 : _vf.length - 1);

      return;
    }
    final next = (cursorIndex.value + dir * pageStep).clamp(0, _vf.length - 1);
    if (next == cursorIndex.value) return;
    _applyCursorMove(next);
  }

  @override
  void moveCursorToStart({bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    if (cursorIndex.value < 0) {
      _initCursor(0);

      return;
    }
    _applyCursorMove(0);
  }

  @override
  void moveCursorToEnd({bool isRepeat = false}) {
    if (_vf.isEmpty) return;
    final last = _vf.length - 1;
    if (cursorIndex.value < 0) {
      _initCursor(last);

      return;
    }
    _applyCursorMove(last);
  }

  void _initCursor(int index) {
    batch(() {
      cursorIndex.value = index;
      anchorIndex.value = index;
      selectedPaths.value = {_vf[index].path};
    });
  }

  void _applyCursorMove(int next) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    batch(() {
      if (shift) {
        final anchor = anchorIndex.value >= 0 && anchorIndex.value < _vf.length
            ? anchorIndex.value
            : cursorIndex.value;
        final cur = cursorIndex.value;
        final extending = (next - anchor).abs() > (cur - anchor).abs();
        if (cur >= 0 &&
            cur < _vf.length &&
            !selectedPaths.value.contains(_vf[cur].path) &&
            extending) {
          final lo = cur < anchor ? cur : anchor;
          final hi = cur < anchor ? anchor : cur;
          final paths = Set<String>.from(selectedPaths.value);
          for (int i = lo; i <= hi; i++) {
            paths.add(_vf[i].path);
          }
          selectedPaths.value = paths;

          return;
        }
        final lo = next < anchor ? next : anchor;
        final hi = next < anchor ? anchor : next;
        final paths = <String>{};
        for (int i = lo; i <= hi; i++) {
          paths.add(_vf[i].path);
        }
        selectedPaths.value = paths;
      } else {
        selectedPaths.value = {_vf[next].path};
        anchorIndex.value = next;
      }
      cursorIndex.value = next;
    });
  }
}
