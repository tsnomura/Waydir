import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/quick_look_common.dart';

void main() {
  testWidgets('holdKey keeps the previous data visible while a same-holdKey '
      'cacheKey is still loading, then swaps once it resolves', (tester) async {
    final completers = <String, Completer<String?>>{
      'a': Completer<String?>()..complete('data-a'),
      'b': Completer<String?>(),
    };

    Widget buildFor(String cacheKey, String holdKey) {
      return MaterialApp(
        home: AsyncRetain<String?>(
          cacheKey: cacheKey,
          holdKey: holdKey,
          loader: () => completers[cacheKey]!.future,
          loading: const Text('loading'),
          builder: (data) => Text(data ?? 'empty'),
        ),
      );
    }

    await tester.pumpWidget(buildFor('a', 'file'));
    await tester.pump();
    expect(find.text('data-a'), findsOneWidget);

    await tester.pumpWidget(buildFor('b', 'file'));
    await tester.pump();
    expect(
      find.text('data-a'),
      findsOneWidget,
      reason:
          'same holdKey: the previous data must stay shown while the new '
          'cacheKey is still loading (no blank between pages)',
    );
    expect(find.text('loading'), findsNothing);

    completers['b']!.complete('data-b');
    await tester.pumpAndSettle();
    expect(find.text('data-b'), findsOneWidget);
    expect(find.text('data-a'), findsNothing);
  });

  testWidgets('a changed holdKey falls back to the loading widget even when '
      'the previous data is available', (tester) async {
    final completers = <String, Completer<String?>>{
      'a': Completer<String?>()..complete('data-a'),
      'b': Completer<String?>(),
    };

    Widget buildFor(String cacheKey, String holdKey) {
      return MaterialApp(
        home: AsyncRetain<String?>(
          cacheKey: cacheKey,
          holdKey: holdKey,
          loader: () => completers[cacheKey]!.future,
          loading: const Text('loading'),
          builder: (data) => Text(data ?? 'empty'),
        ),
      );
    }

    await tester.pumpWidget(buildFor('a', 'file-a'));
    await tester.pump();
    expect(find.text('data-a'), findsOneWidget);

    await tester.pumpWidget(buildFor('b', 'file-b'));
    await tester.pump();
    expect(
      find.text('data-a'),
      findsNothing,
      reason:
          'a different holdKey means a different source: showing the old '
          'source\'s data would mislead the user',
    );
    expect(find.text('loading'), findsOneWidget);
  });

  testWidgets('holdKey drops the held data when the new load resolves to '
      'null or throws', (tester) async {
    String? result = 'data-a';
    var throws = false;

    Widget buildFor(String cacheKey) {
      return MaterialApp(
        home: AsyncRetain<String?>(
          cacheKey: cacheKey,
          holdKey: 'file',
          loader: () async {
            if (throws) throw StateError('boom');
            return result;
          },
          loading: const Text('loading'),
          builder: (data) => Text(data ?? 'empty'),
        ),
      );
    }

    await tester.pumpWidget(buildFor('a'));
    await tester.pump();
    expect(find.text('data-a'), findsOneWidget);

    result = null;
    await tester.pumpWidget(buildFor('b'));
    await tester.pump();
    expect(
      find.text('empty'),
      findsOneWidget,
      reason: 'a null result must show the empty view, not the held frame',
    );

    result = 'data-a';
    await tester.pumpWidget(buildFor('a'));
    await tester.pump();
    expect(find.text('data-a'), findsOneWidget);

    throws = true;
    await tester.pumpWidget(buildFor('b'));
    await tester.pump();
    expect(
      find.text('empty'),
      findsOneWidget,
      reason: 'a failed load must show the empty view, not the held frame',
    );
    expect(tester.takeException(), isNull);
  });

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
