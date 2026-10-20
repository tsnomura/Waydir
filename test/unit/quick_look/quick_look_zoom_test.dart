import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/quick_look_zoom.dart';

void main() {
  final listKey = GlobalKey();

  Widget app() => MaterialApp(
    home: Scaffold(
      body: QuickLookZoomArea(
        child: ListView(
          key: listKey,
          children: [for (var i = 0; i < 200; i++) Text('line $i')],
        ),
      ),
    ),
  );

  double scaleOf(WidgetTester tester) =>
      MediaQuery.textScalerOf(tester.element(find.byKey(listKey))).scale(1);

  double offsetOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  late TestPointer pointer;

  setUp(() => pointer = TestPointer(1, PointerDeviceKind.mouse));

  Future<void> wheel(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byKey(listKey));
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('Ctrl+wheel zooms the text and does not scroll', (tester) async {
    await tester.pumpWidget(app());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await wheel(tester, -100);

    expect(scaleOf(tester), greaterThan(1.0));
    expect(offsetOf(tester), 0);

    await wheel(tester, 100);
    await wheel(tester, 100);
    expect(scaleOf(tester), lessThan(1.0));
    expect(offsetOf(tester), 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('a plain wheel scrolls and keeps the zoom', (tester) async {
    await tester.pumpWidget(app());

    await wheel(tester, 100);

    expect(scaleOf(tester), 1.0);
    expect(offsetOf(tester), greaterThan(0));
  });
}
