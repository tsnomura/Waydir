import 'dart:async';

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/models/file_entry.dart';
import '../../features/navigation/navigation_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'generators/generator_registry.dart';
import 'player/playback_registry.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_common.dart';
import 'quick_look_content.dart';
import 'quick_look_find.dart';
import 'quick_look_reload.dart';

typedef QuickLookCloseGuard = Future<bool> Function();

class QuickLookPanel extends StatefulWidget {
  final NavigationStore store;
  final VoidCallback onClose;
  final ValueChanged<QuickLookCloseGuard?> onRegisterCloseGuard;

  const QuickLookPanel({
    super.key,
    required this.store,
    required this.onClose,
    required this.onRegisterCloseGuard,
  });

  @override
  State<QuickLookPanel> createState() => _QuickLookPanelState();
}

class _QuickLookPanelState extends State<QuickLookPanel>
    with WidgetsBindingObserver {
  final _editorController = CodeEditorController();
  final _editorActive = signal(false);
  final _contentScroll = ScrollController();
  final _generatorPage = GeneratorPageController();
  final _playback = QuickLookPlaybackController();
  bool _compact = true;
  bool _showInfo = true;
  bool _markdownRendered = true;
  bool _pendingSearch = false;
  bool _renderedMarkdown = false;
  late final void Function() _findReadySub;
  String? _presentationKey;
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
    final entry = _resolveEntry();
    _compact = defaultCompactFor(entry);
    _presentationKey = entry?.realPath;
    _findReadySub = _editorController.findReady.subscribe((ready) {
      if (!ready || !mounted) return;
      setState(() {});
      if (!_pendingSearch) return;
      _pendingSearch = false;
      final find = _editorController.find;
      if (find == null) return;
      find.findMode();
    });
    widget.onRegisterCloseGuard(_confirmClose);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlaybackRegistry.instance.unregister(_playback);
    widget.onRegisterCloseGuard(null);
    _reload.dispose();
    _playback.dispose();
    _findReadySub();
    _editorActive.dispose();
    _editorController.dispose();
    _contentScroll.dispose();
    _generatorPage.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _playback.stopForLifecycle();
  }

  FileEntry? _resolveEntry() {
    final cursor = widget.store.cursorEntry.value;

    return cursor?.ghostOf ?? cursor;
  }

  Future<bool> _confirmClose() async {
    if (!mounted) return true;
    if (!_editorController.dirty.value) return true;
    final choice = await confirmUnsavedChanges(
      context,
      t.quickLook.unsavedMessage,
    );
    if (!mounted || choice == UnsavedChoice.cancel) return false;
    if (choice == UnsavedChoice.save) return await _editorController.save();

    return true;
  }

  void _showReloadSkipped() {
    if (!mounted) return;
    showToast(context: context, message: t.quickLook.reloadSkipped);
  }

  void _requestReload() => unawaited(_reload.request(context));

  void _toggleMarkdownRendered() =>
      setState(() => _markdownRendered = !_markdownRendered);

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
    if (!_renderedMarkdown) return;
    _pendingSearch = true;
    setState(() => _markdownRendered = false);
  }

  void _setCompact(bool value) {
    if (_compact == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compact == value) return;
      setState(() => _compact = value);
    });
  }

  void _syncPresentation(FileEntry? entry) {
    final key = entry?.realPath;
    if (_presentationKey == key) return;
    _presentationKey = key;
    _pendingSearch = false;
    _markdownRendered = true;
    _generatorPage.reset();
    _setCompact(defaultCompactFor(entry));
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (_) {
        final entry = _resolveEntry();
        _syncPresentation(entry);
        _reload.watch(entry);
        _reload.revision.value;
        final shown = _reload.shown(entry);
        _renderedMarkdown =
            shown != null &&
            markdownExts.contains(shown.extension) &&
            _markdownRendered &&
            GeneratorRegistry.instance.forExtension(shown.extension) == null;
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
                QuickLookHeader(
                  entry: entry,
                  compact: _compact,
                  showInfo: _showInfo,
                  onToggleInfo: () => setState(() => _showInfo = !_showInfo),
                  onClose: widget.onClose,
                  editorController: _editorController,
                  markdownRendered: _markdownRendered,
                  onToggleMarkdownView: _toggleMarkdownRendered,
                  onSearch: _openSearch,
                  onReload: QuickLookReloadController.canReload(entry)
                      ? _requestReload
                      : null,
                ),
                Container(height: 1, color: AppColors.bgDivider),
                Expanded(
                  child: QuickLookBody(
                    key: ValueKey('qlp#${_reload.generation}'),
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
            ),
            Positioned(
              top: 47,
              right: 14,
              child: QuickLookFindPopup(controller: _editorController),
            ),
          ],
        );
      },
    );
  }
}
