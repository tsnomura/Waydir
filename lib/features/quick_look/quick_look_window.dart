import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/models/file_entry.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/window/window.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';
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
    _reload.watch(widget.entry);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _setCompact(bool value) {
    if (_compact == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compact == value) return;
      setState(() => _compact = value);
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();

      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _requestReload();

      return KeyEventResult.handled;
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

            return Column(
              children: [
                GestureDetector(
                  onDoubleTap: appWindow.maximizeOrRestore,
                  child: QuickLookHeader(
                    entry: entry,
                    compact: _compact,
                    showInfo: _showInfo,
                    onToggleInfo: () => setState(() => _showInfo = !_showInfo),
                    onClose: _close,
                    editorController: _editorController,
                    markdownRendered: _markdownRendered,
                    onToggleMarkdownView: () =>
                        setState(() => _markdownRendered = !_markdownRendered),
                    onReload: _requestReload,
                    onHeaderPanStart: (_) => appWindow.startDragging(),
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
            );
          },
        ),
      ),
    );
  }
}
