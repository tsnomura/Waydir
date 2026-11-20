import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/quick_look_content.dart';

void main() {
  test('info stacks below the preview in a tall, narrow area', () {
    expect(stacksInfoBelow(const Size(420, 900)), isTrue);
  });

  test('info stays beside the preview in wide or short areas', () {
    expect(stacksInfoBelow(const Size(1200, 1400)), isFalse);
    expect(stacksInfoBelow(const Size(800, 300)), isFalse);
    expect(stacksInfoBelow(const Size(420, double.infinity)), isFalse);
  });
}
