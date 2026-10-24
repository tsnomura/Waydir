import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/widgets/app_modal.dart';
import '../../ui/widgets/floating_window_geometry.dart';
import '../../ui/widgets/markdown_body_view.dart';
import '../../ui/window/move_window.dart';
import '../../ui/window/window_buttons.dart';
import 'app_tutorial_pop_out.dart';

Future<void> showHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => const _HelpDialog(),
  );
}

class _HelpPage {
  final String Function() title;
  final String Function() body;
  final String? assetPath;

  const _HelpPage({required this.title, required this.body, this.assetPath});
}

class _HelpGroup {
  final String Function() title;
  final IconData icon;
  final List<_HelpPage> pages;

  const _HelpGroup({
    required this.title,
    required this.icon,
    required this.pages,
  });
}

final _groups = <_HelpGroup>[
  _HelpGroup(
    title: () => t.help.groups.gettingStarted.title,
    icon: WaydirIconsRegular.info,
    pages: [
      _HelpPage(
        title: () => t.help.groups.gettingStarted.welcome.title,
        body: () => t.help.groups.gettingStarted.welcome.body,
      ),
      _HelpPage(
        title: () => t.help.groups.gettingStarted.interface.title,
        body: () => t.help.groups.gettingStarted.interface.body,
      ),
      _HelpPage(
        title: () => t.help.groups.gettingStarted.keyboardBasics.title,
        body: () => t.help.groups.gettingStarted.keyboardBasics.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.navigating.title,
    icon: WaydirIconsRegular.compass,
    pages: [
      _HelpPage(
        title: () => t.help.groups.navigating.moving.title,
        body: () => t.help.groups.navigating.moving.body,
        assetPath: 'docs/gifs/navigating.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.navigating.breadcrumb.title,
        body: () => t.help.groups.navigating.breadcrumb.body,
      ),
      _HelpPage(
        title: () => t.help.groups.navigating.bookmarks.title,
        body: () => t.help.groups.navigating.bookmarks.body,
      ),
      _HelpPage(
        title: () => t.help.groups.navigating.drives.title,
        body: () => t.help.groups.navigating.drives.body,
      ),
      _HelpPage(
        title: () => t.help.groups.navigating.typeAhead.title,
        body: () => t.help.groups.navigating.typeAhead.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.tabsPanes.title,
    icon: WaydirIconsRegular.columns,
    pages: [
      _HelpPage(
        title: () => t.help.groups.tabsPanes.tabs.title,
        body: () => t.help.groups.tabsPanes.tabs.body,
        assetPath: 'docs/gifs/tabs.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.tabsPanes.dualPane.title,
        body: () => t.help.groups.tabsPanes.dualPane.body,
        assetPath: 'docs/gifs/dual_pane_copy.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.tabsPanes.compare.title,
        body: () => t.help.groups.tabsPanes.compare.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.selecting.title,
    icon: WaydirIconsRegular.selectionAll,
    pages: [
      _HelpPage(
        title: () => t.help.groups.selecting.basics.title,
        body: () => t.help.groups.selecting.basics.body,
        assetPath: 'docs/gifs/selection.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.selecting.pattern.title,
        body: () => t.help.groups.selecting.pattern.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.files.title,
    icon: WaydirIconsRegular.copy,
    pages: [
      _HelpPage(
        title: () => t.help.groups.files.operations.title,
        body: () => t.help.groups.files.operations.body,
        assetPath: 'docs/gifs/file_operations.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.files.dragDrop.title,
        body: () => t.help.groups.files.dragDrop.body,
      ),
      _HelpPage(
        title: () => t.help.groups.files.multiRename.title,
        body: () => t.help.groups.files.multiRename.body,
        assetPath: 'docs/gifs/multi_rename.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.files.archives.title,
        body: () => t.help.groups.files.archives.body,
        assetPath: 'docs/gifs/archive_browsing.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.files.openWith.title,
        body: () => t.help.groups.files.openWith.body,
      ),
      _HelpPage(
        title: () => t.help.groups.files.tags.title,
        body: () => t.help.groups.files.tags.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.previewing.title,
    icon: WaydirIconsRegular.eye,
    pages: [
      _HelpPage(
        title: () => t.help.groups.previewing.quickLook.title,
        body: () => t.help.groups.previewing.quickLook.body,
        assetPath: 'docs/gifs/quick_look_images.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.previewing.editor.title,
        body: () => t.help.groups.previewing.editor.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.searching.title,
    icon: WaydirIconsRegular.magnifyingGlass,
    pages: [
      _HelpPage(
        title: () => t.help.groups.searching.folder.title,
        body: () => t.help.groups.searching.folder.body,
        assetPath: 'docs/gifs/search.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.searching.function.title,
        body: () => t.help.groups.searching.function.body,
        assetPath: 'docs/gifs/function_search.gif',
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.commandPalette.title,
    icon: WaydirIconsRegular.magicWand,
    pages: [
      _HelpPage(
        title: () => t.help.groups.commandPalette.basics.title,
        body: () => t.help.groups.commandPalette.basics.body,
      ),
      _HelpPage(
        title: () => t.help.groups.commandPalette.files.title,
        body: () => t.help.groups.commandPalette.files.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.remote.title,
    icon: WaydirIconsRegular.hardDrive,
    pages: [
      _HelpPage(
        title: () => t.help.groups.remote.sftp.title,
        body: () => t.help.groups.remote.sftp.body,
        assetPath: 'docs/gifs/sftp.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.remote.network.title,
        body: () => t.help.groups.remote.network.body,
      ),
      _HelpPage(
        title: () => t.help.groups.remote.terminal.title,
        body: () => t.help.groups.remote.terminal.body,
        assetPath: 'docs/gifs/terminal.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.remote.git.title,
        body: () => t.help.groups.remote.git.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.customization.title,
    icon: WaydirIconsRegular.palette,
    pages: [
      _HelpPage(
        title: () => t.help.groups.customization.themes.title,
        body: () => t.help.groups.customization.themes.body,
        assetPath: 'docs/gifs/customization.gif',
      ),
      _HelpPage(
        title: () => t.help.groups.customization.shortcuts.title,
        body: () => t.help.groups.customization.shortcuts.body,
      ),
      _HelpPage(
        title: () => t.help.groups.customization.plugins.title,
        body: () => t.help.groups.customization.plugins.body,
      ),
    ],
  ),
  _HelpGroup(
    title: () => t.help.groups.resources.title,
    icon: WaydirIconsRegular.bookmarkSimple,
    pages: [
      _HelpPage(
        title: () => t.help.groups.resources.links.title,
        body: () => t.help.groups.resources.links.body,
      ),
    ],
  ),
];

class _PageRef {
  final int group;
  final int page;

  const _PageRef(this.group, this.page);
}

final _flatPages = <_PageRef>[
  for (var g = 0; g < _groups.length; g++)
    for (var p = 0; p < _groups[g].pages.length; p++) _PageRef(g, p),
];

/// Tree/page navigation shared by the Help dialog and its standalone
/// `--app-tutorial` window counterpart ([HelpTutorialContent]): which page is
/// selected, which groups are expanded, and arrow-key browsing between them.
mixin _HelpNavigation<T extends StatefulWidget> on State<T> {
  int selected = 0;
  late final Set<int> expandedGroups = {
    for (var i = 0; i < _groups.length; i++) i,
  };

  _PageRef get current => _flatPages[selected];

  KeyEventResult handleNavigationKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      selectFlat((selected + 1) % _flatPages.length);

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      selectFlat((selected - 1 + _flatPages.length) % _flatPages.length);

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => expandedGroups.remove(current.group));

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => expandedGroups.add(current.group));

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void selectFlat(int index) {
    setState(() {
      selected = index;
      expandedGroups.add(_flatPages[index].group);
    });
  }

  void selectPage(int group, int page) {
    final index = _flatPages.indexWhere(
      (ref) => ref.group == group && ref.page == page,
    );
    if (index >= 0) setState(() => selected = index);
  }

  void toggleGroup(int group) {
    setState(() {
      if (expandedGroups.contains(group)) {
        expandedGroups.remove(group);
      } else {
        expandedGroups.add(group);
      }
    });
  }
}

class _HelpDialog extends StatefulWidget {
  const _HelpDialog();

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog>
    with FloatingWindowGeometry<_HelpDialog>, _HelpNavigation<_HelpDialog> {
  @override
  double get minWindowWidth => 640;

  @override
  double get minWindowHeight => 420;

  @override
  Rect computeInitialRect(Size screen) {
    final width = screen.width.clamp(760.0, 1040.0).toDouble();
    final height = (screen.height * 0.94).clamp(520.0, 1100.0).toDouble();
    final originX = (screen.width - width) / 2;
    final originY = (screen.height - height) / 2;

    return Rect.fromLTWH(originX, originY, width, height);
  }

  void _popOut() {
    unawaited(
      AppTutorialPopOut.open().then((opened) {
        if (!mounted) return;
        if (opened) {
          Navigator.of(context).pop();
        } else {
          showToast(context: context, message: t.help.popOutUnavailable);
        }
      }),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();

      return KeyEventResult.handled;
    }

    return handleNavigationKey(event);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final rect = ensureRect(screen);
    final ref = current;
    final page = _groups[ref.group].pages[ref.page];

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: rect,
            child: AppModal(
              icon: WaydirIconsRegular.info,
              title: t.help.title,
              width: rect.width,
              height: rect.height,
              onClose: () => Navigator.of(context).pop(),
              onTitleBarPanStart: handleDragStart,
              onTitleBarPanUpdate: handleDragUpdate,
              titleBarActions: [_HelpPopOutButton(onTap: _popOut)],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 248,
                    child: _HelpTree(
                      expanded: expandedGroups,
                      selected: ref,
                      onToggleGroup: toggleGroup,
                      onSelectPage: selectPage,
                    ),
                  ),
                  Container(width: 1, color: AppColors.bgDivider),
                  Expanded(
                    child: _HelpPageView(key: ValueKey(selected), page: page),
                  ),
                ],
              ),
            ),
          ),
          ...resizeHandles(rect),
        ],
      ),
    );
  }
}

/// Standalone-window counterpart of [_HelpDialog] for the `--app-tutorial`
/// launch flag: the same tree and page content, without the modal chrome —
/// there's no parent window to show a dialog over in a standalone process.
class HelpTutorialContent extends StatefulWidget {
  const HelpTutorialContent({super.key});

  @override
  State<HelpTutorialContent> createState() => _HelpTutorialContentState();
}

class _HelpTutorialContentState extends State<HelpTutorialContent>
    with _HelpNavigation<HelpTutorialContent> {
  @override
  Widget build(BuildContext context) {
    final ref = current;
    final page = _groups[ref.group].pages[ref.page];

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => handleNavigationKey(event),
      child: Column(
        children: [
          const _HelpTutorialTitleBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 248,
                  child: _HelpTree(
                    expanded: expandedGroups,
                    selected: ref,
                    onToggleGroup: toggleGroup,
                    onSelectPage: selectPage,
                  ),
                ),
                Container(width: 1, color: AppColors.bgDivider),
                Expanded(
                  child: _HelpPageView(key: ValueKey(selected), page: page),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal window chrome for the standalone `--app-tutorial` process: this
/// window has no OS title bar (the app always draws its own, undecorated),
/// so without this it could not be moved or closed.
class _HelpTutorialTitleBar extends StatelessWidget {
  const _HelpTutorialTitleBar();

  static final _iconColor = AppColors.fgMuted;
  static final _btnColors = WindowButtonColors(
    iconNormal: _iconColor,
    iconMouseOver: AppColors.fg,
    mouseOver: AppColors.bgHover,
    mouseDown: AppColors.bgSurface,
  );
  static final _closeColors = WindowButtonColors(
    iconNormal: _iconColor,
    iconMouseOver: Colors.white,
    mouseOver: AppColors.windowCloseHover,
    mouseDown: AppColors.windowClosePressed,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.bgSidebar,
        border: Border(bottom: BorderSide(color: AppColors.bgDivider)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(WaydirIconsRegular.info, size: 14, color: _iconColor),
          const SizedBox(width: 8),
          Text(t.help.title, style: context.txt.captionSmall),
          const Expanded(child: MoveWindow()),
          MinimizeWindowButton(colors: _btnColors, animate: false),
          MaximizeWindowButton(colors: _btnColors, animate: false),
          CloseWindowButton(colors: _closeColors, animate: false),
        ],
      ),
    );
  }
}

class _HelpPopOutButton extends StatefulWidget {
  final VoidCallback onTap;

  const _HelpPopOutButton({required this.onTap});

  @override
  State<_HelpPopOutButton> createState() => _HelpPopOutButtonState();
}

class _HelpPopOutButtonState extends State<_HelpPopOutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.help.popOut,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.bgHover : Colors.transparent,
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(
              WaydirIconsRegular.arrowSquareOut,
              size: 14,
              color: _hovered ? AppColors.fg : AppColors.fgMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpTree extends StatelessWidget {
  final Set<int> expanded;
  final _PageRef selected;
  final ValueChanged<int> onToggleGroup;
  final void Function(int group, int page) onSelectPage;

  const _HelpTree({
    required this.expanded,
    required this.selected,
    required this.onToggleGroup,
    required this.onSelectPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgSidebar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (var g = 0; g < _groups.length; g++) ...[
            _GroupRow(
              group: _groups[g],
              expanded: expanded.contains(g),
              onTap: () => onToggleGroup(g),
            ),
            if (expanded.contains(g))
              for (var p = 0; p < _groups[g].pages.length; p++)
                _PageRow(
                  page: _groups[g].pages[p],
                  selected: selected.group == g && selected.page == p,
                  onTap: () => onSelectPage(g, p),
                ),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatefulWidget {
  final _HelpGroup group;
  final bool expanded;
  final VoidCallback onTap;

  const _GroupRow({
    required this.group,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? AppColors.fg : AppColors.fgMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.expanded
                    ? WaydirIconsRegular.caretDown
                    : WaydirIconsRegular.caretRight,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 7),
              Icon(widget.group.icon, size: 15, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.group.title(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.txt.rowEmphasis.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageRow extends StatefulWidget {
  final _HelpPage page;
  final bool selected;
  final VoidCallback onTap;

  const _PageRow({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PageRow> createState() => _PageRowState();
}

class _PageRowState extends State<_PageRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.fgAccent
        : _hovered
        ? AppColors.fg
        : AppColors.fgMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 40, right: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.bgSelected
                : _hovered
                ? AppColors.bgHover
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.selected ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.page.title(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.txt.row.copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpPageView extends StatelessWidget {
  final _HelpPage page;

  const _HelpPageView({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(page.title(), style: context.txt.pageTitle),
          const SizedBox(height: 10),
          _HelpMarkdown(data: page.body()),
          if (page.assetPath != null) ...[
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  page.assetPath!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpMarkdown extends StatelessWidget {
  final String data;

  const _HelpMarkdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final base = context.txt.bodyMuted.copyWith(height: 1.45);
    final emphasis = context.txt.bodyEmphasis.copyWith(height: 1.45);
    final mono = context.txt.keyCap.copyWith(
      color: AppColors.fg,
      backgroundColor: AppColors.bgInput,
    );

    return MarkdownBodyView(
      data: sanitizeHtml(data),
      onTapLink: _openUrl,
      styleSheet: MarkdownStyleSheet(
        p: base,
        listBullet: base,
        strong: emphasis,
        em: base.copyWith(fontStyle: FontStyle.italic),
        a: base.copyWith(color: AppColors.fgAccent),
        code: mono,
        blockSpacing: 8,
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  if (Platform.isLinux) {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', [url], mode: ProcessStartMode.detached);
  } else if (Platform.isWindows) {
    await Process.start('cmd', [
      '/c',
      'start',
      url,
    ], mode: ProcessStartMode.detached);
  }
}
