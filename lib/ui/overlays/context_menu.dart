import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:signals/signals_flutter.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icon.dart';
import 'popup_overlay.dart';

class ContextMenuItem {
  final IconData icon;
  final String label;
  final String action;
  final bool danger;
  final bool isToggle;
  final ReadonlySignal<bool>? toggleSignal;
  final String? shortcut;
  final bool enabled;

  /// When non-null this item opens a cascading submenu instead of firing an
  /// action on tap.
  final List<ContextMenuItem>? children;

  /// Optional path to a real icon file (PNG/SVG) shown instead of [icon].
  final String? iconPath;

  /// Optional widget shown instead of [icon]; used for tag colour dots.
  final Widget? leading;

  const ContextMenuItem({
    required this.icon,
    required this.label,
    required this.action,
    this.danger = false,
    this.isToggle = false,
    this.toggleSignal,
    this.shortcut,
    this.enabled = true,
    this.children,
    this.iconPath,
    this.leading,
  });

  static const divider = ContextMenuItem._divider();

  const ContextMenuItem._divider()
    : icon = const IconData(0),
      label = '',
      action = '__divider__',
      danger = false,
      isToggle = false,
      toggleSignal = null,
      shortcut = null,
      enabled = true,
      children = null,
      iconPath = null,
      leading = null;

  bool get isDivider => action == '__divider__';
  bool get hasChildren => children != null && children!.isNotEmpty;
}

class _MenuLayer {
  final OverlayEntry entry;
  final GlobalKey bodyKey;

  _MenuLayer(this.entry, this.bodyKey);

  bool contains(Offset position) {
    final box = bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;

    return (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }
}

class _MenuSession {
  final List<_MenuLayer> layers = [];
  late final VoidCallback dismissAll;
  bool armed = false;

  bool contains(Offset position) => layers.any((l) => l.contains(position));
}

final _sessions = <_MenuSession>{};
bool _globalHandlersInstalled = false;

void _installGlobalHandlersIfNeeded() {
  if (_globalHandlersInstalled) return;
  _globalHandlersInstalled = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  HardwareKeyboard.instance.addHandler(_onGlobalKey);
}

void _uninstallGlobalHandlersIfIdle() {
  if (!_globalHandlersInstalled || _sessions.isNotEmpty) return;
  _globalHandlersInstalled = false;
  GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
  HardwareKeyboard.instance.removeHandler(_onGlobalKey);
}

void _onGlobalPointer(PointerEvent event) {
  if (event is! PointerDownEvent) return;
  final outside = [
    for (final s in _sessions)
      if (s.armed && !s.contains(event.position)) s,
  ];
  for (final s in outside) {
    s.dismissAll();
  }
}

bool _onGlobalKey(KeyEvent event) {
  if (event is! KeyDownEvent ||
      event.logicalKey != LogicalKeyboardKey.escape ||
      _sessions.isEmpty) {
    return false;
  }
  dismissAllContextMenus();

  return true;
}

void dismissAllContextMenus() {
  for (final s in _sessions.toList()) {
    s.dismissAll();
  }
}

void showContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
  required void Function(String action) onSelect,
  bool keyboard = false,
  void Function(bool forward)? onRootHorizontalNav,
  VoidCallback? onClosed,
}) {
  final overlay = Overlay.of(context);
  final session = _MenuSession();
  final entries = session.layers;
  final previousFocus = keyboard ? FocusManager.instance.primaryFocus : null;
  Timer? pendingDismiss;

  void dismissAll({bool restoreFocus = true}) {
    pendingDismiss?.cancel();
    pendingDismiss = null;
    final hadEntries = entries.isNotEmpty;
    for (final l in entries) {
      if (l.entry.mounted) l.entry.remove();
    }
    entries.clear();
    _sessions.remove(session);
    _uninstallGlobalHandlersIfIdle();
    if (hadEntries) onClosed?.call();
    final restore = previousFocus;
    if (restoreFocus &&
        hadEntries &&
        restore != null &&
        restore.context != null) {
      restore.requestFocus();
    }
  }

  session.dismissAll = dismissAll;

  void dismissFrom(int depth) {
    while (entries.length > depth) {
      final l = entries.removeLast();
      if (l.entry.mounted) l.entry.remove();
    }
  }

  void dismissFromSoon(int depth) {
    pendingDismiss?.cancel();
    pendingDismiss = Timer(const Duration(milliseconds: 90), () {
      pendingDismiss = null;
      dismissFrom(depth);
    });
  }

  void cancelPendingDismiss() {
    pendingDismiss?.cancel();
    pendingDismiss = null;
  }

  void dismissFromNow(int depth) {
    cancelPendingDismiss();
    dismissFrom(depth);
  }

  void openMenu(
    int depth,
    Offset pos,
    List<ContextMenuItem> menuItems, {
    OverlayEntry? owner,
    FocusNode? parentFocus,
    bool fromKeyboard = false,
  }) {
    if (depth > 0 &&
        (entries.length < depth ||
            !identical(entries[depth - 1].entry, owner))) {
      return;
    }
    dismissFromNow(depth);
    final bodyKey = GlobalKey();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => PopupOverlay(
        position: pos,
        width: 180,
        autoDismiss: depth == 0,
        onDismiss: dismissAll,
        builder: (_) => _ContextMenuBody(
          key: bodyKey,
          items: menuItems,
          keyboard: keyboard,
          highlightFirst: depth == 0 || fromKeyboard,
          onRootHorizontalNav: depth == 0 ? onRootHorizontalNav : null,
          onRootMenuSwitch: depth == 0
              ? () => dismissAll(restoreFocus: false)
              : null,
          onKeyboardBack: depth == 0
              ? dismissAll
              : () {
                  if (entries.length < depth) return;
                  dismissFromNow(depth);
                  parentFocus?.requestFocus();
                },
          onEnterMenu: depth == 0 ? () {} : cancelPendingDismiss,
          onExitMenu: () => dismissFromSoon(depth == 0 ? 1 : depth),
          onCloseSubmenus: () => dismissFromNow(depth + 1),
          onScheduleCloseSubmenus: () => dismissFromSoon(depth + 1),
          onSelect: (action) {
            final item = menuItems.firstWhere(
              (i) => !i.isDivider && i.action == action,
              orElse: () => menuItems.first,
            );
            if (item.hasChildren) return;
            onSelect(action);
            if (!item.isToggle) dismissAll();
          },
          onOpenSubmenu: (item, rect, {fromFocus, fromKeyboard = false}) =>
              openMenu(
                depth + 1,
                Offset(rect.right - 4, rect.top),
                item.children!,
                owner: entry,
                parentFocus: fromFocus,
                fromKeyboard: fromKeyboard,
              ),
        ),
      ),
    );
    entries.add(_MenuLayer(entry, bodyKey));
    overlay.insert(entry);
  }

  _sessions.add(session);
  _installGlobalHandlersIfNeeded();
  openMenu(0, position, items);
  WidgetsBinding.instance.addPostFrameCallback((_) => session.armed = true);
}

typedef _OpenSubmenu =
    void Function(
      ContextMenuItem item,
      Rect tileRect, {
      FocusNode? fromFocus,
      bool fromKeyboard,
    });

class _ContextMenuBody extends StatefulWidget {
  final List<ContextMenuItem> items;
  final bool keyboard;
  final bool highlightFirst;
  final void Function(bool forward)? onRootHorizontalNav;
  final VoidCallback? onRootMenuSwitch;
  final VoidCallback onKeyboardBack;
  final VoidCallback onEnterMenu;
  final VoidCallback onExitMenu;
  final VoidCallback onCloseSubmenus;
  final VoidCallback onScheduleCloseSubmenus;
  final void Function(String action) onSelect;
  final _OpenSubmenu onOpenSubmenu;

  const _ContextMenuBody({
    super.key,
    required this.items,
    required this.keyboard,
    required this.highlightFirst,
    this.onRootHorizontalNav,
    this.onRootMenuSwitch,
    required this.onKeyboardBack,
    required this.onEnterMenu,
    required this.onExitMenu,
    required this.onCloseSubmenus,
    required this.onScheduleCloseSubmenus,
    required this.onSelect,
    required this.onOpenSubmenu,
  });

  @override
  State<_ContextMenuBody> createState() => _ContextMenuBodyState();
}

class _ContextMenuBodyState extends State<_ContextMenuBody> {
  final _focus = FocusNode(debugLabel: 'context-menu');
  late final _keys = [for (final _ in widget.items) GlobalKey()];
  int _highlight = -1;

  @override
  void initState() {
    super.initState();
    if (!widget.keyboard) return;
    if (widget.highlightFirst) _highlight = _step(-1, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool _selectable(int i) =>
      !widget.items[i].isDivider && widget.items[i].enabled;

  int _step(int from, int dir) {
    final n = widget.items.length;
    for (var k = 1; k <= n; k++) {
      final i = ((from + dir * k) % n + n) % n;
      if (_selectable(i)) return i;
    }

    return from;
  }

  void _openHighlightedSubmenu() {
    final box =
        _keys[_highlight].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onOpenSubmenu(
      widget.items[_highlight],
      box.localToGlobal(Offset.zero) & box.size,
      fromFocus: _focus,
      fromKeyboard: true,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    final item = _highlight >= 0 ? widget.items[_highlight] : null;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlight = _step(_highlight, 1));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onRootHorizontalNav != null && _highlight == _step(-1, 1)) {
        widget.onKeyboardBack();
      } else {
        setState(() => _highlight = _step(_highlight < 0 ? 0 : _highlight, -1));
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (item != null && item.hasChildren) {
        _openHighlightedSubmenu();
      } else if (widget.onRootHorizontalNav != null) {
        widget.onRootHorizontalNav!(true);
        widget.onRootMenuSwitch?.call();
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (widget.onRootHorizontalNav != null) {
        widget.onRootHorizontalNav!(false);
        widget.onRootMenuSwitch?.call();
      } else {
        widget.onKeyboardBack();
      }
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onKeyboardBack();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (item == null) return KeyEventResult.handled;
      if (item.hasChildren) {
        _openHighlightedSubmenu();
      } else {
        widget.onSelect(item.action);
      }
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (!widget.keyboard) return body;

    return Focus(focusNode: _focus, onKeyEvent: _onKey, child: body);
  }

  Widget _buildBody(BuildContext context) {
    final items = widget.items;

    return MouseRegion(
      onEnter: (_) => widget.onEnterMenu(),
      onExit: (_) => widget.onExitMenu(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
        child: IntrinsicWidth(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.asMap().entries.map((e) {
                  if (e.value.isDivider) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.bgDivider,
                      ),
                    );
                  }

                  return _ContextMenuItemTile(
                    key: _keys[e.key],
                    item: e.value,
                    highlighted: _highlight == e.key,
                    onHovered: widget.keyboard
                        ? () => setState(() => _highlight = e.key)
                        : null,
                    onTap: () => widget.onSelect(e.value.action),
                    onOpenSubmenu: (item, rect) => widget.onOpenSubmenu(
                      item,
                      rect,
                      fromFocus: widget.keyboard ? _focus : null,
                    ),
                    onCloseSubmenus: widget.onCloseSubmenus,
                    onScheduleCloseSubmenus: widget.onScheduleCloseSubmenus,
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextMenuItemTile extends StatefulWidget {
  final ContextMenuItem item;
  final bool highlighted;
  final VoidCallback? onHovered;
  final VoidCallback onTap;
  final VoidCallback onCloseSubmenus;
  final VoidCallback onScheduleCloseSubmenus;
  final void Function(ContextMenuItem item, Rect tileRect) onOpenSubmenu;

  const _ContextMenuItemTile({
    super.key,
    required this.item,
    this.highlighted = false,
    this.onHovered,
    required this.onTap,
    required this.onCloseSubmenus,
    required this.onScheduleCloseSubmenus,
    required this.onOpenSubmenu,
  });

  @override
  State<_ContextMenuItemTile> createState() => _ContextMenuItemTileState();
}

class _ContextMenuItemTileState extends State<_ContextMenuItemTile> {
  bool _hovered = false;

  void _openSubmenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    widget.onOpenSubmenu(widget.item, origin & box.size);
  }

  void _handleTap() {
    if (!widget.item.enabled) return;
    if (widget.item.hasChildren) {
      _openSubmenu();
    } else {
      widget.onTap();
    }
  }

  void _handleEnter() {
    setState(() => _hovered = true);
    widget.onHovered?.call();
    if (!widget.item.enabled) {
      widget.onCloseSubmenus();

      return;
    }
    if (widget.item.hasChildren) {
      _openSubmenu();
    } else {
      widget.onCloseSubmenus();
    }
  }

  void _handleExit() {
    setState(() => _hovered = false);
    if (widget.item.hasChildren) {
      widget.onScheduleCloseSubmenus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dangerColor = AppColors.danger;
    final hoverBg = item.danger
        ? dangerColor.withValues(alpha: 0.12)
        : AppColors.bgHoverStrong;
    final active = widget.onHovered != null ? widget.highlighted : _hovered;
    final fg = !item.enabled
        ? AppColors.fgMuted.withValues(alpha: 0.45)
        : active
        ? (item.danger ? dangerColor : AppColors.fg)
        : AppColors.fgMuted;

    return MouseRegion(
      cursor: item.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _handleEnter(),
      onExit: (_) => _handleExit(),
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active && item.enabled ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Row(
            children: [
              if (item.leading != null)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(child: item.leading),
                )
              else if (item.iconPath != null)
                AppIcon(path: item.iconPath, size: 16)
              else
                Icon(item.icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: context.txt.body.copyWith(color: fg),
              ),
              const Spacer(),
              if (item.shortcut != null) ...[
                const SizedBox(width: 16),
                Text(
                  item.shortcut!,
                  maxLines: 1,
                  softWrap: false,
                  style: context.txt.captionSmall.copyWith(
                    color: fg.withValues(alpha: 0.5),
                  ),
                ),
              ],
              if (item.toggleSignal != null) ...[
                const SizedBox(width: 8),
                SignalBuilder(
                  builder: (_) => _Checkbox(value: item.toggleSignal!.value),
                ),
              ],
              if (item.hasChildren) ...[
                const SizedBox(width: 8),
                Icon(WaydirIconsRegular.caretRight, size: 12, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool value;

  const _Checkbox({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: value ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: value ? AppColors.accent : AppColors.borderColor,
          width: 1,
        ),
      ),
      child: value
          ? Icon(WaydirIconsRegular.check, size: 10, color: Colors.white)
          : null,
    );
  }
}
