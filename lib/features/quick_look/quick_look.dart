import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/settings/settings_store.dart';
import '../../features/files/file_icons.dart';
import '../../features/navigation/navigation_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'generators/generator_preview.dart';
import 'generators/generator_registry.dart';
import 'image_preview.dart';
import 'info_panel.dart';
import 'markdown_preview.dart';
import 'pdf_preview.dart';
import 'quick_look_common.dart';
import 'quick_look_io.dart';

Future<void> showQuickLook({
  required BuildContext context,
  required NavigationStore store,
  FileEntry? explicitEntry,
  Rect? anchorArea,
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
        anchorArea: anchorArea,
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
  final Rect? anchorArea;

  const _QuickLook({required this.store, this.explicitEntry, this.anchorArea});

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

enum _ResizeEdge { n, s, e, w, ne, nw, se, sw }

const double _kMinWindowWidth = 420;
const double _kMinWindowHeight = 320;

class _QuickLookState extends State<_QuickLook> {
  final _focus = FocusNode();
  final _editorActive = signal(false);
  final _editorController = CodeEditorController();
  final _contentScroll = ScrollController();
  final _generatorPage = GeneratorPageController();
  bool _compact = true;
  bool _showInfo = true;
  bool _markdownRendered = true;
  String? _presentationKey;
  DateTime? _lastCursorRepeatAt;
  Rect? _rect;
  Offset? _dragAnchor;
  Rect? _dragStartRect;

  static const _cursorRepeatInterval = Duration(milliseconds: 70);

  /// Centers the window in [screen] by default, or within [anchor] when
  /// given (e.g. the inactive pane's area in dual-pane mode).
  Rect _initialRect(Size screen) {
    final anchor = widget.anchorArea;
    final maxWidth = anchor != null ? anchor.width : screen.width;
    final maxHeight = anchor != null ? anchor.height : screen.height;
    final width = _clampSize(
      anchor != null ? maxWidth * 0.86 : maxWidth * 0.7,
      _kMinWindowWidth,
      anchor != null ? maxWidth : 1100.0,
    );
    final height = _clampSize(
      anchor != null ? maxHeight * 0.86 : maxHeight * 0.78,
      _kMinWindowHeight,
      anchor != null ? maxHeight : 900.0,
    );
    final originX = (anchor?.left ?? 0) + (maxWidth - width) / 2;
    final originY = (anchor?.top ?? 0) + (maxHeight - height) / 2;

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
    final entry = widget.store.cursorEntry.value;
    _compact = _defaultCompact(entry);
    _presentationKey = entry?.realPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _editorActive.dispose();
    _editorController.dispose();
    _contentScroll.dispose();
    _generatorPage.dispose();
    super.dispose();
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

  void _selectFromStats(FileEntry entry) {
    final files = widget.store.visibleFiles.value;
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final isRepeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !isRepeat) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!isRepeat && key == LogicalKeyboardKey.escape) {
      _requestClose();

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

    if (!isRepeat && AppShortcuts.matches('quick_look_close', key)) {
      _requestClose();

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

  static bool _defaultCompact(FileEntry? entry) {
    if (entry == null || entry.type == FileItemType.folder) return true;
    final ext = entry.extension;

    return !imageExts.contains(ext) &&
        !pdfExts.contains(ext) &&
        !markdownExts.contains(ext);
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
    final key = entry?.realPath;
    if (_presentationKey == key) return;
    _presentationKey = key;
    _markdownRendered = true;
    _generatorPage.reset();
    _setCompact(_defaultCompact(entry));
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
        final override = widget.explicitEntry;
        if (override != null) {
          return Column(
            children: [
              _Header(
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
        final selected = widget.store.selectedPaths.value;
        if (selected.length > 1) {
          final entries = widget.store.selectedEntries;

          return Column(
            children: [
              _Header(
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
          if (entries.length == 1 &&
              entries.first.type == FileItemType.folder) {
            final entry = entries.first;
            _syncPresentation(entry);

            return Column(
              children: [
                _Header(
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
        }
        final entry = widget.store.cursorEntry.value;
        _syncPresentation(entry);

        return Column(
          children: [
            _Header(
              entry: entry,
              compact: _compact,
              showInfo: _showInfo,
              onToggleInfo: () => setState(() => _showInfo = !_showInfo),
              onClose: _requestClose,
              editorController: _editorController,
              markdownRendered: _markdownRendered,
              onToggleMarkdownView: _toggleMarkdownRendered,
              onHeaderPanStart: _handleDragStart,
              onHeaderPanUpdate: _handleDragUpdate,
            ),
            Container(height: 1, color: AppColors.bgDivider),
            Expanded(
              child: _Body(
                entry: entry,
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
      },
    );
  }
}

class _ShortcutBar extends StatelessWidget {
  final Signal<bool> editorActive;

  const _ShortcutBar({required this.editorActive});

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
              ]
            : [
                _ShortcutHint(
                  caps: const ['↑', '↓'],
                  label: t.quickLook.hintSwitchFile,
                ),
                _ShortcutHint(
                  caps: _capsOf('quick_look_close'),
                  label: t.quickLook.hintClose,
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

class _Header extends StatelessWidget {
  final FileEntry? entry;
  final bool compact;
  final bool showInfo;
  final VoidCallback onToggleInfo;
  final VoidCallback onClose;
  final int? multiCount;
  final CodeEditorController editorController;
  final bool markdownRendered;
  final VoidCallback? onToggleMarkdownView;
  final GestureDragStartCallback? onHeaderPanStart;
  final GestureDragUpdateCallback? onHeaderPanUpdate;

  const _Header({
    required this.entry,
    required this.compact,
    required this.showInfo,
    required this.onToggleInfo,
    required this.onClose,
    required this.editorController,
    this.multiCount,
    this.markdownRendered = true,
    this.onToggleMarkdownView,
    this.onHeaderPanStart,
    this.onHeaderPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final multi = multiCount != null;
    final name = multi
        ? t.quickLook.items(count: multiCount!)
        : e?.name ?? t.quickLook.noSelection;
    final hasPreview = !multi && e != null && !compact;
    final isMarkdown =
        !multi &&
        e != null &&
        markdownExts.contains(e.extension) &&
        onToggleMarkdownView != null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onHeaderPanStart,
      onPanUpdate: onHeaderPanUpdate,
      child: Container(
        height: 46,
        color: AppColors.bgSidebar,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (multi)
              Icon(WaydirIconsRegular.copy, size: 18, color: AppColors.accent)
            else if (e == null)
              Icon(WaydirIconsRegular.file, size: 18, color: AppColors.fgMuted)
            else
              buildFileIcon(
                name: e.name,
                ext: e.extension,
                isFolder: e.type == FileItemType.folder,
                size: 18,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: context.txt.bodyEmphasis,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (isMarkdown) ...[
              SignalBuilder(
                builder: (context) {
                  final blocked =
                      !markdownRendered && editorController.dirty.value;

                  return _HeaderButton(
                    icon: markdownRendered
                        ? WaydirIconsRegular.code
                        : WaydirIconsRegular.eye,
                    active: false,
                    enabled: !blocked,
                    tooltip: blocked
                        ? t.quickLook.saveBeforePreview
                        : markdownRendered
                        ? t.quickLook.viewSource
                        : t.quickLook.viewRendered,
                    onTap: onToggleMarkdownView!,
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
            if (hasPreview) ...[
              _HeaderButton(
                icon: WaydirIconsRegular.info,
                active: showInfo,
                tooltip: t.menu.properties,
                onTap: onToggleInfo,
              ),
              const SizedBox(width: 4),
            ],
            _CloseButton(onTap: onClose),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatefulWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _HeaderButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final hovered = widget.enabled && _hover;
    final bg = active
        ? AppColors.accent.withValues(alpha: 0.16)
        : hovered
        ? AppColors.bgHover
        : Colors.transparent;
    final fg = !widget.enabled
        ? AppColors.fgSubtle
        : active
        ? AppColors.accent
        : hovered
        ? AppColors.fg
        : AppColors.fgMuted;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover ? AppColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Icon(
            Icons.close,
            size: 16,
            color: _hover ? AppColors.fg : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}

Widget _split(
  Widget preview,
  FileEntry entry, {
  required bool showInfo,
  ScrollController? scrollController,
}) {
  final scrollablePreview = scrollController == null
      ? preview
      : PrimaryScrollController(
          controller: scrollController,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: preview,
        );
  if (!showInfo) return scrollablePreview;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: scrollablePreview),
      Container(width: 1, color: AppColors.bgDivider),
      SizedBox(
        width: panelWidth,
        child: PrimaryScrollController.none(child: InfoPanel(entry: entry)),
      ),
    ],
  );
}

class _Body extends StatelessWidget {
  final FileEntry? entry;
  final Signal<bool> editorActive;
  final CodeEditorController editorController;
  final bool showInfo;
  final ValueChanged<bool> onCompactChanged;
  final bool markdownRendered;
  final ScrollController scrollController;
  final GeneratorPageController generatorPage;

  const _Body({
    required this.entry,
    required this.editorActive,
    required this.editorController,
    required this.showInfo,
    required this.onCompactChanged,
    required this.markdownRendered,
    required this.scrollController,
    required this.generatorPage,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    void release() => WidgetsBinding.instance.addPostFrameCallback(
      (_) => editorActive.value = false,
    );

    if (e == null || e.type == FileItemType.folder) {
      release();
      onCompactChanged(true);

      return PropertiesOnly(entry: e);
    }
    // Checked first, ahead of every built-in preview: a configured generator
    // is an explicit, deliberate choice to handle this extension a specific
    // way, so it wins even over a built-in that would otherwise apply (e.g.
    // pdf).
    final generator = GeneratorRegistry.instance.forExtension(e.extension);
    if (generator != null) {
      release();
      onCompactChanged(false);

      return _split(
        GeneratorPreview(entry: e, page: generatorPage),
        e,
        showInfo: showInfo,
      );
    }
    if (imageExts.contains(e.extension)) {
      release();
      onCompactChanged(false);

      return _split(ImagePreview(path: e.realPath), e, showInfo: showInfo);
    }
    if (pdfExts.contains(e.extension)) {
      release();
      onCompactChanged(false);

      return _split(
        PdfPreview(path: e.realPath),
        e,
        showInfo: showInfo,
        scrollController: scrollController,
      );
    }
    if (markdownExts.contains(e.extension) && markdownRendered) {
      release();
      onCompactChanged(false);

      return _split(
        MarkdownPreview(entry: e),
        e,
        showInfo: showInfo,
        scrollController: scrollController,
      );
    }
    if (binaryExts.contains(e.extension)) {
      release();
      onCompactChanged(true);

      return PropertiesOnly(entry: e);
    }

    return _ProbeLoader(
      entry: e,
      editorActive: editorActive,
      editorController: editorController,
      showInfo: showInfo,
      onCompactChanged: onCompactChanged,
      scrollController: scrollController,
    );
  }
}

class _ProbeLoader extends StatelessWidget {
  final FileEntry entry;
  final Signal<bool> editorActive;
  final CodeEditorController editorController;
  final bool showInfo;
  final ValueChanged<bool> onCompactChanged;
  final ScrollController scrollController;

  const _ProbeLoader({
    required this.entry,
    required this.editorActive,
    required this.editorController,
    required this.showInfo,
    required this.onCompactChanged,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    void release() => WidgetsBinding.instance.addPostFrameCallback(
      (_) => editorActive.value = false,
    );

    return AsyncRetain<Probe>(
      cacheKey: entry.realPath,
      loader: () => probeFile(entry),
      loading: const QlCentered.spinner(),
      builder: (res) {
        switch (res.kind) {
          case QlKind.text:
            onCompactChanged(false);

            return _split(
              CodeEditor(
                key: ValueKey(entry.realPath),
                path: entry.realPath,
                extension: entry.extension,
                initial: res.text,
                editorActive: editorActive,
                controller: editorController,
                verticalScrollController: scrollController,
              ),
              entry,
              showInfo: showInfo,
            );
          case QlKind.binary:
          case QlKind.tooLarge:
            release();
            onCompactChanged(true);

            return PropertiesOnly(entry: entry);
          case QlKind.error:
            release();
            onCompactChanged(true);

            return PropertiesOnly(entry: entry);
        }
      },
    );
  }
}
