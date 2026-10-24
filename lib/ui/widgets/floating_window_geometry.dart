import 'package:flutter/material.dart';

enum ResizeEdge { n, s, e, w, ne, nw, se, sw }

/// Shared drag-to-move / edge-and-corner-resize [Rect] tracking for a
/// floating "window" hosted inside a modal route — used by Quick Look's
/// panel and the Help dialog so the geometry logic isn't duplicated.
///
/// The host [State] owns [computeInitialRect] (its own default size/position
/// logic) and renders [rect] plus [resizeHandles] itself; this mixin only
/// tracks the geometry and the drag/resize gesture math.
mixin FloatingWindowGeometry<T extends StatefulWidget> on State<T> {
  Rect? rect;
  Offset? _dragAnchor;
  Rect? _dragStartRect;

  double get minWindowWidth => 420;
  double get minWindowHeight => 320;

  /// The window's default size/position the first time it's shown, before
  /// any drag or resize. Called with the current screen size.
  Rect computeInitialRect(Size screen);

  Rect ensureRect(Size screen) =>
      rect ??= clampToScreen(computeInitialRect(screen), screen);

  Rect clampToScreen(Rect value, Size screen) {
    final width = value.width.clamp(
      minWindowWidth,
      screen.width.clamp(minWindowWidth, double.infinity),
    );
    final height = value.height.clamp(
      minWindowHeight,
      screen.height.clamp(minWindowHeight, double.infinity),
    );
    final left = value.left.clamp(
      0.0,
      (screen.width - width).clamp(0.0, screen.width),
    );
    final top = value.top.clamp(
      0.0,
      (screen.height - height).clamp(0.0, screen.height),
    );

    return Rect.fromLTWH(left, top, width, height);
  }

  void handleDragStart(DragStartDetails details) {
    _dragAnchor = details.globalPosition;
    _dragStartRect = rect;
  }

  void handleDragUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor;
    final startRect = _dragStartRect;
    if (anchor == null || startRect == null) return;
    final delta = details.globalPosition - anchor;
    final screen = MediaQuery.of(context).size;
    setState(() => rect = clampToScreen(startRect.shift(delta), screen));
  }

  void handleResizeStart(DragStartDetails details) {
    _dragAnchor = details.globalPosition;
    _dragStartRect = rect;
  }

  void handleResizeUpdate(ResizeEdge edge, DragUpdateDetails details) {
    final anchor = _dragAnchor;
    final startRect = _dragStartRect;
    if (anchor == null || startRect == null) return;
    final delta = details.globalPosition - anchor;
    final screen = MediaQuery.of(context).size;
    setState(() => rect = resizeRect(startRect, edge, delta, screen));
  }

  Rect resizeRect(Rect start, ResizeEdge edge, Offset delta, Size screen) {
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;
    const west = {ResizeEdge.w, ResizeEdge.nw, ResizeEdge.sw};
    const east = {ResizeEdge.e, ResizeEdge.ne, ResizeEdge.se};
    const north = {ResizeEdge.n, ResizeEdge.nw, ResizeEdge.ne};
    const south = {ResizeEdge.s, ResizeEdge.sw, ResizeEdge.se};
    if (west.contains(edge)) left += delta.dx;
    if (east.contains(edge)) right += delta.dx;
    if (north.contains(edge)) top += delta.dy;
    if (south.contains(edge)) bottom += delta.dy;
    if (right - left < minWindowWidth) {
      if (west.contains(edge)) {
        left = right - minWindowWidth;
      } else {
        right = left + minWindowWidth;
      }
    }
    if (bottom - top < minWindowHeight) {
      if (north.contains(edge)) {
        top = bottom - minWindowHeight;
      } else {
        bottom = top + minWindowHeight;
      }
    }
    left = left.clamp(0.0, screen.width - minWindowWidth);
    top = top.clamp(0.0, screen.height - minWindowHeight);
    right = right.clamp(left + minWindowWidth, screen.width);
    bottom = bottom.clamp(top + minWindowHeight, screen.height);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  List<Widget> resizeHandles(Rect rect) => [
    for (final edge in ResizeEdge.values) _resizeHandle(edge, rect),
  ];

  Widget _resizeHandle(ResizeEdge edge, Rect rect) {
    const thickness = 8.0;
    const corner = 12.0;
    late Rect handleRect;
    late MouseCursor cursor;
    switch (edge) {
      case ResizeEdge.n:
        handleRect = Rect.fromLTWH(
          rect.left + corner,
          rect.top - thickness / 2,
          rect.width - corner * 2,
          thickness,
        );
        cursor = SystemMouseCursors.resizeUpDown;
      case ResizeEdge.s:
        handleRect = Rect.fromLTWH(
          rect.left + corner,
          rect.bottom - thickness / 2,
          rect.width - corner * 2,
          thickness,
        );
        cursor = SystemMouseCursors.resizeUpDown;
      case ResizeEdge.w:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.top + corner,
          thickness,
          rect.height - corner * 2,
        );
        cursor = SystemMouseCursors.resizeLeftRight;
      case ResizeEdge.e:
        handleRect = Rect.fromLTWH(
          rect.right - thickness / 2,
          rect.top + corner,
          thickness,
          rect.height - corner * 2,
        );
        cursor = SystemMouseCursors.resizeLeftRight;
      case ResizeEdge.nw:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.top - thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeEdge.se:
        handleRect = Rect.fromLTWH(
          rect.right - corner + thickness / 2,
          rect.bottom - corner + thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeEdge.ne:
        handleRect = Rect.fromLTWH(
          rect.right - corner + thickness / 2,
          rect.top - thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
      case ResizeEdge.sw:
        handleRect = Rect.fromLTWH(
          rect.left - thickness / 2,
          rect.bottom - corner + thickness / 2,
          corner,
          corner,
        );
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
    }

    return Positioned.fromRect(
      rect: handleRect,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: handleResizeStart,
          onPanUpdate: (details) => handleResizeUpdate(edge, details),
        ),
      ),
    );
  }
}
