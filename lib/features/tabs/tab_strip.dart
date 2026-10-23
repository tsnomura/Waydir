import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:signals/signals_flutter.dart';
import '../../ui/theme/app_theme.dart';
import 'tab_chip.dart';
import 'tabs_store.dart';

const _kScrollStep = 120.0;

class TabStrip extends StatefulWidget {
  final TabsStore tabsStore;
  final bool isActive;
  final void Function(String tabId)? onMoveToOtherPane;

  const TabStrip({
    super.key,
    required this.tabsStore,
    this.isActive = true,
    this.onMoveToOtherPane,
  });

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // `ScrollPosition.maxScrollExtent` null-check-asserts internally until the
  // first layout has actually measured the scrollable's contents — true
  // right after this widget mounts, before `hasClients` alone would suggest.
  bool get _hasMetrics =>
      _scrollController.hasClients &&
      _scrollController.position.hasContentDimensions;

  void _scrollBy(double delta) {
    if (!_hasMetrics) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollBy(delta);
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final tabs = widget.tabsStore.tabs.value;

        return DragTarget<DraggedTabPayload>(
          onWillAcceptWithDetails: (details) =>
              !tabs.any((t) => t.id == details.data.tabId),
          onAcceptWithDetails: (details) =>
              details.data.moveToOtherPane(details.data.tabId),
          builder: (context, candidateData, rejectedData) => Container(
            height: 30,
            decoration: BoxDecoration(
              color: widget.isActive ? AppColors.bgSidebar : AppColors.bg,
              border: Border(
                bottom: BorderSide(color: AppColors.bgDivider),
                top: candidateData.isNotEmpty
                    ? BorderSide(color: AppColors.accent, width: 2)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, _) {
                    if (!_hasMetrics ||
                        _scrollController.position.pixels <= 0) {
                      return const SizedBox.shrink();
                    }

                    return _ScrollButton(
                      icon: WaydirIconsRegular.caretLeft,
                      onTap: () => _scrollBy(-_kScrollStep),
                    );
                  },
                ),
                Expanded(
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      itemCount: tabs.length,
                      onReorderItem: widget.tabsStore.reorderTab,
                      itemBuilder: (context, index) {
                        final tab = tabs[index];

                        return ReorderableDragStartListener(
                          key: ValueKey('tab:${tab.id}'),
                          index: index,
                          child: TabChip(
                            tab: tab,
                            index: index,
                            tabsStore: widget.tabsStore,
                            onMoveToOtherPane: widget.onMoveToOtherPane,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, _) {
                    if (!_hasMetrics ||
                        _scrollController.position.pixels >=
                            _scrollController.position.maxScrollExtent) {
                      return const SizedBox.shrink();
                    }

                    return _ScrollButton(
                      icon: WaydirIconsRegular.caretRight,
                      onTap: () => _scrollBy(_kScrollStep),
                    );
                  },
                ),
                _AddButton(
                  onTap: () {
                    final activePath = widget
                        .tabsStore
                        .activeTab
                        .value
                        .store
                        .currentPath
                        .value;
                    widget.tabsStore.addTab(activePath);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScrollButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScrollButton({required this.icon, required this.onTap});

  @override
  State<_ScrollButton> createState() => _ScrollButtonState();
}

class _ScrollButtonState extends State<_ScrollButton> {
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
          width: 20,
          height: 30,
          alignment: Alignment.center,
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 12,
            color: _hovered ? AppColors.fg : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
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
          width: 28,
          height: 30,
          alignment: Alignment.center,
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          child: Icon(
            WaydirIconsRegular.plus,
            size: 14,
            color: _hovered ? AppColors.fg : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}
