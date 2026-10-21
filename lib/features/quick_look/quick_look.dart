import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../core/settings/settings_store.dart';
import '../../features/navigation/navigation_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'code_editor.dart';
import 'diff/diff_runner.dart';
import 'generators/generator_page_controller.dart';
import 'info_panel.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';
import 'quick_look_pop_out.dart';
import 'quick_look_reload.dart';

typedef QuickLookDiffResolver =
    (FileEntry, FileEntry)? Function(FileEntry? entry);

typedef QuickLookOpenMenu =
    void Function(FileEntry entry, Offset position, VoidCallback done);

Future<void> showQuickLook({
  required BuildContext context,
  required NavigationStore store,
  FileEntry? explicitEntry,
  QuickLookDiffResolver? diffPair,
  bool useMarkedSelection = false,
  QuickLookOpenMenu? onOpenMenu,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: t.quickLook.title,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 110),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _QuickLook(
        store: store,
        explicitEntry: explicitEntry,
        diffPair: diffPair,
        useMarkedSelection: useMarkedSelection,
        onOpenMenu: onOpenMenu,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _QuickLook extends StatefulWidget {
  final NavigationStore store;
  final FileEntry? explicitEntry;
  final QuickLookDiffResolver? diffPair;
  final bool useMarkedSelection;
  final QuickLookOpenMenu? onOpenMenu;

  const _QuickLook({
    required this.store,
    this.explicitEntry,
    this.diffPair,
    this.useMarkedSelection = false,
    this.onOpenMenu,
  });

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

enum _ResizeEdge { n, s, e, w, ne, nw, se, sw }

const double _kMinWindowWidth = 420;
const double _kMinWindowHeight = 320;

class _QuickLookState extends State<_QuickLook> with WidgetsBindingObserver {
  final _focus = FocusNode();
  final _editorActive = signal(false);
  final _identicalPairs = signal<Set<String>>(const {});
  FileEntry? _shownEntry;
  final _editorController = CodeEditorController();
  final _contentScroll = ScrollController();
  final _generatorPage = GeneratorPageController();
  final _playback = QuickLookPlaybackController();
  bool _compact = true;
  bool _showInfo = true;
  bool _markdownRendered = true;
  String? _presentationKey;
  FileChangeWatcher? _watcher;
  int _reloadGen = 0;
  FileEntry? _freshEntry;
  DateTime? _lastCursorRepeatAt;
  Rect? _rect;
  Offset? _dragAnchor;
  Rect? _dragStartRect;

  static const _cursorRepeatInterval = Duration(milliseconds: 70);

  /// Centers the window in [screen] — wider by default when opened as a
  /// compare-mode diff, since a side-by-side diff needs more room than a
  /// normal single-file preview.
  Rect _initialRect(Size screen) {
    final isDiff =
        widget.diffPair?.call(
          widget.explicitEntry ?? widget.store.cursorEntry.value,
        ) !=
        null;
    final width = _clampSize(
      screen.width * (isDiff ? 0.92 : 0.7),
      _kMinWindowWidth,
      isDiff ? 1600.0 : 1100.0,
    );
    final height = _clampSize(screen.height * 0.78, _kMinWindowHeight, 900.0);
    final originX = (screen.width - width) / 2;
    final originY = (screen.height - height) / 2;

    return _clampToScreen(
      Rect.fromLTWH(originX, originY, width, height),
      screen,
    );
  }

  static double _clampSize(double value, double min, double max) {
    if (max < min) return min;

    return value.clamp(min, max);
  }

  Rect _clampToScreen(Rect rect, Size screen) {
    final width = rect.width.clamp(
      _kMinWindowWidth,
      screen.width.clamp(_kMinWindowWidth, double.infinity),
    );
    final height = rect.height.clamp(
      _kMinWindowHeight,
      screen.height.clamp(_kMinWindowHeight, double.infinity),
    );
    final left = rect.left.clamp(
      0.0,
      (screen.width - width).clamp(0.0, screen.width),
    );
    final top = rect.top.clamp(
      0.0,
      (screen.height - height).clamp(0.0, screen.height),
    );

    return Rect.fromLTWH(left, top, width, height);
  }

  void _handleDragStart(DragStartDetails details) {
    _dragAnchor = details.globalPosition;
    _dragStartRect = _rect;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor;
    final startRect = _dragStartRect;
    if (anchor == null || startRect == null) return;
    final delta = details.globalPosition - anchor;
    final screen = MediaQuery.of(context).size;
    setState(() {
      _rect = _clampToScreen(startRect.shift(delta), screen);
    });
  }

  void _handleResizeStart(DragStartDetails details) {
    _dragAnchor = details.globalPosition;
    _dragStartRect = _rect;
  }

  void _handleResizeUpdate(_ResizeEdge edge, DragUpdateDetails details) {
    final anchor = _dragAnchor;
    final startRect = _dragStartRect;
    if (anchor == null || startRect == null) return;
    final delta = details.globalPosition - anchor;
    final screen = MediaQuery.of(context).size;
    setState(() {
      _rect = _resize(startRect, edge, delta, screen);
    });
  }

  static Rect _resize(Rect start, _ResizeEdge edge, Offset delta, Size screen) {
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;
    const west = {_ResizeEdge.w, _ResizeEdge.nw, _ResizeEdge.sw};
    const east = {_ResizeEdge.e, _ResizeEdge.ne, _ResizeEdge.se};
    const north = {_ResizeEdge.n, _ResizeEdge.nw, _ResizeEdge.ne};
    const south = {_ResizeEdge.s, _ResizeEdge.sw, _ResizeEdge.se};
    if (west.contains(edge)) left += delta.dx;
    if (east.contains(edge)) right += delta.dx;
    if (north.contains(edge)) top += delta.dy;
    if (south.contains(edge)) bottom += delta.dy;
    if (right - left < _kMinWindowWidth) {
      if (west.contains(edge)) {
        left = right - _kMinWindowWidth;
      } else {
        right = left + _kMinWindowWidth;
      }
    }
    if (bottom - top < _kMinWindowHeight) {
      if (north.contains(edge)) {
        top = bottom - _kMinWindowHeight;
      } else {
        bottom = top + _kMinWindowHeight;
      }
    }
    left = left.clamp(0.0, screen.width - _kMinWindowWidth);
    top = top.clamp(0.0, screen.height - _kMinWindowHeight);
    right = right.clamp(left + _kMinWindowWidth, screen.width);
    bottom = bottom.clamp(top + _kMinWindowHeight, screen.height);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    _editorController.onSaved = _onEditorSaved;
    final cursor = widget.store.cursorEntry.value;
    final entry = cursor?.ghostOf ?? cursor;
    _compact = defaultCompactFor(entry);
    _presentationKey = entry?.realPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watcher?.stop();
    _playback.dispose();
    _focus.dispose();
    _editorActive.dispose();
    _editorController.dispose();
    _contentScroll.dispose();
    _generatorPage.dispose();
    super.dispose();
  }

  /// Stops audio playback the moment Waydir loses focus or is minimized —
  /// Quick Look is for browsing with sound, not for leaving something
  /// playing in the background. It never auto-resumes on its own; moving
  /// the cursor or paging again picks playback back up as usual.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _playback.stopForLifecycle();
  }

  /// Closes the preview, prompting first when the editor has unsaved changes.
  Future<void> _requestClose() async {
    if (!_editorController.dirty.value) {
      Navigator.of(context).pop();

      return;
    }
    final result = await showCustomDialog<String>(
      context: context,
      title: t.quickLook.unsavedTitle,
      icon: WaydirIconsRegular.warning,
      iconColor: AppColors.warning,
      body: Text(
        t.quickLook.unsavedMessage,
        style: context.txt.row.copyWith(color: AppColors.fg),
      ),
      actions: [
        DialogAction(label: t.quickLook.cancel, color: AppColors.fgMuted),
        DialogAction(label: t.quickLook.discard, color: AppColors.danger),
        DialogAction(label: t.quickLook.save, color: AppColors.accent),
      ],
    );
    if (!mounted || result == null || result == t.quickLook.cancel) return;
    if (result == t.quickLook.save && !await _editorController.save()) {
      return; // save failed - keep the preview open
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _syncWatch(FileEntry? entry) {
    final watchable =
        entry != null &&
        entry.type == FileItemType.file &&
        !PlatformPaths.isRemoteUri(entry.realPath) &&
        widget.diffPair?.call(entry) == null;
    if (!watchable) {
      _watcher?.stop();
      return;
    }
    _watcher ??= FileChangeWatcher(onChanged: _onDiskChanged);
    _watcher!.start(entry.realPath);
  }

  void _onDiskChanged(String path, int modifiedMs, int size) {
    final entry = _shownEntry;
    if (!mounted || entry == null || entry.realPath != path) return;
    if (_editorController.dirty.value) {
      showToast(context: context, message: t.quickLook.reloadSkipped);

      return;
    }
    _applyReload(modifiedMs, size);
  }

  void _applyReload(int modifiedMs, int size) {
    final entry = _shownEntry;
    if (!mounted || entry == null) return;
    evictPreviewImage(entry.realPath);
    setState(() {
      _freshEntry = entry.copyWithStats(size: size, modifiedMs: modifiedMs);
      _reloadGen += 1;
    });
  }

  void _refreshStats(int modifiedMs, int size) {
    final entry = _shownEntry;
    if (!mounted || entry == null) return;
    setState(() {
      _freshEntry = entry.copyWithStats(size: size, modifiedMs: modifiedMs);
    });
  }

  Future<FileStat?> _statOf(String path) async {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.notFound ? null : stat;
  }

  FileEntry? _shownFileEntry(FileEntry? entry) {
    final fresh = _freshEntry;
    if (entry == null || fresh == null) return entry;
    return fresh.realPath == entry.realPath ? fresh : entry;
  }

  void _onEditorSaved() {
    final entry = _shownEntry;
    final watcher = _watcher;
    if (entry == null || watcher == null || watcher.path != entry.realPath) {
      return;
    }
    unawaited(
      _statOf(entry.realPath).then((stat) {
        if (stat != null) {
          watcher.refreshBaseline(
            stat.modified.millisecondsSinceEpoch,
            stat.size,
          );
        }
      }),
    );
  }

  Future<void> _requestReload() async {
    final entry = _shownEntry;
    if (entry == null || entry.type != FileItemType.file) return;
    if (PlatformPaths.isRemoteUri(entry.realPath)) return;
    if (widget.diffPair?.call(entry) != null) return;
    if (_editorController.dirty.value) {
      final result = await showCustomDialog<String>(
        context: context,
        title: t.quickLook.unsavedTitle,
        icon: WaydirIconsRegular.warning,
        iconColor: AppColors.warning,
        body: Text(
          t.quickLook.reloadMessage,
          style: context.txt.row.copyWith(color: AppColors.fg),
        ),
        actions: [
          DialogAction(label: t.quickLook.cancel, color: AppColors.fgMuted),
          DialogAction(label: t.quickLook.discard, color: AppColors.danger),
          DialogAction(label: t.quickLook.save, color: AppColors.accent),
        ],
      );
      if (!mounted || result == null || result == t.quickLook.cancel) return;
      if (result == t.quickLook.save) {
        if (!await _editorController.save()) return;
        final stat = await _statOf(entry.realPath);
        if (!mounted || stat == null) return;
        if (_shownEntry?.realPath != entry.realPath) return;
        _refreshStats(stat.modified.millisecondsSinceEpoch, stat.size);

        return;
      }
    }
    final stat = await _statOf(entry.realPath);
    if (!mounted || stat == null) return;
    if (_shownEntry?.realPath != entry.realPath) return;
    _applyReload(stat.modified.millisecondsSinceEpoch, stat.size);
  }

  void _selectFromStats(FileEntry entry) {
    final files = widget.store.navigableFiles;
    final idx = files.indexWhere((f) => f.path == entry.path);
    if (idx >= 0) {
      widget.store.jumpToIndex(idx);
    } else {
      widget.store.selectedPaths.value = {entry.path};
    }
    if (mounted) Navigator.of(context).pop();
  }

  bool _acceptCursorRepeat() {
    final now = DateTime.now();
    final last = _lastCursorRepeatAt;
    if (last != null && now.difference(last) < _cursorRepeatInterval) {
      return false;
    }
    _lastCursorRepeatAt = now;

    return true;
  }

  KeyEventResult _stepCursor(int delta, bool isRepeat) {
    if (isRepeat && !_acceptCursorRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastCursorRepeatAt = null;
    widget.store.moveCursor(delta);

    return KeyEventResult.handled;
  }

  KeyEventResult _stepCursorHorizontally(int delta, bool isRepeat) {
    if (isRepeat && !_acceptCursorRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastCursorRepeatAt = null;
    widget.store.moveCursorHorizontally(delta);

    return KeyEventResult.handled;
  }

  /// Scrolls the previewed file's content by roughly one page, for
  /// PageUp/PageDown. A no-op when the current preview isn't scrollable
  /// (e.g. an image) or nothing is attached yet.
  KeyEventResult _scrollContent(int direction, bool isRepeat) {
    if (isRepeat && !_acceptCursorRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastCursorRepeatAt = null;
    if (_contentScroll.hasClients) {
      final position = _contentScroll.position;
      final page = position.viewportDimension * 0.9;
      final target = (position.pixels + direction * page).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _contentScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }

    return KeyEventResult.handled;
  }

  /// Steps the currently shown generator preview to the next/previous page,
  /// for PageUp/PageDown. Only called while a multi-page generator preview
  /// is active — see [_generatorPage].
  KeyEventResult _stepGeneratorPage(int direction, bool isRepeat) {
    if (isRepeat && !_acceptCursorRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastCursorRepeatAt = null;
    if (direction > 0) {
      _generatorPage.next();
    } else {
      _generatorPage.prev();
    }

    return KeyEventResult.handled;
  }

  void _openShown() {
    final entry = _shownEntry;
    if (entry == null) return;
    Navigator.of(context).pop();
    widget.store.onOpen(entry);
  }

  void _popOutShown() {
    final entry = _shownEntry;
    if (entry == null) return;
    unawaited(
      QuickLookPopOut.open(entry).then((opened) {
        if (!opened && mounted) {
          showToast(context: context, message: t.quickLook.popOutUnavailable);
        }
      }),
    );
  }

  void _openShownWithMenu() {
    final entry = _shownEntry;
    final menu = widget.onOpenMenu;
    if (entry == null || menu == null) return;
    final rect = _rect;
    final position = rect == null
        ? const Offset(80, 80)
        : Offset(rect.left + 24, rect.top + 46);
    menu(entry, position, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final isRepeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !isRepeat) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!isRepeat && key == LogicalKeyboardKey.escape) {
      _requestClose();

      return KeyEventResult.handled;
    }
    if (!isRepeat && key == LogicalKeyboardKey.f5) {
      unawaited(_requestReload());

      return KeyEventResult.handled;
    }

    if (_editorActive.value) {
      if (AppShortcuts.matches('quick_look_next_file_edit', key)) {
        _focus.requestFocus();

        return _stepCursor(1, isRepeat);
      }
      if (AppShortcuts.matches('quick_look_prev_file_edit', key)) {
        _focus.requestFocus();

        return _stepCursor(-1, isRepeat);
      }

      return KeyEventResult.ignored;
    }

    if (!isRepeat &&
        (AppShortcuts.matches('quick_look_close', key) ||
            AppShortcuts.matches('quick_look_marked', key))) {
      _requestClose();

      return KeyEventResult.handled;
    }
    if (!isRepeat &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      if (AppShortcuts.isControl) {
        _popOutShown();
      } else if (HardwareKeyboard.instance.isShiftPressed) {
        _openShownWithMenu();
      } else {
        _openShown();
      }

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return _generatorPage.pageCount > 1
          ? _stepGeneratorPage(1, isRepeat)
          : _scrollContent(1, isRepeat);
    }
    if (key == LogicalKeyboardKey.pageUp) {
      return _generatorPage.pageCount > 1
          ? _stepGeneratorPage(-1, isRepeat)
          : _scrollContent(-1, isRepeat);
    }
    final gridMode = SettingsStore.instance.fileViewMode.value == 'grid';
    if (gridMode &&
        !AppShortcuts.isControl &&
        !AppShortcuts.isAlt &&
        key == LogicalKeyboardKey.arrowRight) {
      return _stepCursorHorizontally(1, isRepeat);
    }
    if (gridMode &&
        !AppShortcuts.isControl &&
        !AppShortcuts.isAlt &&
        key == LogicalKeyboardKey.arrowLeft) {
      return _stepCursorHorizontally(-1, isRepeat);
    }
    if (AppShortcuts.matches('quick_look_next_file', key) ||
        AppShortcuts.matches('quick_look_next_file_edit', key)) {
      return _stepCursor(1, isRepeat);
    }
    if (AppShortcuts.matches('quick_look_prev_file', key) ||
        AppShortcuts.matches('quick_look_prev_file_edit', key)) {
      return _stepCursor(-1, isRepeat);
    }

    return KeyEventResult.ignored;
  }

  void _setCompact(bool value) {
    if (_compact == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compact == value) return;
      setState(() => _compact = value);
    });
  }

  void _toggleMarkdownRendered() =>
      setState(() => _markdownRendered = !_markdownRendered);

  void _syncPresentation(FileEntry? entry) {
    _shownEntry = entry;
    final key = entry?.realPath;
    if (_presentationKey == key) return;
    _presentationKey = key;
    _freshEntry = null;
    _markdownRendered = true;
    _generatorPage.reset();
    _setCompact(defaultCompactFor(entry));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final rect = _rect ??= _initialRect(screen);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: rect,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  border: Border.all(color: AppColors.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(child: _buildContent()),
                    Container(height: 1, color: AppColors.bgDivider),
                    _ShortcutBar(editorActive: _editorActive),
                  ],
                ),
              ),
            ),
          ),
          for (final edge in _ResizeEdge.values) _resizeHandle(edge, rect),
        ],
      ),
    );
  }

  Widget _resizeHandle(_ResizeEdge edge, Rect rect) {
    const thickness = 8.0;
    const corner = 12.0;
    late Rect handleRect;
    late MouseCursor cursor;
    switch (edge) {
      case _ResizeEdge.n:
        handleRect = Rect.fromLTWH(
          rect.left + corner,
          rect.top - thickness / 2,
          rect.width - corner * 2,
          thickness,
        );
        cursor = SystemMouseCursors.resizeUpDown;
      case _ResizeEdge.s:
        handleRect = Rect.fromLTWH(
          rect.left + corner,
          rect.bottom - thickness / 2,
          rect.width - corner * 2,
          thickness,
        );
        cursor = SystemMouseCursors.resizeUpDown;
      case _ResizeEdge.w:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.top + corner,
          thickness,
          rect.height - corner * 2,
        );
        cursor = SystemMouseCursors.resizeLeftRight;
      case _ResizeEdge.e:
        handleRect = Rect.fromLTWH(
          rect.right - thickness / 2,
          rect.top + corner,
          thickness,
          rect.height - corner * 2,
        );
        cursor = SystemMouseCursors.resizeLeftRight;
      case _ResizeEdge.nw:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.top - thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeEdge.se:
        handleRect = Rect.fromLTWH(
          rect.right - corner + thickness / 2,
          rect.bottom - corner + thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeEdge.ne:
        handleRect = Rect.fromLTWH(
          rect.right - corner + thickness / 2,
          rect.top - thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
      case _ResizeEdge.sw:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.bottom - corner + thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
    }

    return Positioned.fromRect(
      rect: handleRect,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _handleResizeStart,
          onPanUpdate: (details) => _handleResizeUpdate(edge, details),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SignalBuilder(
      builder: (_) {
        _shownEntry = null;
        final override = widget.explicitEntry;
        if (override != null) {
          _shownEntry = override;
          _syncWatch(null);

          return Column(
            children: [
              QuickLookHeader(
                entry: override,
                compact: true,
                showInfo: true,
                onToggleInfo: () {},
                onClose: _requestClose,
                editorController: _editorController,
                onHeaderPanStart: _handleDragStart,
                onHeaderPanUpdate: _handleDragUpdate,
              ),
              Container(height: 1, color: AppColors.bgDivider),
              Expanded(
                child: override.type == FileItemType.folder
                    ? MultiProperties(entries: [override])
                    : PropertiesOnly(entry: override),
              ),
            ],
          );
        }
        if (widget.useMarkedSelection) {
          final selected = widget.store.selectedPaths.value;
          if (selected.length > 1) {
            final entries = widget.store.selectedEntries;
            _syncWatch(null);

            return Column(
              children: [
                QuickLookHeader(
                  entry: null,
                  compact: true,
                  showInfo: _showInfo,
                  multiCount: entries.length,
                  onToggleInfo: () {},
                  onClose: _requestClose,
                  editorController: _editorController,
                  onHeaderPanStart: _handleDragStart,
                  onHeaderPanUpdate: _handleDragUpdate,
                ),
                Container(height: 1, color: AppColors.bgDivider),
                Expanded(
                  child: MultiProperties(
                    entries: entries,
                    onSelect: _selectFromStats,
                  ),
                ),
              ],
            );
          }
          if (selected.length == 1) {
            final entries = widget.store.selectedEntries;
            if (entries.length == 1) {
              final entry = entries.first;
              if (entry.type == FileItemType.folder) {
                _syncPresentation(entry);
                _syncWatch(entry);

                return Column(
                  children: [
                    QuickLookHeader(
                      entry: entry,
                      compact: true,
                      showInfo: true,
                      onToggleInfo: () {},
                      onClose: _requestClose,
                      editorController: _editorController,
                      onHeaderPanStart: _handleDragStart,
                      onHeaderPanUpdate: _handleDragUpdate,
                    ),
                    Container(height: 1, color: AppColors.bgDivider),
                    Expanded(
                      child: MultiProperties(
                        entries: entries,
                        onSelect: _selectFromStats,
                      ),
                    ),
                  ],
                );
              }
              _syncPresentation(entry);
              _syncWatch(entry);

              return _singleFilePreview(entry);
            }
          }
        }

        final cursor = widget.store.cursorEntry.value;
        final entry = cursor?.ghostOf ?? cursor;
        _syncPresentation(entry);
        _syncWatch(entry);

        return _singleFilePreview(entry);
      },
    );
  }

  void _markIdentical(String key) {
    if (_identicalPairs.value.contains(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _identicalPairs.value = {..._identicalPairs.value, key};
    });
  }

  Widget _singleFilePreview(FileEntry? entry) {
    final diffPair = widget.diffPair?.call(entry);
    final showDiff = diffPair != null;
    final diffKey = diffPair == null
        ? null
        : DiffRunner.cacheKeyFor(diffPair.$1, diffPair.$2);
    final identical =
        diffKey != null && _identicalPairs.value.contains(diffKey);
    final shown = _shownFileEntry(entry);
    _playback.sync(entry, _generatorPage, blocked: showDiff && !identical);

    return Column(
      children: [
        QuickLookHeader(
          entry: entry,
          nameSuffix: identical ? t.quickLook.identicalSuffix : null,
          onOpen: entry == null ? null : _openShown,
          compact: _compact,
          showInfo: _showInfo,
          onToggleInfo: () => setState(() => _showInfo = !_showInfo),
          onClose: _requestClose,
          editorController: _editorController,
          markdownRendered: _markdownRendered,
          onToggleMarkdownView: _toggleMarkdownRendered,
          onReload: showDiff ? null : _requestReload,
          onHeaderPanStart: _handleDragStart,
          onHeaderPanUpdate: _handleDragUpdate,
        ),
        Container(height: 1, color: AppColors.bgDivider),
        Expanded(
          child: showDiff
              ? QuickLookDiffAttempt(
                  left: diffPair.$1,
                  right: diffPair.$2,
                  editorActive: _editorActive,
                  onCompactChanged: _setCompact,
                  onIdentical: () => _markIdentical(diffKey!),
                  fallback: (context) => QuickLookBody(
                    entry: entry,
                    editorActive: _editorActive,
                    editorController: _editorController,
                    showInfo: _showInfo,
                    onCompactChanged: _setCompact,
                    markdownRendered: _markdownRendered,
                    scrollController: _contentScroll,
                    generatorPage: _generatorPage,
                  ),
                )
              : QuickLookBody(
                  key: ValueKey('ql#$_reloadGen'),
                  entry: shown,
                  editorActive: _editorActive,
                  editorController: _editorController,
                  showInfo: _showInfo,
                  onCompactChanged: _setCompact,
                  markdownRendered: _markdownRendered,
                  scrollController: _contentScroll,
                  generatorPage: _generatorPage,
                ),
        ),
      ],
    );
  }
}

class _ShortcutBar extends StatelessWidget {
  final Signal<bool> editorActive;

  const _ShortcutBar({required this.editorActive});

  String get _ctrlCap => Platform.isMacOS ? '⌘' : 'Ctrl';

  List<String> _capsOf(String id) =>
      AppShortcuts.getById(id).displayKeys.split('+');

  List<String> _editStepCaps() {
    final parts = _capsOf('quick_look_next_file_edit');
    final mods = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : const <String>[];

    return [...mods, '↑', '↓'];
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final editing = editorActive.value;
        final hints = editing
            ? [
                _ShortcutHint(
                  caps: _editStepCaps(),
                  label: t.quickLook.hintSwitchFile,
                ),
                _ShortcutHint(
                  caps: _capsOf('quick_look_save'),
                  label: t.quickLook.save,
                ),
                _ShortcutHint(
                  caps: const ['F5'],
                  label: t.quickLook.hintReload,
                ),
              ]
            : [
                _ShortcutHint(
                  caps: const ['↑', '↓'],
                  label: t.quickLook.hintSwitchFile,
                ),
                _ShortcutHint(
                  caps: const ['F5'],
                  label: t.quickLook.hintReload,
                ),
                _ShortcutHint(
                  caps: _capsOf('quick_look_close'),
                  label: t.quickLook.hintClose,
                ),
                _ShortcutHint(
                  caps: const ['Enter'],
                  label: t.quickLook.hintOpen,
                ),
                _ShortcutHint(
                  caps: const ['Shift', 'Enter'],
                  label: t.quickLook.hintOpenWith,
                ),
                _ShortcutHint(
                  caps: [_ctrlCap, 'Enter'],
                  label: t.quickLook.hintPopOut,
                ),
              ];

        return Container(
          height: 30,
          color: AppColors.bgStatus,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              for (var i = 0; i < hints.length; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                hints[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  final List<String> caps;
  final String label;

  const _ShortcutHint({required this.caps, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < caps.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Text(
            caps[i],
            style: context.txt.keyCap.copyWith(color: AppColors.fg),
          ),
        ],
        const SizedBox(width: 5),
        Text(
          label,
          style: context.txt.caption.copyWith(color: AppColors.fgMuted),
        ),
      ],
    );
  }
}
