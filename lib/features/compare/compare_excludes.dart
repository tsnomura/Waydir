class CompareExcludes {
  static const markerFileName = '.waydir-sync-ignore';

  final List<RegExp> _patterns;

  const CompareExcludes._(this._patterns);

  static CompareExcludes parse(String raw) {
    final patterns = <RegExp>[];
    for (final pattern in splitPatterns(raw)) {
      patterns.add(_compile(pattern));
    }

    return CompareExcludes._(patterns);
  }

  static List<String> splitPatterns(String raw) {
    final patterns = <String>[];
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      if (line.trim().startsWith('#')) continue;
      for (final part in line.split(RegExp(r'[;,]+'))) {
        final pattern = _trimSlashes(part.trim());
        if (pattern.isNotEmpty) patterns.add(pattern);
      }
    }

    return patterns;
  }

  bool get isEmpty => _patterns.isEmpty;

  bool isExcluded(String relativePath) {
    if (relativePath.isEmpty) return false;
    final segments = relativePath.split('/');
    for (final segment in segments) {
      if (segment == markerFileName) return true;
    }
    if (_patterns.isEmpty) return false;
    for (final pattern in _patterns) {
      if (pattern.hasMatch(relativePath)) return true;
      for (final segment in segments) {
        if (pattern.hasMatch(segment)) return true;
      }
    }

    return false;
  }

  static String _trimSlashes(String pattern) {
    var start = 0;
    var end = pattern.length;
    while (start < end && pattern[start] == '/') {
      start++;
    }
    while (end > start && pattern[end - 1] == '/') {
      end--;
    }

    return pattern.substring(start, end);
  }

  static RegExp _compile(String pattern) {
    final body = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '*') {
        body.write('[^/]*');
      } else if (ch == '?') {
        body.write('[^/]');
      } else if (ch == '[') {
        final end = _classEnd(pattern, i);
        if (end < 0) {
          body.write(RegExp.escape('['));
        } else {
          body.write(_classBody(pattern, i, end));
          i = end;
        }
      } else {
        body.write(RegExp.escape(ch));
      }
    }

    return RegExp('^$body\$');
  }

  static int _classEnd(String pattern, int start) {
    var i = start + 1;
    if (i < pattern.length && (pattern[i] == '!' || pattern[i] == '^')) i++;
    if (i < pattern.length && pattern[i] == ']') i++;
    while (i < pattern.length && pattern[i] != ']') {
      i++;
    }

    return i < pattern.length ? i : -1;
  }

  static String _classBody(String pattern, int start, int end) {
    final inner = pattern.substring(start + 1, end);
    final negated = inner.startsWith('!') || inner.startsWith('^');
    final content = negated ? inner.substring(1) : inner;
    if (content.isEmpty) {
      return RegExp.escape(pattern.substring(start, end + 1));
    }

    final body = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final ch = content[i];
      if (ch == ']' || ch == '\\') {
        body.write('\\$ch');
      } else if (ch == '-' && i > 0 && i < content.length - 1) {
        body.write(ch);
      } else {
        body.write(RegExp.escape(ch));
      }
    }

    return '[${negated ? '^' : ''}$body]';
  }
}
