import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/quick_look_common.dart';

void main() {
  testWidgets('does not keep showing the previous cacheKey\'s data while a new '
      'cacheKey is still loading '
      '(regression: Quick Look header switches file but body stays on the '
      'previous one until the next reload completes)', (tester) async {
    final completers = <String, Completer<String>>{
      'a': Completer<String>()..complete('data-a'),
      'b': Completer<String>(),
    };

    Widget buildFor(String cacheKey) {
      return MaterialApp(
        home: AsyncRetain<String>(
          cacheKey: cacheKey,
          loader: () => completers[cacheKey]!.future,
          loading: const Text('loading'),
          builder: (data) => Text(data),
        ),
      );
    }

    await tester.pumpWidget(buildFor('a'));
    await tester.pump();
    expect(find.text('data-a'), findsOneWidget);

    await tester.pumpWidget(buildFor('b'));
    await tester.pump();
    expect(
      find.text('data-a'),
      findsNothing,
      reason:
          'must not keep rendering the previous cacheKey\'s stale data '
          'while the new cacheKey is still loading',
    );
    expect(find.text('loading'), findsOneWidget);

    completers['b']!.complete('data-b');
    await tester.pumpAndSettle();
    expect(find.text('data-b'), findsOneWidget);
  });
}
