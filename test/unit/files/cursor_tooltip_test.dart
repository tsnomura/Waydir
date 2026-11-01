import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/files/cursor_tooltip.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool cursor}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CursorTooltip(
            message: 'full name.txt',
            showForCursor: cursor,
            child: const Text('full…txt'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows after the cursor delay and hides when it leaves', (
    tester,
  ) async {
    await pump(tester, cursor: false);
    await pump(tester, cursor: true);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('full name.txt'), findsNothing);

    await tester.pump(CursorTooltip.cursorDelay);
    await tester.pumpAndSettle();
    expect(find.text('full name.txt'), findsOneWidget);

    await pump(tester, cursor: false);
    await tester.pumpAndSettle();
    expect(find.text('full name.txt'), findsNothing);
  });

  testWidgets('a cursor that moves on before the delay shows nothing', (
    tester,
  ) async {
    await pump(tester, cursor: true);
    await tester.pump(const Duration(milliseconds: 200));
    await pump(tester, cursor: false);
    await tester.pump(CursorTooltip.cursorDelay);
    await tester.pumpAndSettle();

    expect(find.text('full name.txt'), findsNothing);
  });
}
