import 'dart:ui';

/// Tracks the mouse cursor's last-known global position so a keyboard
/// shortcut (e.g. F10) can open a popup there instead of at a fixed spot.
class CursorPosition {
  CursorPosition._();

  static Offset? lastKnownPosition;
}
