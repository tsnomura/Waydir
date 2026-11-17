import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waydir/ui/icons/waydir_icons.dart' show WaydirIconsRegular;
import 'package:signals/signals_flutter.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import '../../i18n/strings.g.dart';
import '../../core/fs/file_sort.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../core/settings/settings_store.dart';
import '../../ui/overlays/context_menu.dart';
import '../../ui/overlays/popup_overlay.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/motion.dart';
import '../../ui/widgets/app_spinner.dart';
import 'package:path/path.dart' as p;
import '../../utils/format.dart';
import 'cursor_tooltip.dart';
import 'file_icons.dart';
import 'file_item.dart';
import 'file_list_selection.dart';
import 'file_view_behavior.dart';
import 'path_ellipsis.dart';
import 'pointer_hover_store.dart';
import 'row_decorations.dart';
import 'rubber_band_layer.dart';
import 'scroll_link.dart';
import 'status_chip.dart';

part 'file_view/columns.dart';
part 'file_view/header.dart';
part 'file_view/row.dart';
part 'file_view/scrollbar.dart';

typedef FileSelectCallback = void Function(FileSelectionEvent event);
typedef FileOpenCallback = void Function(FileEntry entry);
typedef BackgroundTapCallback = void Function();
typedef BackgroundContextMenuCallback = void Function(Offset position);
typedef FileContextMenuCallback =
    void Function(FileSelectionEvent event, Offset position);
typedef FileMenuActionCallback = void Function(String action);
typedef FileDropCallback =
    void Function(List<String> paths, String destination, {bool move});
typedef RenameSubmitCallback = void Function(String newName);
typedef RenameCancelCallback = void Function();
typedef OpenInNewTabCallback = void Function(String path);

const _kRowHeightComfortable = 26.0;
const _kRowHeightCompact = 20.0;
const _kRowGapComfortable = 6.0;
const _kLocationWidth = 190.0;
const _kScrollbarThumbWidth = 6.0;
const _kScrollbarGutterWidth = _kScrollbarThumbWidth;
const _kRowPaddingLeft = 8.0;
const _kRowPaddingRight = 10.0;
const _kNameMinWidth = 160.0;
const _kNameManualDefaultWidth = 260.0;
const _kLocationMinWidth = 120.0;
const _kLocationMaxFraction = 0.4;
const _kColumnGap = 6.0;
const _kHeaderHeight = 24.0;
const _kResizeHandleWidth = 16.0;
const _kColumnWidthsNameKey = 'name';
const _kColumnWidthsLocationKey = 'location';
const _kTreeIndentWidth = 14.0;
const _kTreeDisclosureWidth = 18.0;

class _Memo<T> {
  List<Object?>? _deps;
  late T _value;

  T call(List<Object?> deps, T Function() compute) {
    final previous = _deps;
    if (previous != null && _sameDeps(previous, deps)) return _value;
    _deps = deps;

    return _value = compute();
  }

  static bool _sameDeps(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      if (x is List || x is Map || x is Set || x != y) return false;
    }

    return true;
  }
}

class FileList extends StatefulWidget {
  final List<FileEntry> files;
  final String currentPath;
  final FileSelectCallback onSelect;
  final FileOpenCallback onOpen;
  final BackgroundTapCallback? onBackgroundTap;
  final BackgroundContextMenuCallback? onBackgroundContextMenu;
  final FileContextMenuCallback? onContextMenu;
  final FileMenuActionCallback? onMenuAction;
  final FileDropCallback? onDropFiles;
  final FileListSelection? selection;
  final Set<String> cutPaths;
  final String? renamingPath;
  final int renameAttempt;
  final RenameSubmitCallback? onRenameSubmit;
  final RenameCancelCallback? onRenameCancel;
  final bool recursiveResults;
  final VoidCallback? onCloseSearch;
  final OpenInNewTabCallback? onOpenInNewTab;
  final OpenInNewTabCallback? onOpenInOtherPaneNewTab;
  final RubberBandSelectCallback? onRectSelect;
  final SortKey sortColumn;
  final bool sortAscending;
  final void Function(SortKey key)? onSortColumn;
  final ValueChanged<int>? onPageRows;
  final Map<String, int> folderSizes;
  final bool sizeBars;
  final Map<String, RowDecoration> rowDecorations;
  final bool showStatusColumn;
  final bool cursorTooltips;
  final List<FileTreeRow>? treeRows;
  final ValueChanged<FileEntry>? onToggleTreeFolder;
  final ScrollLink? scrollLink;

  const FileList({
    super.key,
    required this.files,
    required this.currentPath,
    this.scrollLink,
    this.folderSizes = const {},
    this.sizeBars = false,
    this.rowDecorations = const {},
    this.showStatusColumn = false,
    this.cursorTooltips = false,
    this.treeRows,
    this.onToggleTreeFolder,
    required this.onSelect,
    required this.onOpen,
    this.sortColumn = SortKey.name,
    this.sortAscending = true,
    this.onSortColumn,
    this.onBackgroundTap,
    this.onBackgroundContextMenu,
    this.onContextMenu,
    this.onMenuAction,
    this.onDropFiles,
    this.selection,
    this.cutPaths = const {},
    this.renamingPath,
    this.renameAttempt = 0,
    this.onRenameSubmit,
    this.onRenameCancel,
    this.recursiveResults = false,
    this.onCloseSearch,
    this.onOpenInNewTab,
    this.onOpenInOtherPaneNewTab,
    this.onRectSelect,
    this.onPageRows,
  });

  @override
  State<FileList> createState() => _FileListState();
}

class FileTree extends StatelessWidget {
  final List<FileTreeRow> rows;
  final String currentPath;
  final FileSelectCallback onSelect;
  final FileOpenCallback onOpen;
  final BackgroundTapCallback? onBackgroundTap;
  final BackgroundContextMenuCallback? onBackgroundContextMenu;
  final FileContextMenuCallback? onContextMenu;
  final FileMenuActionCallback? onMenuAction;
  final FileDropCallback? onDropFiles;
  final FileListSelection? selection;
  final Set<String> cutPaths;
  final String? renamingPath;
  final int renameAttempt;
  final RenameSubmitCallback? onRenameSubmit;
  final RenameCancelCallback? onRenameCancel;
  final VoidCallback? onCloseSearch;
  final OpenInNewTabCallback? onOpenInNewTab;
  final OpenInNewTabCallback? onOpenInOtherPaneNewTab;
  final RubberBandSelectCallback? onRectSelect;
  final SortKey sortColumn;
  final bool sortAscending;
  final void Function(SortKey key)? onSortColumn;
  final ValueChanged<int>? onPageRows;
  final Map<String, int> folderSizes;
  final bool sizeBars;
  final Map<String, RowDecoration> rowDecorations;
  final bool showStatusColumn;
  final bool cursorTooltips;
  final ValueChanged<FileEntry> onToggleFolder;
  final ScrollLink? scrollLink;
  final bool recursiveResults;

  const FileTree({
    super.key,
    required this.rows,
    required this.currentPath,
    this.scrollLink,
    required this.onSelect,
    required this.onOpen,
    required this.onToggleFolder,
    this.folderSizes = const {},
    this.sizeBars = false,
    this.rowDecorations = const {},
    this.showStatusColumn = false,
    this.cursorTooltips = false,
    this.sortColumn = SortKey.name,
    this.sortAscending = true,
    this.onSortColumn,
    this.onBackgroundTap,
    this.onBackgroundContextMenu,
    this.onContextMenu,
    this.onMenuAction,
    this.onDropFiles,
    this.selection,
    this.cutPaths = const {},
    this.renamingPath,
    this.renameAttempt = 0,
    this.onRenameSubmit,
    this.onRenameCancel,
    this.onCloseSearch,
    this.onOpenInNewTab,
    this.onOpenInOtherPaneNewTab,
    this.onRectSelect,
    this.onPageRows,
    this.recursiveResults = false,
  });

  @override
  Widget build(BuildContext context) {
    return FileList(
      files: const [],
      treeRows: rows,
      currentPath: currentPath,
      recursiveResults: recursiveResults,
      onSelect: onSelect,
      onOpen: onOpen,
      onToggleTreeFolder: onToggleFolder,
      onBackgroundTap: onBackgroundTap,
      onBackgroundContextMenu: onBackgroundContextMenu,
      onContextMenu: onContextMenu,
      onMenuAction: onMenuAction,
      onDropFiles: onDropFiles,
      selection: selection,
      cutPaths: cutPaths,
      renamingPath: renamingPath,
      renameAttempt: renameAttempt,
      onRenameSubmit: onRenameSubmit,
      onRenameCancel: onRenameCancel,
      onCloseSearch: onCloseSearch,
      onOpenInNewTab: onOpenInNewTab,
      onOpenInOtherPaneNewTab: onOpenInOtherPaneNewTab,
      onRectSelect: onRectSelect,
      sortColumn: sortColumn,
      sortAscending: sortAscending,
      onSortColumn: onSortColumn,
      onPageRows: onPageRows,
      folderSizes: folderSizes,
      sizeBars: sizeBars,
      rowDecorations: rowDecorations,
      showStatusColumn: showStatusColumn,
      cursorTooltips: cursorTooltips,
      scrollLink: scrollLink,
    );
  }
}

class _FileListState extends State<FileList>
    with ScrollLinkBinding, FileViewBehavior<FileList> {
  @override
  ScrollController get linkedScrollController => _scrollController;

  @override
  ScrollLink? get scrollLink => widget.scrollLink;

  @override
  String get scrollMemoryKey => 'list|${widget.currentPath}';

  @override
  void initState() {
    super.initState();
    initScrollLink();
    _scrollController.addListener(_reportCursorRow);
    watchCursor();
  }

  @override
  void didUpdateWidget(covariant FileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateScrollLink();
    if (oldWidget.currentPath != widget.currentPath) {
      switchScrollMemory('list|${oldWidget.currentPath}');
    }
    if (!identical(oldWidget.selection, widget.selection)) watchCursor();
  }

  FileListSelection get _selection =>
      widget.selection ?? FileListSelection.none;

  @override
  FileListSelection get viewSelection => _selection;

  @override
  void revealCursor() => _revealSelectedRow();

  @override
  void reportCursorRow() => _reportCursorRow();

  FileEntry? _entryAt(Offset localPosition) {
    final index = _rowAt(localPosition);

    return index < 0 ? null : _displayFiles[index];
  }

  late final _scrollController = ScrollController(
    initialScrollOffset: widget.scrollLink?.offsetFor(scrollMemoryKey) ?? 0,
  );
  final _hScrollController = ScrollController();
  double _contentWidth = 0;
  double _rowH = _kRowHeightComfortable;
  double _rowG = _kRowGapComfortable;
  double _itemExt = _kRowHeightComfortable + _kRowGapComfortable;
  double _listHorizontalSpacing = _kRowGapComfortable;
  double _viewportWidth = 0;
  Map<String, double> _shownColumnWidths = const {};
  String _dateFmt = 'locale';
  bool _recentDatesRelative = true;
  String? _lastRevealedKey;
  int _lastReportedRows = -1;

  double get _listTopPadding => _rowG;
  double get _listHorizontalPadding => _listHorizontalSpacing;
  final _displayFilesMemo = _Memo<List<FileEntry>>();
  final _markFractionsMemo = _Memo<List<double>>();
  final _columnWidthsMemo = _Memo<Map<FileColumn, double>>();
  final _maxItemSizeMemo = _Memo<int>();
  final _maxTreeDepthMemo = _Memo<int>();
  final _hasBadgeMemo = _Memo<bool>();
  final _locationWantedMemo = _Memo<double>();

  List<FileEntry> get _displayFiles {
    final rows = widget.treeRows;
    if (rows == null) return widget.files;

    return _displayFilesMemo([
      rows,
      rows.length,
    ], () => [for (final row in rows) row.entry]);
  }

  List<double> _markFractions(List<FileEntry> files, Set<String> selected) {
    if (selected.isEmpty || files.isEmpty) return const [];

    return _markFractionsMemo(
      [files, files.length, selected, selected.length],
      () => [
        for (var i = 0; i < files.length; i++)
          if (selected.contains(files[i].path)) (i + 0.5) / files.length,
      ],
    );
  }

  int _maxItemSize(List<FileEntry> files) {
    if (!widget.sizeBars) return 0;

    return _maxItemSizeMemo([
      files,
      files.length,
      widget.folderSizes,
      widget.folderSizes.length,
    ], () => files.fold<int>(0, (max, e) => math.max(max, _itemSize(e))));
  }

  int _maxTreeDepth() {
    final rows = widget.treeRows;
    if (rows == null) return 0;

    return _maxTreeDepthMemo(
      [rows, rows.length],
      () => rows.fold<int>(0, (max, row) => row.depth > max ? row.depth : max),
    );
  }

  bool _hasStatusBadge() {
    final decorations = widget.rowDecorations;
    if (decorations.isEmpty) return false;

    return _hasBadgeMemo([
      decorations,
      decorations.length,
    ], () => decorations.values.any((d) => d.badge != null));
  }

  int get _relativeDateBucket {
    final relative =
        _dateFmt == 'relative' ||
        (_dateFmt == 'locale' && _recentDatesRelative);

    return relative ? DateTime.now().millisecondsSinceEpoch ~/ 60000 : 0;
  }

  int _itemSize(FileEntry e) => e.type == FileItemType.folder
      ? widget.folderSizes[e.realPath] ?? 0
      : e.size;

  double _measureWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.noScaling,
    )..layout();

    return tp.width;
  }

  List<FileColumn> _visibleColumns() => [
    for (final col in orderedColumns())
      if (fileColumnSignal(col).value) col,
  ];

  Map<FileColumn, double> _computeColumnWidths(
    BuildContext context,
    List<FileColumn> columns,
    List<FileEntry> files,
  ) {
    final muted = context.txt.muted;
    final headerStyle = context.txt.fieldLabel;
    final folderSizes = widget.folderSizes;

    return _columnWidthsMemo(
      [
        files,
        files.length,
        columns.map((c) => c.name).join(','),
        _dateFmt,
        _recentDatesRelative,
        _relativeDateBucket,
        columns.contains(FileColumn.size) ? folderSizes : null,
        folderSizes.length,
        muted,
        headerStyle,
        t,
      ],
      () {
        final widths = <FileColumn, double>{};
        for (final col in columns) {
          var longest = fileColumnLabel(col);
          for (final e in files) {
            final v = fileColumnText(
              col,
              e,
              dateFmt: _dateFmt,
              recentDatesRelative: _recentDatesRelative,
              folderSize: folderSizes[e.realPath],
            );
            if (v.length > longest.length) longest = v;
          }
          final cellW = _measureWidth(longest, muted);
          final headerW = _measureWidth(fileColumnLabel(col), headerStyle) + 14;
          widths[col] = math.max(cellW, headerW).ceilToDouble() + 8;
        }

        return widths;
      },
    );
  }

  double _persistedColumnWidth(
    Map<String, double> persisted,
    String key,
    double fallback,
  ) {
    final min = minColumnWidth(key);
    final saved = persisted[key];
    if (saved == null || !saved.isFinite) return math.max(min, fallback);

    return math.max(min, saved);
  }

  void _resizeColumn(String key, double delta) {
    if (delta == 0) return;
    final settings = SettingsStore.instance;
    final widths = Map<String, double>.of(
      parseColumnWidths(settings.columnWidths.value),
    );
    final shown = settings.columnWidthMode.value == 'resizableAutomatic'
        ? _shownColumnWidths[key]
        : null;
    final current =
        shown ??
        _persistedColumnWidth(
          widths,
          key,
          key == _kColumnWidthsNameKey
              ? _kNameManualDefaultWidth
              : key == _kColumnWidthsLocationKey
              ? _kLocationWidth
              : minColumnWidth(key),
        );
    widths[key] = math.max(minColumnWidth(key), current + delta);
    settings.columnWidths.value = columnWidthsToString(widths);
  }

  void _autoFitColumn(String key) {
    final settings = SettingsStore.instance;
    final widths = Map<String, double>.of(
      parseColumnWidths(settings.columnWidths.value),
    );
    if (key == _kColumnWidthsNameKey) {
      widths[key] = _fitNameWidth();
    } else {
      widths.remove(key);
    }
    settings.columnWidths.value = columnWidthsToString(widths);
  }

  void _resetColumnWidths() {
    SettingsStore.instance.columnWidths.value = columnWidthsToString(const {});
  }

  double _fitNameWidth() {
    var longest = '';
    for (final e in _displayFiles) {
      if (e.name.length > longest.length) longest = e.name;
    }
    final dots = widget.rowDecorations.values.fold<int>(
      0,
      (max, d) => math.max(max, d.badgeColors.length),
    );
    final dotsWidth = dots == 0 ? 0.0 : 6.0 + dots * 10;
    final width = _measureWidth(longest, context.txt.bodyEmphasis) + dotsWidth;

    return math.max(_kNameMinWidth, width.ceilToDouble() + 8);
  }

  void _openColumnMenu(BuildContext context, Offset position) {
    showPopup(
      context: context,
      position: position,
      width: 230,
      builder: (_) => const _ColumnConfigMenu(),
    );
  }

  String? _relativeParent(String entryPath, String currentPath) {
    final rel = p.relative(p.dirname(entryPath), from: currentPath);
    if (rel == '.') return null;

    return rel;
  }

  double _automaticLocationWidth(
    BuildContext context,
    List<FileEntry> files,
    double room,
  ) {
    final muted = context.txt.muted;
    final currentPath = widget.currentPath;
    final wanted = _locationWantedMemo(
      [files, files.length, currentPath, muted],
      () {
        var longest = '';
        for (final e in files) {
          final rel = _relativeParent(e.path, currentPath);
          if (rel != null && rel.length > longest.length) longest = rel;
        }

        return _measureWidth(longest, muted) + 8 + 8;
      },
    );
    final cap = math.max(
      _kLocationMinWidth,
      math.min(_viewportWidth * _kLocationMaxFraction, room),
    );

    return wanted.clamp(_kLocationMinWidth, cap).ceilToDouble();
  }

  int _rowAt(Offset localPosition) {
    if (localPosition.dy < 0 || localPosition.dx < _listHorizontalPadding) {
      return -1;
    }
    final rightEdge = _contentWidth - _listHorizontalPadding;
    if (_contentWidth > 0 && localPosition.dx >= rightEdge) return -1;

    final adjustedY =
        localPosition.dy + _scrollController.offset - _listTopPadding;
    if (adjustedY < 0) return -1;
    final index = (adjustedY / _itemExt).floor();
    if (index < 0 || index >= _displayFiles.length) return -1;

    final relativeY = adjustedY % _itemExt;
    if (relativeY >= _rowH) return -1;

    return index;
  }

  bool _canStartRubberBandAt(Offset localPosition) {
    if (_contentWidth <= 0) return true;

    return localPosition.dx < _contentWidth - _listHorizontalPadding;
  }

  double? _cursorRowTop() {
    final index = _selection.cursorIndex.peek();
    if (index < 0 || index >= _displayFiles.length) return null;

    return _listTopPadding + index * _itemExt;
  }

  void _reportCursorRow() {
    final top = _cursorRowTop();
    if (top == null || !_scrollController.hasClients || _itemExt <= 0) return;
    widget.scrollLink?.reportCursorRow(
      widget.currentPath,
      (top - _scrollController.offset) / _itemExt,
    );
  }

  int _revealIndex(List<FileEntry> files) {
    final renaming = widget.renamingPath;
    if (renaming != null) {
      final index = files.indexWhere((f) => f.path == renaming);
      if (index >= 0) return index;
    }

    return _selection.cursorIndex.peek();
  }

  void _revealSelectedRow() {
    final files = _displayFiles;
    final index = _revealIndex(files);
    if (index < 0 || index >= files.length) return;
    final key = '$index:${files[index].path}';
    final restoreRow = widget.renamingPath == null
        ? widget.scrollLink?.takeCursorRow(widget.currentPath)
        : null;
    if (restoreRow != null) {
      _lastRevealedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final top = _cursorRowTop();
        if (!mounted || !_scrollController.hasClients || top == null) return;
        final position = _scrollController.position;
        _scrollController.jumpTo(
          (top - restoreRow * _itemExt).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      });

      return;
    }
    if (key == _lastRevealedKey) return;
    _lastRevealedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      final top = _listTopPadding + index * _itemExt;
      final bottom = top + _rowH;
      final current = _scrollController.offset;
      final target = top < current
          ? top
          : bottom > current + viewport
          ? bottom - viewport
          : current;
      if (target == current) return;
      final clamped = target.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      if (context.reduceMotion) {
        _scrollController.jumpTo(clamped);
      } else {
        _scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _reportPageRows() {
    if (widget.onPageRows == null || !_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    if (viewport <= 0 || _itemExt <= 0) return;
    final rows = (viewport / _itemExt).floor().clamp(1, 1 << 20);
    if (rows == _lastReportedRows) return;
    _lastReportedRows = rows;
    widget.onPageRows!(rows);
  }

  @override
  void dispose() {
    stopWatchingCursor();
    disposeScrollLink();
    _scrollController.removeListener(_reportCursorRow);
    _scrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final density = SettingsStore.instance.rowDensity.value;
        final horizontalSpacing =
            SettingsStore.instance.fileListHorizontalSpacing.value;
        final verticalSpacing =
            SettingsStore.instance.fileListVerticalSpacing.value;
        _dateFmt = SettingsStore.instance.dateFormat.value;
        _recentDatesRelative = SettingsStore.instance.recentDatesRelative.value;
        _rowH = density == 'compact'
            ? _kRowHeightCompact
            : _kRowHeightComfortable;
        _rowG = verticalSpacing.toDouble();
        _listHorizontalSpacing = horizontalSpacing.toDouble();
        _itemExt = _rowH + _rowG;
        _revealSelectedRow();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _reportPageRows();
          _reportCursorRow();
        });

        final displayFiles = _displayFiles;
        final columns = _visibleColumns();
        final automaticColumnWidths = _computeColumnWidths(
          context,
          columns,
          displayFiles,
        );
        final columnWidthMode = SettingsStore.instance.columnWidthMode.value;
        final resizableAutomatic = columnWidthMode == 'resizableAutomatic';
        final resizableColumns =
            resizableAutomatic || columnWidthMode == 'resizable';
        final persistedColumnWidths = parseColumnWidths(
          SettingsStore.instance.columnWidths.value,
        );
        final recursive = widget.recursiveResults;
        final maxItemSize = _maxItemSize(displayFiles);
        final maxTreeDepth = _maxTreeDepth();
        final hasStatusBadge = _hasStatusBadge();

        return LayoutBuilder(
          builder: (context, constraints) {
            _viewportWidth = constraints.maxWidth;

            final treeLeading = widget.treeRows == null
                ? 0.0
                : maxTreeDepth * _kTreeIndentWidth + _kTreeDisclosureWidth;
            final showStatus = widget.showStatusColumn || hasStatusBadge;
            final statusSlot = showStatus ? 16.0 + 6 : 0.0;
            final iconSlot = statusSlot + 16.0 + 6 + treeLeading;
            final rowChrome =
                _listHorizontalPadding * 2 +
                _kScrollbarGutterWidth +
                _kRowPaddingLeft +
                _kRowPaddingRight;
            final automaticOptionalCols = columns.fold<double>(
              0,
              (sum, col) => sum + automaticColumnWidths[col]! + _kColumnGap,
            );
            final automaticLocationWidth = recursive
                ? _automaticLocationWidth(
                    context,
                    displayFiles,
                    _viewportWidth -
                        rowChrome -
                        iconSlot -
                        automaticOptionalCols -
                        _kNameMinWidth -
                        _kColumnGap,
                  )
                : _kLocationWidth;
            final automaticFixedCols =
                iconSlot +
                automaticOptionalCols +
                (recursive ? automaticLocationWidth + _kColumnGap : 0);
            final automaticAvailable =
                _viewportWidth - rowChrome - automaticFixedCols;
            final automaticNameWidth = math.max(
              _kNameMinWidth,
              automaticAvailable,
            );
            final locationWidth = resizableColumns
                ? _persistedColumnWidth(
                    persistedColumnWidths,
                    _kColumnWidthsLocationKey,
                    resizableAutomatic
                        ? automaticLocationWidth
                        : _kLocationWidth,
                  )
                : automaticLocationWidth;
            final columnWidths = resizableColumns
                ? {
                    for (final col in columns)
                      col: _persistedColumnWidth(
                        persistedColumnWidths,
                        columnWidthKey(col),
                        automaticColumnWidths[col]!,
                      ),
                  }
                : automaticColumnWidths;
            final optionalCols = columns.fold<double>(
              0,
              (sum, col) => sum + columnWidths[col]! + _kColumnGap,
            );
            final fixedCols =
                iconSlot +
                optionalCols +
                (recursive ? locationWidth + _kColumnGap : 0);
            final remainingNameWidth = math.max(
              _kNameMinWidth,
              _viewportWidth - rowChrome - fixedCols,
            );
            final fallbackNameWidth = resizableAutomatic
                ? remainingNameWidth
                : automaticNameWidth;
            final nameWidth = resizableColumns
                ? _persistedColumnWidth(
                    persistedColumnWidths,
                    _kColumnWidthsNameKey,
                    fallbackNameWidth.isFinite
                        ? fallbackNameWidth
                        : _kNameManualDefaultWidth,
                  )
                : automaticNameWidth;
            _shownColumnWidths = {
              _kColumnWidthsNameKey: nameWidth,
              _kColumnWidthsLocationKey: locationWidth,
              for (final col in columns)
                columnWidthKey(col): columnWidths[col]!,
            };
            _contentWidth = nameWidth + fixedCols + rowChrome;
            final bodyWidth = math.max(_contentWidth, _viewportWidth);

            return Stack(
              children: [
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: RawScrollbar(
                    controller: _hScrollController,
                    thumbVisibility: bodyWidth > _viewportWidth,
                    thumbColor: AppColors.fgSubtle,
                    thickness: _kScrollbarThumbWidth,
                    crossAxisMargin: 0,
                    radius: Radius.zero,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _hScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: bodyWidth,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _ListHeader(
                                    recursive: recursive,
                                    leadingWidth: iconSlot,
                                    nameWidth: nameWidth,
                                    locationWidth: locationWidth,
                                    columns: columns,
                                    columnWidths: columnWidths,
                                    resizable: resizableColumns,
                                    sortColumn: widget.sortColumn,
                                    sortAscending: widget.sortAscending,
                                    onSortColumn: widget.onSortColumn,
                                    onResizeColumn: _resizeColumn,
                                    onAutoFitColumn: resizableAutomatic
                                        ? _autoFitColumn
                                        : null,
                                    onResetColumns: resizableAutomatic
                                        ? _resetColumnWidths
                                        : null,
                                    onConfigureColumns: (pos) =>
                                        _openColumnMenu(context, pos),
                                  ),
                                ),
                                SizedBox(
                                  width: _kScrollbarGutterWidth,
                                  height: 24,
                                  child: ColoredBox(color: AppColors.bg),
                                ),
                              ],
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.bgDivider,
                            ),
                            Expanded(
                              child: RubberBandLayer(
                                scrollController: _scrollController,
                                itemCount: displayFiles.length,
                                itemExtent: _itemExt,
                                rowHeight: _rowH,
                                topPadding: _listTopPadding,
                                pathAt: (i) => displayFiles[i].path,
                                rowAt: _rowAt,
                                canStartSelectionAt: _canStartRubberBandAt,
                                onSelectionChanged: widget.onRectSelect,
                                currentSelection: _selection.selectedPaths.peek,
                                onBackgroundTap: widget.onBackgroundTap,
                                child: buildDropRegion(
                                  entryAt: _entryAt,
                                  currentPath: () => widget.currentPath,
                                  onDropFiles: () => widget.onDropFiles,
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: GestureDetector(
                                      onSecondaryTapUp: (d) {
                                        final index = _rowAt(d.localPosition);
                                        if (index < 0) {
                                          widget.onBackgroundTap?.call();
                                          widget.onBackgroundContextMenu?.call(
                                            d.globalPosition,
                                          );
                                        }
                                      },
                                      behavior: HitTestBehavior.translucent,
                                      child: MediaQuery.withClampedTextScaling(
                                        minScaleFactor: 1,
                                        maxScaleFactor: 1,
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          padding: EdgeInsets.only(
                                            left: _listHorizontalPadding,
                                            top: _listTopPadding,
                                            right:
                                                _listHorizontalPadding +
                                                _kScrollbarGutterWidth,
                                          ),
                                          itemCount: displayFiles.length,
                                          itemExtent: _itemExt,
                                          addAutomaticKeepAlives: false,
                                          addRepaintBoundaries: false,
                                          addSemanticIndexes: false,
                                          itemBuilder: (context, i) => RepaintBoundary(
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                bottom: _rowG,
                                              ),
                                              child: _ListRow(
                                                rowHeight: _rowH,
                                                iconSize: 16.0,
                                                dateFmt: _dateFmt,
                                                recentDatesRelative:
                                                    _recentDatesRelative,
                                                entry: displayFiles[i],
                                                folderSize:
                                                    widget
                                                        .folderSizes[displayFiles[i]
                                                        .realPath],
                                                sizeFraction: maxItemSize == 0
                                                    ? 0
                                                    : _itemSize(
                                                            displayFiles[i],
                                                          ) /
                                                          maxItemSize,
                                                rowDecoration:
                                                    widget
                                                        .rowDecorations[displayFiles[i]
                                                        .path] ??
                                                    widget
                                                        .rowDecorations[displayFiles[i]
                                                        .realPath],
                                                index: i,
                                                nameWidth: nameWidth,
                                                locationWidth: locationWidth,
                                                selection: _selection,
                                                cursorTooltips:
                                                    widget.cursorTooltips,
                                                isCut: widget.cutPaths.contains(
                                                  displayFiles[i].path,
                                                ),
                                                isFolderDragOver:
                                                    hoveredFolderPath ==
                                                    displayFiles[i].path,
                                                isRenaming:
                                                    widget.renamingPath ==
                                                    displayFiles[i].path,
                                                renameAttempt:
                                                    widget.renameAttempt,
                                                onRenameSubmit:
                                                    widget.onRenameSubmit,
                                                onRenameCancel:
                                                    widget.onRenameCancel,
                                                onSelect: widget.onSelect,
                                                onOpen: widget.onOpen,
                                                onContextMenu:
                                                    widget.onContextMenu,
                                                onMenuAction:
                                                    widget.onMenuAction,
                                                recursive: recursive,
                                                showStatus: showStatus,
                                                treeMode:
                                                    widget.treeRows != null,
                                                treeDepth:
                                                    widget.treeRows?[i].depth ??
                                                    0,
                                                treeExpanded:
                                                    widget
                                                        .treeRows?[i]
                                                        .expanded ??
                                                    false,
                                                treeLoading:
                                                    widget
                                                        .treeRows?[i]
                                                        .loading ??
                                                    false,
                                                onToggleTree:
                                                    widget.onToggleTreeFolder ==
                                                        null
                                                    ? null
                                                    : () =>
                                                          widget
                                                              .onToggleTreeFolder!(
                                                            displayFiles[i],
                                                          ),
                                                columns: columns,
                                                columnWidths: columnWidths,
                                                location: recursive
                                                    ? _relativeParent(
                                                        displayFiles[i].path,
                                                        widget.currentPath,
                                                      )
                                                    : null,
                                                onOpenInNewTab:
                                                    widget.onOpenInNewTab,
                                                onOpenInOtherPaneNewTab: widget
                                                    .onOpenInOtherPaneNewTab,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: _kHeaderHeight + 1,
                  right: 0,
                  bottom: 0,
                  width: _kScrollbarGutterWidth,
                  child: SignalBuilder(
                    builder: (_) => _PinnedVerticalScrollbar(
                      controller: _scrollController,
                      marks: _markFractions(
                        displayFiles,
                        _selection.selectedPaths.value,
                      ),
                    ),
                  ),
                ),
                if (displayFiles.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !widget.recursiveResults,
                      child: ColoredBox(
                        color: AppColors.bg,
                        child: _EmptyState(
                          isSearching: widget.recursiveResults,
                          onCloseSearch: widget.onCloseSearch,
                        ),
                      ),
                    ),
                  ),
                if (isDragOver)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.4),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback? onCloseSearch;

  const _EmptyState({this.isSearching = false, this.onCloseSearch});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: null,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              WaydirIconsRegular.folderOpen,
              size: 48,
              color: AppColors.fgSubtle,
            ),
            const SizedBox(height: 12),
            if (isSearching) ...[
              Text(
                t.search.noMatches,
                style: context.txt.dialogTitle.copyWith(
                  color: AppColors.fgMuted,
                ),
              ),
              const SizedBox(height: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onCloseSearch,
                  child: Text(
                    t.search.clear,
                    style: context.txt.body.copyWith(
                      color: AppColors.accent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ] else
              Text(
                t.fileView.empty,
                style: context.txt.dialogTitle.copyWith(
                  color: AppColors.fgMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
