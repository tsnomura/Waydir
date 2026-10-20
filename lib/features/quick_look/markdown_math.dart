import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// `$...$` inline math. Delimiters must hug their content (no leading/
/// trailing whitespace, no `$` inside) — the same rule Pandoc's
/// `tex_math_dollars` uses — so ordinary prose mentioning two dollar amounts
/// (`$5 and $10`) never gets misread as a single equation.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'\$(\S(?:[^$]*\S)?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math_inline', match[1]!));

    return true;
  }
}

/// `\(...\)` inline math. Registered ahead of the built-in escape handling,
/// so `\(` here opens math instead of producing a literal parenthesis; the
/// content may wrap across a soft line break.
class MathParenInlineSyntax extends md.InlineSyntax {
  MathParenInlineSyntax() : super(r'\\\(([\s\S]+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math_inline', match[1]!.trim()));

    return true;
  }
}

/// Display math, either `$$...$$` or `\[...\]`: on one line (`$$ x^2 $$`) or
/// spanning lines, where the opening line may carry content after the
/// delimiter and the closing line content before it. A block is only taken
/// when its closing delimiter actually follows, so a prose line that merely
/// starts with an escaped bracket (`\[1\] reference`) stays text.
class MathBlockSyntax extends md.BlockSyntax {
  final String open;
  final String close;

  const MathBlockSyntax.dollars() : open = r'$$', close = r'$$';

  const MathBlockSyntax.brackets() : open = r'\[', close = r'\]';

  String get _open => RegExp.escape(open);

  String get _close => RegExp.escape(close);

  RegExp get _fullLine => RegExp('^\\s*$_open(.+?)$_close\\s*\$');

  RegExp get _closingLine => RegExp('^(.*?)$_close\\s*\$');

  @override
  RegExp get pattern => RegExp('^\\s*$_open');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content;
    if (!pattern.hasMatch(line)) return false;
    if (_fullLine.hasMatch(line)) return true;
    for (var ahead = 1; ; ahead++) {
      final next = parser.peek(ahead);
      if (next == null) return false;
      if (_closingLine.hasMatch(next.content)) return true;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final first = parser.current.content;
    final full = _fullLine.firstMatch(first);
    parser.advance();
    if (full != null) return md.Element.text('math_block', full[1]!.trim());

    final lines = [first.substring(first.indexOf(open) + open.length)];
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      final closing = _closingLine.firstMatch(line);
      if (closing != null) {
        lines.add(closing[1]!);
        break;
      }
      lines.add(line);
    }

    return md.Element.text('math_block', lines.join('\n').trim());
  }
}

final _codeSpan = RegExp(r'`+[^`]*`+');
final _inlineMathSpan = RegExp(
  r'\\\((.+?)\\\)|(?<![\\$])\$(?!\$)\S(?:[^$]*\S)?\$(?!\$)',
);

/// GFM tables split rows at every `|` before inline syntaxes run, so inline
/// math such as `\(|t_i|\to1\)` in a table cell was cut apart. In table rows,
/// `|` and `\|` inside inline math are rewritten to the equivalent `\vert`
/// and `\Vert`; code spans are left untouched.
String protectTableMathPipes(String source) {
  if (!source.contains('|')) return source;
  String protect(String segment) => segment.replaceAllMapped(
    _inlineMathSpan,
    (m) => m[0]!.replaceAll(r'\|', r'\Vert ').replaceAll('|', r'\vert '),
  );
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.trimLeft().startsWith('|')) continue;
    final out = StringBuffer();
    var last = 0;
    for (final code in _codeSpan.allMatches(line)) {
      out
        ..write(protect(line.substring(last, code.start)))
        ..write(code[0]);
      last = code.end;
    }
    out.write(protect(line.substring(last)));
    lines[i] = out.toString();
  }

  return lines.join('\n');
}

/// `flutter_math_fork` parses `\operatorname{name}` as a function that takes
/// the next group as its argument, and fails when that group is a command
/// that cannot stand alone as one (`\left`, `\big`, accents, `\sqrt`, `\,`, …:
/// "Got function '\left' with no arguments"). KaTeX and LaTeX accept these, so
/// a formula that fails to parse is retried with an empty group after every
/// operator name (and its scripts) that is followed by a command.
String separateOperatorNames(String tex) => tex.replaceAllMapped(
  RegExp(
    r'(\\operatorname\*?\s*\{[^{}]*\}'
    r'(?:\s*[_^]\s*(?:\{[^{}]*\}|\\[A-Za-z]+|[^\s\\{}]))*)'
    r'(?=\s*\\)',
  ),
  (m) => '${m[1]}{}',
);

class MathElementBuilder extends MarkdownElementBuilder {
  final TextStyle textStyle;
  final MathStyle mathStyle;

  MathElementBuilder({required this.textStyle, required this.mathStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;

    Widget source() => Text(
      tex,
      style: textStyle.copyWith(
        fontFamily: 'monospace',
        color: textStyle.color?.withValues(alpha: 0.6),
      ),
    );

    return Math.tex(
      tex,
      textStyle: textStyle,
      mathStyle: mathStyle,
      onErrorFallback: (error) {
        final retry = separateOperatorNames(tex);
        if (retry == tex) return source();

        return Math.tex(
          retry,
          textStyle: textStyle,
          mathStyle: mathStyle,
          onErrorFallback: (error) => source(),
        );
      },
    );
  }
}
