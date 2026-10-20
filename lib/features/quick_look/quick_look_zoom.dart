import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuickLookZoomArea extends StatefulWidget {
  final Widget child;

  const QuickLookZoomArea({super.key, required this.child});

  @override
  State<QuickLookZoomArea> createState() => _QuickLookZoomAreaState();
}

class _QuickLookZoomAreaState extends State<QuickLookZoomArea> {
  static const _min = 0.5;
  static const _max = 3.0;
  static const _step = 1.1;

  double _scale = 1.0;
  bool _ctrl = HardwareKeyboard.instance.isControlPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl != _ctrl && mounted) setState(() => _ctrl = ctrl);

    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final next = (dy < 0 ? _scale * _step : _scale / _step).clamp(_min, _max);
      if (next != _scale) setState(() => _scale = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onPointerSignal,
      child: IgnorePointer(
        ignoring: _ctrl,
        child: MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(media.textScaler.scale(1) * _scale),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
