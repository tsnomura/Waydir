import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/compare/compare_excludes.dart';

void main() {
  group('CompareExcludes.parse', () {
    test('empty input yields no patterns', () {
      expect(CompareExcludes.parse('').isEmpty, isTrue);
      expect(CompareExcludes.parse('   ').isEmpty, isTrue);
      expect(CompareExcludes.parse(',,;\n\n  ').isEmpty, isTrue);
    });

    test('splits on commas, newlines and semicolons', () {
      final excludes = CompareExcludes.parse('*.bin\n.git;build ,  tmp');
      expect(excludes.isEmpty, isFalse);
      expect(excludes.isExcluded('a.bin'), isTrue);
      expect(excludes.isExcluded('.git/config'), isTrue);
      expect(excludes.isExcluded('build'), isTrue);
      expect(excludes.isExcluded('tmp'), isTrue);
      expect(excludes.isExcluded('a.txt'), isFalse);
    });

    test('trims leading and trailing slashes', () {
      expect(CompareExcludes.parse('.git/').isExcluded('.git/HEAD'), isTrue);
      expect(CompareExcludes.parse('/build').isExcluded('a/build'), isTrue);
      expect(CompareExcludes.parse('///').isEmpty, isTrue);
    });

    test('unclosed character class stays literal', () {
      final excludes = CompareExcludes.parse('a[bc');
      expect(excludes.isExcluded('a[bc'), isTrue);
      expect(excludes.isExcluded('ab'), isFalse);
      expect(excludes.isExcluded('ac'), isFalse);
    });
  });

  group('CompareExcludes.isExcluded', () {
    test('star matches within one path segment', () {
      final excludes = CompareExcludes.parse('*.bin');
      expect(excludes.isExcluded('data.bin'), isTrue);
      expect(excludes.isExcluded('dir/data.bin'), isTrue);
      expect(excludes.isExcluded('a/b/data.bin'), isTrue);
      expect(excludes.isExcluded('data.bin.bak'), isFalse);
      expect(excludes.isExcluded('data'), isFalse);
    });

    test('bare name matches a folder and everything under it', () {
      final excludes = CompareExcludes.parse('.git');
      expect(excludes.isExcluded('.git'), isTrue);
      expect(excludes.isExcluded('.git/HEAD'), isTrue);
      expect(excludes.isExcluded('.git/refs/heads/main'), isTrue);
      expect(excludes.isExcluded('a/.git'), isTrue);
      expect(excludes.isExcluded('a/.git/x'), isTrue);
      expect(excludes.isExcluded('.git2'), isFalse);
      expect(excludes.isExcluded('git'), isFalse);
      expect(excludes.isExcluded('my.git'), isFalse);
    });

    test('question mark matches one non-separator character', () {
      final excludes = CompareExcludes.parse('core.?mp');
      expect(excludes.isExcluded('core.lmp'), isTrue);
      expect(excludes.isExcluded('dir/core.rmp'), isTrue);
      expect(excludes.isExcluded('core.lxmp'), isFalse);
    });

    test('character classes and negation', () {
      final excludes = CompareExcludes.parse('file[0-9].txt, log[!0-9].log');
      expect(excludes.isExcluded('file1.txt'), isTrue);
      expect(excludes.isExcluded('dir/file7.txt'), isTrue);
      expect(excludes.isExcluded('filex.txt'), isFalse);
      expect(excludes.isExcluded('loga.log'), isTrue);
      expect(excludes.isExcluded('log1.log'), isFalse);
      expect(CompareExcludes.parse('a[b].c').isExcluded('ab.c'), isTrue);
      expect(CompareExcludes.parse('a[b].c').isExcluded('aX.c'), isFalse);
      expect(CompareExcludes.parse('a[]b]').isExcluded('a]'), isTrue);
      expect(CompareExcludes.parse('a[]b]').isExcluded('ab'), isTrue);
      expect(CompareExcludes.parse('a[]b]').isExcluded('a]b'), isFalse);
    });

    test('regex metacharacters are literal', () {
      final excludes = CompareExcludes.parse('a.b+c(d)');
      expect(excludes.isExcluded('a.b+c(d)'), isTrue);
      expect(excludes.isExcluded('axb+c(d)'), isFalse);
      expect(excludes.isExcluded('a.b+cxd'), isFalse);
    });

    test('matching is case-sensitive', () {
      final excludes = CompareExcludes.parse('*.BIN');
      expect(excludes.isExcluded('a.BIN'), isTrue);
      expect(excludes.isExcluded('a.bin'), isFalse);
    });

    test('patterns with separators match the full relative path', () {
      final excludes = CompareExcludes.parse('docs/*.md');
      expect(excludes.isExcluded('docs/a.md'), isTrue);
      expect(excludes.isExcluded('docs/a.txt'), isFalse);
      expect(excludes.isExcluded('docs/sub/a.md'), isFalse);
      expect(excludes.isExcluded('x/docs/a.md'), isFalse);
      expect(excludes.isExcluded('docs'), isFalse);
    });

    test('empty relative path is never excluded', () {
      expect(CompareExcludes.parse('.git').isExcluded(''), isFalse);
    });

    test('the .waydir-sync marker file is always excluded', () {
      final excludes = CompareExcludes.parse('');
      expect(excludes.isExcluded('.waydir-sync'), isTrue);
      expect(excludes.isExcluded('sub/nested/.waydir-sync'), isTrue);
      expect(
        CompareExcludes.parse('*.bin').isExcluded('a/.waydir-sync'),
        isTrue,
      );
      expect(excludes.isExcluded('.waydir-sync.bak'), isFalse);
      expect(excludes.isExcluded('a.waydir-sync'), isFalse);
    });
  });
}
