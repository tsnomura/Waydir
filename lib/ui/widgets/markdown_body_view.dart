import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../features/quick_look/markdown_math.dart';

final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _htmlAttr = RegExp(
  '''([\\w:-]+)\\s*=\\s*("([^"]*)"|'([^']*)')''',
  caseSensitive: false,
);
final _pBlock = RegExp(
  r'<p\b[^>]*>(.*?)</p>',
  caseSensitive: false,
  dotAll: true,
);
final _aPair = RegExp(
  r'<a\b([^>]*)>(.*?)</a>',
  caseSensitive: false,
  dotAll: true,
);
final _boldPair = RegExp(
  r'<(b|strong)\b[^>]*>(.*?)</\1>',
  caseSensitive: false,
  dotAll: true,
);
final _emPair = RegExp(
  r'<(i|em)\b[^>]*>(.*?)</\1>',
  caseSensitive: false,
  dotAll: true,
);
final _htmlBlockPair = RegExp(
  r'<(div|p)\b([^>]*)>(.*?)</\1>',
  caseSensitive: false,
  dotAll: true,
);
final _brTag = RegExp(r'<br\s*/?>', caseSensitive: false);

/// Real HTML tags only: a tag name after `<` (or `</`). Leaves CommonMark
/// autolinks like `<https://…>` and `<a@b.com>` untouched (no `://`/`@` here).
final _htmlTag = RegExp(r'</?[a-zA-Z][a-zA-Z0-9-]*(?:\s[^<>]*)?/?>');
final _fence = RegExp(r'^\s*(```|~~~)');

/// flutter_markdown_plus renders no HTML. Two things go wrong without help:
///  - images embedded as `<img>` tags (common in READMEs wrapped in
///    `<div>`/`<p>`/`<table>`) are dropped, and
///  - other tags (`<td>`, `<b>`, `</div>`, …) leak into the preview as text.
///
/// Rewrite each `<img>` to a Markdown image on its own line (the blank lines
/// break out of any enclosing HTML block so the parser sees a real image),
/// then strip the remaining tags while keeping their inner text. Fenced code
/// blocks and inline code spans are left untouched.
String sanitizeHtml(String src) {
  final out = StringBuffer();
  var normal = StringBuffer();
  var inFence = false;

  void flushNormal() {
    final aligned = _preserveHtmlAlignment(normal.toString());
    final rewritten = _rewriteHtmlLinkParagraphs(aligned);
    normal = StringBuffer();
    for (final line in rewritten.split('\n')) {
      final parts = line.split('`');
      final sb = StringBuffer();
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) sb.write('`');
        sb.write(i.isEven ? _stripHtml(parts[i]) : parts[i]);
      }
      out.writeln(sb.toString());
    }
  }

  for (final line in src.split('\n')) {
    if (_fence.hasMatch(line)) {
      flushNormal();
      inFence = !inFence;
      out.writeln(line);
      continue;
    }
    if (inFence) {
      out.writeln(line);
      continue;
    }
    normal.writeln(line);
  }
  flushNormal();

  return out.toString();
}

const _centerStart = '@@WAYDIR_CENTER_START@@';
const _centerEnd = '@@WAYDIR_CENTER_END@@';

String _preserveHtmlAlignment(String src) {
  return src.replaceAllMapped(_htmlBlockPair, (m) {
    final attrs = m[2]!;
    if (!_isCenteredHtml(attrs)) return m[0]!;

    return '\n$_centerStart\n${m[3]!}\n$_centerEnd\n';
  });
}

bool _isCenteredHtml(String attrs) {
  final align = _attrValue(attrs, 'align')?.trim().toLowerCase();
  if (align == 'center') return true;
  final style = _attrValue(attrs, 'style')?.toLowerCase() ?? '';

  return style.split(';').any((part) {
    final pieces = part.split(':');
    if (pieces.length != 2) return false;

    return pieces[0].trim() == 'text-align' && pieces[1].trim() == 'center';
  });
}

String _rewriteHtmlLinkParagraphs(String src) {
  return src.replaceAllMapped(_pBlock, (m) {
    final body = m[1]!;
    if (!_aPair.hasMatch(body) || _imgTag.hasMatch(body)) return m[0]!;

    final inline = _htmlInlineToMarkdown(body)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (inline.isEmpty) return '';

    return '\n\n$inline\n\n';
  });
}

String _htmlInlineToMarkdown(String src) {
  var out = src.replaceAllMapped(_aPair, (m) {
    final attrs = m[1]!;
    final href = _attrValue(attrs, 'href');
    final text = _htmlInlineToMarkdown(m[2]!).trim();
    if (href == null || href.isEmpty || text.isEmpty) return text;

    return '[$text]($href)';
  });
  out = out.replaceAllMapped(
    _boldPair,
    (m) => '**${_htmlInlineToMarkdown(m[2]!).trim()}**',
  );
  out = out.replaceAllMapped(
    _emPair,
    (m) => '*${_htmlInlineToMarkdown(m[2]!).trim()}*',
  );

  return out.replaceAll(_brTag, '\n').replaceAll(_htmlTag, '');
}

String? _attrValue(String attrs, String name) {
  for (final a in _htmlAttr.allMatches(attrs)) {
    if (a[1]!.toLowerCase() == name) return a[3] ?? a[4] ?? '';
  }

  return null;
}

String _stripHtml(String segment) {
  return segment
      .replaceAllMapped(_imgTag, (m) {
        String? imgSrc;
        String alt = '';
        for (final a in _htmlAttr.allMatches(m[0]!)) {
          final name = a[1]!.toLowerCase();
          final value = a[3] ?? a[4] ?? '';
          if (name == 'src') {
            imgSrc = value;
          } else if (name == 'alt') {
            alt = value;
          }
        }
        if (imgSrc == null || imgSrc.isEmpty) return '';

        return '\n\n![$alt]($imgSrc)\n\n';
      })
      .replaceAll(_brTag, '\n')
      .replaceAll(_htmlTag, '');
}

/// Generic selectable Markdown renderer shared by Quick Look and Help: HTML
/// sanitization (via [sanitizeHtml], applied by the caller before [data] is
/// passed in), centered-block support, LaTeX math and a style sheet built
/// from the caller's own text theme. Image resolution is left to the caller
/// through [imageBuilder] — Quick Look plugs in its SFTP/remote-aware
/// resolver, Help just inherits the package default (its markdown has no
/// images; those are bundled GIFs rendered separately).
class MarkdownBodyView extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet styleSheet;
  final void Function(String href)? onTapLink;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  const MarkdownBodyView({
    super.key,
    required this.data,
    required this.styleSheet,
    this.onTapLink,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final children = _markdownSegments(data)
        .map(
          (segment) => _segmentView(
            segment.text,
            segment.centered ? _centeredStyleSheet(styleSheet) : styleSheet,
            centered: segment.centered,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _segmentView(
    String data,
    MarkdownStyleSheet styleSheet, {
    required bool centered,
  }) {
    final mathTextStyle = styleSheet.p ?? const TextStyle();
    final onTap = onTapLink;

    return SizedBox(
      width: double.infinity,
      child: MarkdownBody(
        data: protectTableMathPipes(data),
        selectable: true,
        fitContent: !centered,
        onTapLink: onTap == null
            ? null
            : (_, href, _) {
                if (href != null) onTap(href);
              },
        imageBuilder: imageBuilder,
        styleSheet: styleSheet,
        inlineSyntaxes: [MathInlineSyntax(), MathParenInlineSyntax()],
        blockSyntaxes: const [
          MathBlockSyntax.dollars(),
          MathBlockSyntax.brackets(),
        ],
        builders: {
          'math_inline': MathElementBuilder(
            textStyle: mathTextStyle,
            mathStyle: MathStyle.text,
          ),
          'math_block': MathElementBuilder(
            textStyle: mathTextStyle,
            mathStyle: MathStyle.display,
          ),
        },
      ),
    );
  }
}

MarkdownStyleSheet _centeredStyleSheet(MarkdownStyleSheet styleSheet) {
  return styleSheet.copyWith(
    textAlign: WrapAlignment.center,
    h1Align: WrapAlignment.center,
    h2Align: WrapAlignment.center,
    h3Align: WrapAlignment.center,
    h4Align: WrapAlignment.center,
    h5Align: WrapAlignment.center,
    h6Align: WrapAlignment.center,
    unorderedListAlign: WrapAlignment.center,
    orderedListAlign: WrapAlignment.center,
    blockquoteAlign: WrapAlignment.center,
    codeblockAlign: WrapAlignment.center,
  );
}

typedef _MarkdownSegment = ({String text, bool centered});

List<_MarkdownSegment> _markdownSegments(String md) {
  final segments = <_MarkdownSegment>[];
  var centered = false;
  var buffer = StringBuffer();

  void flush() {
    final text = buffer.toString();
    buffer = StringBuffer();
    if (text.trim().isEmpty) return;
    segments.add((text: text, centered: centered));
  }

  for (final line in md.split('\n')) {
    final trimmed = line.trim();
    if (trimmed == _centerStart) {
      flush();
      centered = true;
      continue;
    }
    if (trimmed == _centerEnd) {
      flush();
      centered = false;
      continue;
    }
    buffer.writeln(line);
  }
  flush();

  return segments;
}
