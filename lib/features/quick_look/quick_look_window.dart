import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
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
  FileChangeWatcher? _watcher;
  int _reloadGen = 0;
  FileEntry? _freshEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    _editorController.onSaved = _onEditorSaved;
    final entry = widget.entry;
    if (entry.type == FileItemType.file &&
        !PlatformPaths.isRemoteUri(entry.realPath)) {
      _watcher = FileChangeWatcher(onChanged: _onDiskChanged);
      _watcher!.start(entry.realPath);
    }
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watcher?.stop();
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

  FileEntry get _shownEntry => _freshEntry ?? widget.entry;

  void _onDiskChanged(String path, int modifiedMs, int size) {
    if (!mounted || _shownEntry.realPath != path) return;
    if (_editorController.dirty.value) {
      showToast(context: context, message: t.quickLook.reloadSkipped);

      return;
    }
    _applyReload(modifiedMs, size);
  }

  void _applyReload(int modifiedMs, int size) {
    if (!mounted) return;
    final entry = _shownEntry;
    evictPreviewImage(entry.realPath);
    setState(() {
      _freshEntry = entry.copyWithStats(size: size, modifiedMs: modifiedMs);
      _reloadGen += 1;
    });
  }

  void _refreshStats(int modifiedMs, int size) {
    if (!mounted) return;
    final entry = _shownEntry;
    setState(() {
      _freshEntry = entry.copyWithStats(size: size, modifiedMs: modifiedMs);
    });
  }

  Future<FileStat?> _statOf(String path) async {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.notFound ? null : stat;
  }

  void _onEditorSaved() {
    final watcher = _watcher;
    final entry = _shownEntry;
    if (watcher == null || watcher.path != entry.realPath) return;
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
    if (entry.type != FileItemType.file) return;
    if (PlatformPaths.isRemoteUri(entry.realPath)) return;
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
        _refreshStats(stat.modified.millisecondsSinceEpoch, stat.size);

        return;
      }
    }
    final stat = await _statOf(entry.realPath);
    if (!mounted || stat == null) return;
    _applyReload(stat.modified.millisecondsSinceEpoch, stat.size);
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
      unawaited(_requestReload());

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _shownEntry;

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
                    onReload: _requestReload,
                    onHeaderPanStart: (_) => appWindow.startDragging(),
                  ),
                ),
                Container(height: 1, color: AppColors.bgDivider),
                Expanded(
                  child: QuickLookBody(
                    key: ValueKey('qlw#$_reloadGen'),
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
