import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class CtrlWheelZoom extends SingleChildRenderObjectWidget {
  final void Function(int direction) onZoom;

  const CtrlWheelZoom({super.key, required this.onZoom, super.child});

  @override
  RenderCtrlWheelZoom createRenderObject(BuildContext context) =>
      RenderCtrlWheelZoom(onZoom);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCtrlWheelZoom renderObject,
  ) {
    renderObject.onZoom = onZoom;
  }
}

class RenderCtrlWheelZoom extends RenderProxyBox {
  void Function(int direction) onZoom;

  RenderCtrlWheelZoom(this.onZoom);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);

    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => onZoom(dy < 0 ? 1 : -1),
    );
  }
}
