import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/models/file_entry.dart';
import '../../features/navigation/navigation_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'code_editor.dart';
import 'generators/generator_page_controller.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_content.dart';

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
  String? _presentationKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generatorPage.onManualChange = _playback.onManualPageChange;
    final entry = _resolveEntry();
    _compact = defaultCompactFor(entry);
    _presentationKey = entry?.realPath;
    widget.onRegisterCloseGuard(_confirmClose);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.onRegisterCloseGuard(null);
    _playback.dispose();
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

  void _toggleMarkdownRendered() =>
      setState(() => _markdownRendered = !_markdownRendered);

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
        _playback.sync(entry, _generatorPage, blocked: false);

        return Column(
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
    );
  }
}
