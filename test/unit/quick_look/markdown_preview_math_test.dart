import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
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

  testWidgets('renders \\[ \\] as block LaTeX math', (tester) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync(r'''
Before.

\[
\sum_{k=1}^n k = \frac{n(n+1)}{2}
\]

After.
''');

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining('After.'), findsOneWidget);
  });

  group('block math parsing', () {
    List<String> blocks(String source) {
      final doc = md.Document(
        blockSyntaxes: const [
          MathBlockSyntax.dollars(),
          MathBlockSyntax.brackets(),
        ],
      );

      return [
        for (final node in doc.parse(source))
          if (node is md.Element && node.tag == 'math_block') node.textContent,
      ];
    }

    test('one-line brackets', () {
      expect(blocks(r'\[ x^2 \]'), ['x^2']);
    });

    test('brackets alone on their own lines', () {
      expect(blocks('\\[\na + b\n= c\n\\]\n\nText.'), ['a + b\n= c']);
    });

    test('content on the delimiter lines', () {
      expect(blocks('\\[ a + b\n= c \\]'), ['a + b\n= c']);
    });

    test('a line starting with an escaped bracket stays text', () {
      expect(blocks('\\[1\\] see the reference\nmore text'), isEmpty);
    });

    test('an unterminated opening stays text', () {
      expect(blocks('\\[\nx^2\n\nno closing here'), isEmpty);
      expect(blocks('\$\$\nx^2'), isEmpty);
    });

    test('dollar blocks keep working', () {
      expect(blocks('\$\$ x \$\$'), ['x']);
      expect(blocks('\$\$\ny\n\$\$'), ['y']);
    });
  });

  group('paren inline math', () {
    List<String> inline(String source) {
      final doc = md.Document(
        inlineSyntaxes: [MathInlineSyntax(), MathParenInlineSyntax()],
      );
      final found = <String>[];
      void walk(md.Node node) {
        if (node is md.Element) {
          if (node.tag == 'math_inline') found.add(node.textContent);
          node.children?.forEach(walk);
        }
      }

      doc.parse(source).forEach(walk);

      return found;
    }

    test('renders \\( \\) inside a sentence', () {
      expect(inline(r'Area is \(\pi r^2\), roughly.'), [r'\pi r^2']);
    });

    test('allows a soft line break inside', () {
      expect(inline('Sum \\(a +\nb\\) here.'), ['a +\nb']);
    });

    test('a lone escaped parenthesis stays text', () {
      expect(inline(r'Call f\(x) with x.'), isEmpty);
    });

    test('mixes with dollar math', () {
      expect(inline(r'Both $x$ and \(y\).'), ['x', 'y']);
    });
  });

  testWidgets('renders \\( \\) as inline LaTeX math', (tester) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync(r'The area is \(\pi r^2\) for a circle.');

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
  });

  group('protectTableMathPipes', () {
    test('rewrites pipes inside inline math in table rows', () {
      expect(
        protectTableMathPipes(r'| a | `beta_t`で \(|t_i|\to1\) |'),
        r'| a | `beta_t`で \(\vert t_i\vert \to1\) |',
      );
      expect(
        protectTableMathPipes(r'| $\|x\|$ | b |'),
        r'| $\Vert x\Vert $ | b |',
      );
    });

    test('leaves code spans, prose and non-table lines alone', () {
      for (final source in [
        r'| `a|b` | c |',
        r'| $5 | $10 |',
        r'Outside a table \(|x|\) stays.',
      ]) {
        expect(protectTableMathPipes(source), source);
      }
    });
  });

  testWidgets('keeps inline math with pipes inside one table cell', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final md = File('${dir.path}/doc.md')
      ..writeAsStringSync(r'''
| 現行eo系列 | 本定式化 |
|---|---|
| `beta_sgn`で各非対角符号を鮮明化 | `beta_t`で \(|t_i|\to1\) としrank-1化 |
| rank 1は未保証 | \(|t_i|\to1\) でrank 1 |
''');

    await _pumpPreview(tester, md.path);

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('としrank-1化'), findsOneWidget);
    expect(find.textContaining(r'\to1'), findsNothing);
  });

  group('separateOperatorNames', () {
    test('inserts an empty group before a following command', () {
      expect(
        separateOperatorNames(r'\operatorname{diag}\left(d\right)'),
        r'\operatorname{diag}{}\left(d\right)',
      );
      expect(
        separateOperatorNames(r'\operatorname*{argmax}_x \bigl(f\bigr)'),
        r'\operatorname*{argmax}_x{} \bigl(f\bigr)',
      );
      expect(
        separateOperatorNames(r'\operatorname{tr}\widetilde Q'),
        r'\operatorname{tr}{}\widetilde Q',
      );
    });

    test('leaves operator names followed by plain content alone', () {
      for (final tex in [
        r'\operatorname{tr}(A)',
        r'\operatorname{tr} A',
        r'\sin\left(x\right)',
      ]) {
        expect(separateOperatorNames(tex), tex);
      }
    });
  });

  for (final (name, source) in [
    (
      'operator name followed by a fence',
      r'''
とすると、\(A\) は

\[
A
=vv^{\mathsf T}
+\operatorname{diag}\left(
d_1(1-t_1^2),
d_2(1-t_2^2),
d_3(1-t_3^2)
\right)
\]

と分解できる。
''',
    ),
    (
      'operator name followed by an accent or spacing',
      r'''
\(\operatorname{tr}A=1\) でも

\[
\operatorname{tr}\widetilde Q
=|M p_0|^2
\le1
\]

\[
\operatorname{tr}\,\hat Q + \operatorname{tr}\sqrt{x}
\]
''',
    ),
  ]) {
    testWidgets('renders $name without falling back to source', (tester) async {
      final dir = Directory.systemTemp.createTempSync('md_preview_math_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final md = File('${dir.path}/doc.md')..writeAsStringSync(source);

      await _pumpPreview(tester, md.path);

      expect(tester.takeException(), isNull);
      expect(find.byType(Math), findsWidgets);
      expect(find.textContaining(r'\operatorname'), findsNothing);
    });
  }

  test('inline math regex requires tight, dollar-free delimiters', () {
    final pattern = MathInlineSyntax().pattern;
    bool matches(String s) => pattern.hasMatch(s);

    expect(matches(r'$x^2$'), isTrue);
    expect(matches(r'$x + y$'), isTrue);
    expect(matches('the price is \$5 and \$10 today'), isFalse);
    expect(matches(r'$$'), isFalse);
  });
}
