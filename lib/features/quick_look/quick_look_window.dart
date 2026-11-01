import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

import '../../core/fs/file_sort.dart';
import '../../core/fs/file_system_service.dart';
import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../../core/settings/settings_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/window/window.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'player/playback_registry.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';
import 'quick_look_find.dart';
import 'quick_look_reload.dart';
import 'quick_look_shortcut_bar.dart';
import 'rendered_source.dart';

class QuickLookWindow extends StatefulWidget {
  final FileEntry entry;
  final ValueChanged<FileEntry>? onEntryChanged;

  const QuickLookWindow({super.key, required this.entry, this.onEntryChanged});

  @override
  State<QuickLookWindow> createState() => _QuickLookWindowState();
}

class _QuickLookWindowState extends State<QuickLookWindow>
    with WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'quick-look-window');
  final _editorController = CodeEditorController();
  final _editorActive = signal(false);
  final _contentScroll = ScrollController();
  final _generatorPage = GeneratorPageController();
  final _playback = QuickLookPlaybackController();
  DateTime? _lastScrollRepeatAt;
  static const _scrollRepeatInterval = Duration(milliseconds: 70);
  late final AppLifecycleListener _lifecycle;
  late FileEntry _entry = widget.entry;
  late bool _compact = defaultCompactFor(widget.entry);
  List<FileEntry>? _siblings;
  bool _stepping = false;
  bool _showInfo = true;
  bool _rendered = true;
  bool _closing = false;
  bool _confirmingClose = false;
  bool _pendingSearch = false;
  bool _showingRendered = false;
  bool _renderable = false;
  bool _pendingEdit = false;
  late final void Function() _findReadySub;
  late final _reload = QuickLookReloadController(
    editorController: _editorController,
    onReloadSkipped: _showReloadSkipped,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    PlaybackRegistry.instance.register(_playback);
    _reload.watch(_entry);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
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
    _lifecycle.dispose();
    _playback.dispose();
    _findReadySub();
    _editorActive.dispose();
    _editorController.dispose();
    _contentScroll.dispose();
    _generatorPage.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _playback.stopForLifecycle();
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (_closing) return AppExitResponse.exit;

    return await _confirmClose()
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  Future<bool> _confirmClose() async {
    if (!mounted) return true;
    if (!_editorController.dirty.value) return true;
    if (_confirmingClose) return false;
    _confirmingClose = true;
    final UnsavedChoice choice;
    try {
      choice = await confirmUnsavedChanges(context, t.quickLook.unsavedMessage);
    } finally {
      _confirmingClose = false;
    }
    if (!mounted || choice == UnsavedChoice.cancel) return false;
    if (choice == UnsavedChoice.save) return await _editorController.save();

    return true;
  }

  Future<void> _close() async {
    if (!await _confirmClose()) return;
    _closing = true;
    appWindow.close();
  }

  void _showReloadSkipped() {
    if (!mounted) return;
    showToast(context: context, message: t.quickLook.reloadSkipped);
  }

  void _requestReload() {
    if (_closing || _confirmingClose) return;
    unawaited(_reload.request(context));
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

  void _setCompact(bool value) {
    if (_compact == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compact == value) return;
      setState(() => _compact = value);
    });
  }

  bool _acceptScrollRepeat() {
    final now = DateTime.now();
    final last = _lastScrollRepeatAt;
    if (last != null && now.difference(last) < _scrollRepeatInterval) {
      return false;
    }
    _lastScrollRepeatAt = now;

    return true;
  }

  KeyEventResult _scrollContent(int direction, bool isRepeat, bool fullPage) {
    if (isRepeat && !_acceptScrollRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastScrollRepeatAt = null;
    if (_contentScroll.hasClients) {
      final position = _contentScroll.position;
      final step = position.viewportDimension * (fullPage ? 0.9 : 0.15);
      final target = (position.pixels + direction * step).clamp(
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

  KeyEventResult _stepGeneratorPage(int direction, bool isRepeat) {
    if (isRepeat && !_acceptScrollRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastScrollRepeatAt = null;
    if (direction > 0) {
      _generatorPage.next();
    } else {
      _generatorPage.prev();
    }

    return KeyEventResult.handled;
  }

  Future<List<FileEntry>> _loadSiblings() async {
    final cached = _siblings;
    if (cached != null) return cached;
    final current = _entry.path;
    final listed = await FileSystemService.listDirectory(p.dirname(current));
    final settings = SettingsStore.instance;
    final showHidden = settings.showHiddenDefault.value;
    final files = [
      for (final e in listed)
        if (e.type == FileItemType.file &&
            (showHidden || !e.isHidden || p.equals(e.path, current)))
          e,
    ];

    return _siblings = sortEntries(
      files,
      key: SortKey.name,
      ascending: true,
      foldersFirst: false,
      naturalSort: settings.naturalSort.value,
    );
  }

  KeyEventResult _stepFile(int delta, bool isRepeat) {
    if (isRepeat && !_acceptScrollRepeat()) return KeyEventResult.handled;
    if (!isRepeat) _lastScrollRepeatAt = null;
    unawaited(_stepFileAsync(delta));

    return KeyEventResult.handled;
  }

  Future<void> _stepFileAsync(int delta) async {
    if (_stepping) return;
    _stepping = true;
    try {
      final List<FileEntry> siblings;
      try {
        siblings = await _loadSiblings();
      } on Exception catch (e, st) {
        log.warn('quick-look', 'sibling listing failed', error: e, stack: st);

        return;
      }
      final index = siblings.indexWhere((e) => p.equals(e.path, _entry.path));
      final target = index + delta;
      if (index < 0 || target < 0 || target >= siblings.length) return;
      if (!await _confirmClose() || !mounted) return;
      _showEntry(siblings[target]);
    } finally {
      _stepping = false;
    }
  }

  void _showEntry(FileEntry entry) {
    final find = _editorController.find;
    if (find?.value != null) find!.close();
    _generatorPage.reset();
    setState(() {
      _entry = entry;
      _compact = defaultCompactFor(entry);
      _rendered = true;
      _pendingSearch = false;
      _pendingEdit = false;
    });
    _reload.watch(entry);
    widget.onEntryChanged?.call(entry);
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
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
      _close();

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
    if (key == LogicalKeyboardKey.pageDown) {
      return _generatorPage.pageCount > 1
          ? _stepGeneratorPage(1, isRepeat)
          : _scrollContent(1, isRepeat, true);
    }
    if (key == LogicalKeyboardKey.pageUp) {
      return _generatorPage.pageCount > 1
          ? _stepGeneratorPage(-1, isRepeat)
          : _scrollContent(-1, isRepeat, true);
    }
    if (!AppShortcuts.isControl && !AppShortcuts.isAlt) {
      if (key == LogicalKeyboardKey.arrowDown) {
        return _scrollContent(1, isRepeat, false);
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        return _scrollContent(-1, isRepeat, false);
      }
      if (key == LogicalKeyboardKey.arrowRight) return _stepFile(1, isRepeat);
      if (key == LogicalKeyboardKey.arrowLeft) return _stepFile(-1, isRepeat);
    }

    return KeyEventResult.ignored;
  }

  List<QuickLookShortcutHint> _shortcutHints(bool editing) {
    if (editing) return QuickLookShortcutHint.editing();

    return [
      QuickLookShortcutHint(
        caps: const ['←', '→'],
        label: t.quickLook.hintSwitchFile,
      ),
      QuickLookShortcutHint(
        caps: const ['↑', '↓'],
        label: t.quickLook.hintScroll,
      ),
      QuickLookShortcutHint(caps: const ['F5'], label: t.quickLook.hintReload),
      QuickLookShortcutHint(caps: const ['F6'], label: t.quickLook.hintEdit),
      QuickLookShortcutHint(caps: const ['F7'], label: t.quickLook.info),
      QuickLookShortcutHint(caps: const ['Esc'], label: t.quickLook.hintClose),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      child: ColoredBox(
        color: AppColors.bg,
        child: SignalBuilder(
          builder: (_) {
            _reload.revision.value;
            final entry = _reload.shown(_entry)!;
            _renderable = RenderedSource.available(entry);
            _showingRendered = _renderable && _rendered;
            _playback.sync(
              entry,
              _generatorPage,
              blocked: false,
              generation: _reload.generation,
            );

            return Stack(
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onDoubleTap: appWindow.maximizeOrRestore,
                      child: QuickLookHeader(
                        entry: entry,
                        compact: _compact,
                        showInfo: _showInfo,
                        onToggleInfo: () =>
                            setState(() => _showInfo = !_showInfo),
                        onClose: _close,
                        editorController: _editorController,
                        rendered: _rendered,
                        onToggleRenderedView: _renderable
                            ? _toggleRendered
                            : null,
                        onSearch: _onSearchTap,
                        onReload: QuickLookReloadController.canReload(entry)
                            ? _requestReload
                            : null,
                        onHeaderPanStart: (_) => appWindow.startDragging(),
                        onToggleMaximize: appWindow.maximizeOrRestore,
                      ),
                    ),
                    Container(height: 1, color: AppColors.bgDivider),
                    Expanded(
                      child: QuickLookBody(
                        key: ValueKey(
                          'qlw#${entry.path}#${_reload.generation}',
                        ),
                        entry: entry,
                        editorActive: _editorActive,
                        editorController: _editorController,
                        showInfo: _showInfo,
                        onCompactChanged: _setCompact,
                        rendered: _rendered,
                        scrollController: _contentScroll,
                        generatorPage: _generatorPage,
                      ),
                    ),
                    Container(height: 1, color: AppColors.bgDivider),
                    QuickLookShortcutBar(
                      editorActive: _editorActive,
                      hints: _shortcutHints,
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
          },
        ),
      ),
    );
  }
}
