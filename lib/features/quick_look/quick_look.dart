import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/settings/settings_store.dart';
import '../../features/navigation/navigation_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/motion.dart';
import '../../ui/widgets/floating_window_geometry.dart';
import 'code_editor.dart';
import 'diff/diff_runner.dart';
import 'generators/generator_page_controller.dart';
import 'info_panel.dart';
import 'player/playback_registry.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';
import 'quick_look_find.dart';
import 'quick_look_pop_out.dart';
import 'quick_look_reload.dart';
import 'quick_look_shortcut_bar.dart';
import 'rendered_source.dart';

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
  final reduceMotion = context.reduceMotion;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: t.quickLook.title,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 110),
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
      if (reduceMotion) return child;
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

class _QuickLookState extends State<_QuickLook>
    with WidgetsBindingObserver, FloatingWindowGeometry<_QuickLook> {
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
  bool _rendered = true;
  bool _pendingSearch = false;
  bool _showingRendered = false;
  bool _renderable = false;
  bool _pendingEdit = false;
  late final void Function() _findReadySub;
  String? _presentationKey;
  late final _reload = QuickLookReloadController(
    editorController: _editorController,
    onReloadSkipped: _showReloadSkipped,
  );
  DateTime? _lastCursorRepeatAt;

  static const _cursorRepeatInterval = Duration(milliseconds: 70);

  /// Centers the window in [screen] — wider by default when opened as a
  /// compare-mode diff, since a side-by-side diff needs more room than a
  /// normal single-file preview.
  @override
  Rect computeInitialRect(Size screen) {
    final isDiff =
        widget.diffPair?.call(
          widget.explicitEntry ?? widget.store.cursorEntry.value,
        ) !=
        null;
    final width = _clampSize(
      screen.width * (isDiff ? 0.92 : 0.7),
      minWindowWidth,
      isDiff ? 1600.0 : 1100.0,
    );
    final height = _clampSize(screen.height * 0.78, minWindowHeight, 900.0);
    final originX = (screen.width - width) / 2;
    final originY = (screen.height - height) / 2;

    return clampToScreen(
      Rect.fromLTWH(originX, originY, width, height),
      screen,
    );
  }

  static double _clampSize(double value, double min, double max) {
    if (max < min) return min;

    return value.clamp(min, max);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    PlaybackRegistry.instance.register(_playback);
    final cursor = widget.store.cursorEntry.value;
    final entry = cursor?.ghostOf ?? cursor;
    _compact = defaultCompactFor(entry);
    _presentationKey = entry?.realPath;
    _findReadySub = _editorController.findReady.subscribe((ready) {
      if (!ready || !mounted) return;
      setState(() {});
      if (_pendingEdit) {
        _pendingEdit = false;
        _editorController.focus();
      }
      if (!_pendingSearch) return;
      _pendingSearch = false;
      final find = _editorController.find;
      if (find == null) return;
      find.findMode();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlaybackRegistry.instance.unregister(_playback);
    _reload.dispose();
    _playback.dispose();
    _findReadySub();
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
    final choice = await confirmUnsavedChanges(
      context,
      t.quickLook.unsavedMessage,
    );
    if (!mounted || choice == UnsavedChoice.cancel) return;
    if (choice == UnsavedChoice.save && !await _editorController.save()) {
      return; // save failed - keep the preview open
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showReloadSkipped() {
    if (!mounted) return;
    showToast(context: context, message: t.quickLook.reloadSkipped);
  }

  void _requestReload() => unawaited(_reload.request(context));
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
    final rect = this.rect;
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
    if (!isRepeat &&
        key == LogicalKeyboardKey.keyF &&
        AppShortcuts.isControl &&
        !AppShortcuts.isAlt) {
      _openSearch();

      return KeyEventResult.handled;
    }
    if (!isRepeat && key == LogicalKeyboardKey.escape) {
      final find = _editorController.find;
      if (find?.value != null) {
        find!.close();

        return KeyEventResult.handled;
      }
      _requestClose();

      return KeyEventResult.handled;
    }
    if (!isRepeat && key == LogicalKeyboardKey.f5) {
      _requestReload();

      return KeyEventResult.handled;
    }

    if (!isRepeat && key == LogicalKeyboardKey.f6) {
      _toggleEditMode();

      return KeyEventResult.handled;
    }
    if (!isRepeat && key == LogicalKeyboardKey.f7) {
      setState(() => _showInfo = !_showInfo);

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG &&
        AppShortcuts.isControl &&
        !AppShortcuts.isAlt) {
      final find = _editorController.find;
      if (find != null && find.value != null) {
        if (AppShortcuts.isShift) {
          find.previousMatch();
        } else {
          find.nextMatch();
        }

        return KeyEventResult.handled;
      }
    }
    if (_editorActive.value) return KeyEventResult.ignored;

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
    if (AppShortcuts.matches('quick_look_next_file', key)) {
      return _stepCursor(1, isRepeat);
    }
    if (AppShortcuts.matches('quick_look_prev_file', key)) {
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

  void _toggleRendered() {
    if (!_rendered) {
      final find = _editorController.find;
      if (find != null && find.value != null) find.close();
    }
    setState(() => _rendered = !_rendered);
  }

  void _toggleEditMode() {
    if (_editorActive.value) {
      _focus.requestFocus();
      if (_renderable && !_rendered) _toggleRendered();

      return;
    }
    if (_showingRendered) {
      _pendingEdit = true;
      _toggleRendered();

      return;
    }
    _editorController.focus();
  }

  void _openSearch() {
    final find = _editorController.find;
    if (find != null) {
      if (find.value == null) {
        find.findMode();
      } else {
        find.close();
      }
      return;
    }
    if (!_showingRendered) return;
    _pendingSearch = true;
    setState(() => _rendered = false);
  }

  void _onSearchTap() {
    if (_editorController.find != null) {
      _openSearch();
      return;
    }
    _toggleRendered();
    _openSearch();
  }

  void _syncPresentation(FileEntry? entry) {
    _shownEntry = entry;
    final key = entry?.realPath;
    if (_presentationKey == key) return;
    _presentationKey = key;
    _pendingSearch = false;
    _pendingEdit = false;
    _rendered = true;
    _generatorPage.reset();
    _setCompact(defaultCompactFor(entry));
  }

  List<QuickLookShortcutHint> _shortcutHints(bool editing) {
    if (editing) return QuickLookShortcutHint.editing();

    return [
      QuickLookShortcutHint(
        caps: const ['↑', '↓'],
        label: t.quickLook.hintSwitchFile,
      ),
      QuickLookShortcutHint(caps: const ['F5'], label: t.quickLook.hintReload),
      QuickLookShortcutHint(caps: const ['F6'], label: t.quickLook.hintEdit),
      QuickLookShortcutHint(caps: const ['F7'], label: t.quickLook.info),
      QuickLookShortcutHint(
        caps: QuickLookShortcutHint.capsOf('quick_look_close'),
        label: t.quickLook.hintClose,
      ),
      QuickLookShortcutHint(caps: const ['Enter'], label: t.quickLook.hintOpen),
      QuickLookShortcutHint(
        caps: const ['Shift', 'Enter'],
        label: t.quickLook.hintOpenWith,
      ),
      QuickLookShortcutHint(
        caps: [QuickLookShortcutHint.ctrlCap, 'Enter'],
        label: t.quickLook.hintPopOut,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final rect = ensureRect(screen);

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
                    QuickLookShortcutBar(
                      editorActive: _editorActive,
                      hints: _shortcutHints,
                    ),
                  ],
                ),
              ),
            ),
          ),
          ...resizeHandles(rect),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SignalBuilder(
      builder: (_) {
        _shownEntry = null;
        _showingRendered = false;
        final override = widget.explicitEntry;
        if (override != null) {
          _shownEntry = override;
          _reload.watch(null);

          return Column(
            children: [
              QuickLookHeader(
                entry: override,
                compact: true,
                showInfo: true,
                onToggleInfo: () {},
                onClose: _requestClose,
                editorController: _editorController,
                onHeaderPanStart: handleDragStart,
                onHeaderPanUpdate: handleDragUpdate,
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
            _reload.watch(null);

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
                  onHeaderPanStart: handleDragStart,
                  onHeaderPanUpdate: handleDragUpdate,
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
                _reload.watch(null);

                return Column(
                  children: [
                    QuickLookHeader(
                      entry: entry,
                      compact: true,
                      showInfo: true,
                      onToggleInfo: () {},
                      onClose: _requestClose,
                      editorController: _editorController,
                      onHeaderPanStart: handleDragStart,
                      onHeaderPanUpdate: handleDragUpdate,
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

              return _singleFilePreview(entry);
            }
          }
        }

        final cursor = widget.store.cursorEntry.value;
        final entry = cursor?.ghostOf ?? cursor;
        _syncPresentation(entry);

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
    _reload.watch(showDiff ? null : entry);
    _reload.revision.value;
    final shown = _reload.shown(entry);
    final sourceToggle = entry != null && RenderedSource.available(entry);
    _renderable = !showDiff && shown != null && RenderedSource.available(shown);
    _showingRendered = _renderable && _rendered;
    _playback.sync(
      entry,
      _generatorPage,
      blocked: showDiff && !identical,
      generation: _reload.generation,
    );

    return Stack(
      children: [
        Column(
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
              rendered: _rendered,
              onToggleRenderedView: sourceToggle ? _toggleRendered : null,
              onSearch: _onSearchTap,
              onReload: !showDiff && QuickLookReloadController.canReload(entry)
                  ? _requestReload
                  : null,
              onHeaderPanStart: handleDragStart,
              onHeaderPanUpdate: handleDragUpdate,
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
                        rendered: _rendered,
                        scrollController: _contentScroll,
                        generatorPage: _generatorPage,
                      ),
                    )
                  : QuickLookBody(
                      key: ValueKey('ql#${_reload.generation}'),
                      entry: shown,
                      editorActive: _editorActive,
                      editorController: _editorController,
                      showInfo: _showInfo,
                      onCompactChanged: _setCompact,
                      rendered: _rendered,
                      scrollController: _contentScroll,
                      generatorPage: _generatorPage,
                    ),
            ),
          ],
        ),
        Positioned(
          top: 47,
          right: 14,
          child: QuickLookFindPopup(controller: _editorController),
        ),
      ],
    );
  }
}
