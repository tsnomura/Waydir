import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/markdown_math.dart';
import 'package:waydir/features/quick_look/markdown_preview.dart';
import 'package:waydir/ui/theme/app_theme.dart';

FileEntry _entry(String path) => FileEntry(
  name: path.split(Platform.pathSeparator).last,
  path: path,
  type: FileItemType.file,
  size: 0,
  modified: DateTime.now(),
);

Future<void> _pumpPreview(WidgetTester tester, String mdPath) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(body: MarkdownPreview(entry: _entry(mdPath))),
      ),
    );
    // probeFile() does real disk I/O; let it complete in the real zone.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  // Flush the setState scheduled when the probe future resolved.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders inline LaTeX math without disturbing surrounding text', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync(r"Einstein's equation is $E = mc^2$, quite famous.");

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining("Einstein's equation is"), findsOneWidget);
  });

  testWidgets('renders block LaTeX math on its own line and inline', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync(r'''
$$
\int_0^1 x\,dx = \frac{1}{2}
$$
''');

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('does not treat two dollar amounts as inline math', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync('The total is \$5 and \$10 combined.');

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNothing);
    expect(find.textContaining(r'$5 and $10'), findsOneWidget);
  });

  test('inline math regex requires tight, dollar-free delimiters', () {
    final pattern = MathInlineSyntax().pattern;
    bool matches(String s) => pattern.hasMatch(s);

    expect(matches(r'$x^2$'), isTrue);
    expect(matches(r'$x + y$'), isTrue);
    expect(matches('the price is \$5 and \$10 today'), isFalse);
    expect(matches(r'$$'), isFalse);
  });
}
