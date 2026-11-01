import 'dart:async';

import 'package:flutter/material.dart';

class CursorTooltip extends StatefulWidget {
  static const cursorDelay = Duration(milliseconds: 600);
  static const hoverDelay = Duration(milliseconds: 500);

  final String message;
  final bool showForCursor;
  final Widget child;

  const CursorTooltip({
    super.key,
    required this.message,
    required this.showForCursor,
    required this.child,
  });

  @override
  State<CursorTooltip> createState() => _CursorTooltipState();
}

class _CursorTooltipState extends State<CursorTooltip> {
  final _tooltipKey = GlobalKey<TooltipState>();
  Timer? _timer;
  bool _shownByCursor = false;

  @override
  void initState() {
    super.initState();
    if (widget.showForCursor) _schedule();
  }

  @override
  void didUpdateWidget(CursorTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showForCursor && !oldWidget.showForCursor) {
      _schedule();
    } else if (!widget.showForCursor && oldWidget.showForCursor) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(CursorTooltip.cursorDelay, () {
      if (!mounted || !widget.showForCursor) return;
      _shownByCursor =
          _tooltipKey.currentState?.ensureTooltipVisible() ?? false;
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (_shownByCursor) {
      _shownByCursor = false;
      Tooltip.dismissAllToolTips();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      waitDuration: CursorTooltip.hoverDelay,
      child: widget.child,
    );
  }
}
