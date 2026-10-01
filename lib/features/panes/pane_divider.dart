import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';
import 'shell_store.dart';

class PaneDivider extends StatefulWidget {
  final ShellStore shell;
  final double totalWidth;

  // No reach into the left pane at all — any reach there would overlap
  // that pane's own vertical scrollbar gutter (_kScrollbarGutterWidth in
  // file_view.dart), which sits flush against this same boundary and would
  // otherwise get swallowed by this divider's opaque hit area before the
  // scrollbar ever sees the pointer. The right pane has no scrollbar near
  // its left edge, so the full grab width goes there instead.
  static const double leftReach = 0.0;
  static const double rightReach = 18.0;
  static const double hitWidth = leftReach + rightReach;

  const PaneDivider({super.key, required this.shell, required this.totalWidth});

  @override
  State<PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<PaneDivider> {
  bool _hovered = false;
  double _startX = 0;
  double _startRatio = 0.5;

  static const double _lineWidth = 1;

  @override
  Widget build(BuildContext context) {
    final lineWidth = _hovered ? 3.0 : _lineWidth;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _startX = details.globalPosition.dx;
          _startRatio = widget.shell.splitRatio.value;
        },
        onPanUpdate: (details) {
          final dx = details.globalPosition.dx - _startX;
          widget.shell.setSplitRatio(_startRatio + dx / widget.totalWidth);
        },
        onDoubleTap: () {
          if (_hovered) widget.shell.swapActiveTabs();
        },
        child: SizedBox(
          width: PaneDivider.hitWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: PaneDivider.leftReach - lineWidth / 2,
                top: 0,
                bottom: 0,
                width: lineWidth,
                child: ColoredBox(
                  color: _hovered ? AppColors.accent : AppColors.bgDivider,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
