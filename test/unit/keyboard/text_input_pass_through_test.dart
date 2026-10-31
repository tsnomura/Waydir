import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/keyboard/text_input_pass_through.dart';

void main() {
  bool passes(
    LogicalKeyboardKey key, {
    bool control = false,
    bool alt = false,
    bool meta = false,
  }) => passesThroughTextInput(key, control: control, alt: alt, meta: meta);

  test('plain and shifted keys stay with the text box', () {
    expect(passes(LogicalKeyboardKey.keyG), isFalse);
    expect(passes(LogicalKeyboardKey.digit1), isFalse);
  });

  test('modifier chords pass through', () {
    expect(passes(LogicalKeyboardKey.keyG, control: true, alt: true), isTrue);
    expect(passes(LogicalKeyboardKey.keyB, control: true), isTrue);
    expect(passes(LogicalKeyboardKey.digit2, meta: true), isTrue);
  });

  test('text editing keys never pass through', () {
    expect(passes(LogicalKeyboardKey.keyA, control: true), isFalse);
    expect(passes(LogicalKeyboardKey.keyZ, control: true), isFalse);
    expect(passes(LogicalKeyboardKey.arrowRight, control: true), isFalse);
    expect(passes(LogicalKeyboardKey.backspace, control: true), isFalse);
    expect(passes(LogicalKeyboardKey.delete), isFalse);
  });

  test('function keys pass through without modifiers', () {
    expect(passes(LogicalKeyboardKey.f8), isTrue);
  });
}
