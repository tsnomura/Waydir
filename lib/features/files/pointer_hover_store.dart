import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals.dart';

class PointerHoverStore {
  PointerHoverStore._() {
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  static final instance = PointerHoverStore._();

  final suppressed = signal(false);

  static final _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !_modifiers.contains(event.logicalKey)) {
      if (!suppressed.value) suppressed.value = true;
    }

    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerHoverEvent || event is PointerMoveEvent) {
      if (suppressed.value) suppressed.value = false;
    }
  }
}
