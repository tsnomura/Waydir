import 'package:flutter/material.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:signals/signals_flutter.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/context_menu.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import '../drives/drive_store.dart';
import 'tab_state.dart';
import 'tabs_store.dart';

enum TabLocationKind { local, removable, network, sftp }

TabLocationKind classifyTabLocation(String path) {
  if (PlatformPaths.isSftpUri(path)) return TabLocationKind.sftp;
  if (PlatformPaths.isRemoteUri(path) || PlatformPaths.isNetworkPath(path)) {
    return TabLocationKind.network;
  }
  for (final drive in driveStore.drives.value) {
    final mountPoint = drive.mountPoint;
    if (mountPoint == null) continue;
    final prefix = mountPoint.endsWith(PlatformPaths.separator)
        ? mountPoint
        : '$mountPoint${PlatformPaths.separator}';
    if (path != mountPoint && !path.startsWith(prefix)) continue;
    if (drive.isNetwork) return TabLocationKind.network;
    if (drive.isRemovable) return TabLocationKind.removable;

    return TabLocationKind.local;
  }

  return TabLocationKind.local;
}

IconData _iconForTabLocation(TabLocationKind kind) => switch (kind) {
  TabLocationKind.local => WaydirIconsRegular.folder,
  TabLocationKind.removable => WaydirIconsRegular.usb,
  TabLocationKind.network => WaydirIconsRegular.treeStructure,
  TabLocationKind.sftp => WaydirIconsRegular.desktopTower,
};

final _driveLetterPattern = RegExp(r'^([A-Za-z]):[\\/]');

String? tabDriveLetter(String path) {
  if (!PlatformPaths.isWindows) return null;

  return _driveLetterPattern.firstMatch(path)?.group(1)?.toUpperCase();
}

class TabChip extends StatefulWidget {
  final TabState tab;
  final int index;
  final TabsStore tabsStore;
  final void Function(String tabId)? onMoveToOtherPane;

  const TabChip({
    super.key,
    required this.tab,
    required this.index,
    required this.tabsStore,
    this.onMoveToOtherPane,
  });

  @override
  State<TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<TabChip> {
  bool _hovered = false;

  void _showContextMenu(Offset position) {
    final canMove = widget.tabsStore.tabs.value.length > 1;
    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          icon: WaydirIconsRegular.arrowsLeftRight,
          label: t.menu.moveTabToOtherPane,
          action: 'move_to_other_pane',
          enabled: canMove && widget.onMoveToOtherPane != null,
        ),
      ],
      onSelect: (action) {
        if (action == 'move_to_other_pane') {
          widget.onMoveToOtherPane?.call(widget.tab.id);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isActive = widget.tabsStore.activeIndex.value == widget.index;
        final title = widget.tab.title.value;
        final fullPath = widget.tab.store.currentPath.value;
        final canClose = widget.tabsStore.tabs.value.length > 1;
        final locationKind = classifyTabLocation(fullPath);
        final driveLetter = tabDriveLetter(fullPath);

        Color bg;
        Color fg;
        if (isActive) {
          bg = AppColors.bgHover;
          fg = AppColors.fg;
        } else if (_hovered) {
          bg = AppColors.bg;
          fg = AppColors.fg;
        } else {
          bg = Colors.transparent;
          fg = AppColors.fgMuted;
        }

        final border = Border(
          right: BorderSide(
            color: (_hovered && !isActive)
                ? Colors.transparent
                : AppColors.bgDivider,
            width: 1,
          ),
        );

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => widget.tabsStore.selectTab(widget.index),
            onTertiaryTapDown: canClose
                ? (_) => widget.tabsStore.closeTab(widget.tab.id)
                : null,
            onSecondaryTapUp: (details) =>
                _showContextMenu(details.globalPosition),
            child: Tooltip(
              message: fullPath,
              child: Container(
                height: 30,
                constraints: const BoxConstraints(minWidth: 72, maxWidth: 220),
                decoration: BoxDecoration(color: bg, border: border),
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconForTabLocation(locationKind),
                      size: 14,
                      color: isActive ? AppColors.accent : fg,
                    ),
                    if (driveLetter != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        driveLetter,
                        style: context.txt.keyCap.copyWith(
                          fontSize: 9,
                          color: AppColors.fgSubtle,
                        ),
                      ),
                    ],
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                        style: context.txt.row.copyWith(
                          color: fg,
                          fontWeight: isActive
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: (canClose && (_hovered || isActive))
                          ? _CloseButton(
                              onTap: () =>
                                  widget.tabsStore.closeTab(widget.tab.id),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgDivider : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Icon(
            WaydirIconsRegular.x,
            size: 11,
            color: _hovered ? AppColors.fg : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}
