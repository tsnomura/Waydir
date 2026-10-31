import 'package:flutter/services.dart';

final _textEditingKeys = {
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyV,
  LogicalKeyboardKey.keyX,
  LogicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyZ,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.end,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.delete,
  LogicalKeyboardKey.insert,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.space,
};

final _functionKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

bool passesThroughTextInput(
  LogicalKeyboardKey key, {
  required bool control,
  required bool alt,
  required bool meta,
}) {
  if (_textEditingKeys.contains(key)) return false;
  if (_functionKeys.contains(key)) return true;

  return control || alt || meta;
}
