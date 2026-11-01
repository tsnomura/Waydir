import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/files/ctrl_wheel_zoom.dart';

void main() {
  Future<(List<int>, ScrollController)> pump(WidgetTester tester) async {
    final zooms = <int>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CtrlWheelZoom(
          onZoom: zooms.add,
          child: ListView.builder(
            controller: controller,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 30, child: Text('$i')),
          ),
        ),
      ),
    );

    return (zooms, controller);
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('ctrl+wheel zooms instead of scrolling', (tester) async {
    final (zooms, controller) = await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(tester, -40);
    await wheel(tester, 40);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(zooms, [1, -1]);
    expect(controller.offset, 0);
  });

  testWidgets('plain wheel scrolls and does not zoom', (tester) async {
    final (zooms, controller) = await pump(tester);

    await wheel(tester, 90);

    expect(zooms, isEmpty);
    expect(controller.offset, greaterThan(0));
  });
}
