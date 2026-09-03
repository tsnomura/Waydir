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

/// `$$...$$` block math, either on one line (`$$ x^2 $$`) or spanning
/// multiple lines with the delimiters alone on their own line.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final _fullLine = RegExp(r'^\s*\$\$(.+?)\$\$\s*$');
  static final _delimiterLine = RegExp(r'^\s*\$\$\s*$');

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  md.Node parse(md.BlockParser parser) {
    final full = _fullLine.firstMatch(parser.current.content);
    if (full != null) {
      parser.advance();

      return md.Element.text('math_block', full[1]!.trim());
    }

    parser.advance();
    final lines = <String>[];
    while (!parser.isDone) {
      if (_delimiterLine.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    return md.Element.text('math_block', lines.join('\n').trim());
  }
}

class MathElementBuilder extends MarkdownElementBuilder {
  final TextStyle textStyle;
  final MathStyle mathStyle;

  MathElementBuilder({required this.textStyle, required this.mathStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;

    return Math.tex(
      tex,
      textStyle: textStyle,
      mathStyle: mathStyle,
      onErrorFallback: (error) => Text(
        tex,
        style: textStyle.copyWith(
          fontFamily: 'monospace',
          color: textStyle.color?.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
