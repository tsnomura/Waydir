import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/models/file_entry.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/window/window.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted || result == null || result == t.quickLook.cancel) {
      return false;
    }
    if (result == t.quickLook.save) return await _editorController.save();

    return true;
  }

  Future<void> _close() async {
    if (!await _confirmClose()) return;
    _closing = true;
    appWindow.close();
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

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      child: ColoredBox(
        color: AppColors.bg,
        child: SignalBuilder(
          builder: (_) {
            _playback.sync(entry, _generatorPage, blocked: false);

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
                    onHeaderPanStart: (_) => appWindow.startDragging(),
                  ),
                ),
                Container(height: 1, color: AppColors.bgDivider),
                Expanded(
                  child: QuickLookBody(
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
