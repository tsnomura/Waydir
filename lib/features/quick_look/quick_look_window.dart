import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
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

class QuickLookWindow extends StatefulWidget {
  final FileEntry entry;

  const QuickLookWindow({super.key, required this.entry});

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
  late bool _compact = defaultCompactFor(widget.entry);
  bool _showInfo = true;
  bool _markdownRendered = true;
  bool _closing = false;
  bool _confirmingClose = false;
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
    _reload.watch(widget.entry);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
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

  void _openSearch() {
    final find = _editorController.find;
    if (find == null) return;
    if (find.value == null) {
      find.findMode();
    } else {
      find.close();
    }
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
    }

    return KeyEventResult.ignored;
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
            final entry = _reload.shown(widget.entry)!;
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
                        markdownRendered: _markdownRendered,
                        onToggleMarkdownView: () => setState(
                          () => _markdownRendered = !_markdownRendered,
                        ),
                        onSearch: _openSearch,
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
                        key: ValueKey('qlw#${_reload.generation}'),
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
