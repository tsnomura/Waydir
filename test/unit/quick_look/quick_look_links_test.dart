import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/quick_look_links.dart';

void main() {
  final base = p.join(p.current, 'docs', 'readme.md');

  group('resolveLocalLink', () {
    test('resolves a relative markdown link against the file', () {
      expect(
        resolveLocalLink('guide/setup.md', base),
        p.join(p.current, 'docs', 'guide', 'setup.md'),
      );
    });

    test('handles parent segments, fragments and escapes', () {
      expect(
        resolveLocalLink('../notes/My%20Notes.md#intro', base),
        p.join(p.current, 'notes', 'My Notes.md'),
      );
    });

    test('ignores web links, anchors and non-markdown targets', () {
      expect(resolveLocalLink('https://example.com/a.md', base), isNull);
      expect(resolveLocalLink('#section', base), isNull);
      expect(resolveLocalLink('image.png', base), isNull);
      expect(resolveLocalLink('mailto:a@example.com', base), isNull);
    });
  });

  group('QuickLookLinkHistory', () {
    FileEntry file(String name) => FileEntry.raw(
      name: name,
      path: '/tmp/$name',
      type: FileItemType.file,
      size: 1,
      modifiedMs: 1,
    );

    test('shows pushed pages and goes back to the base', () {
      final history = QuickLookLinkHistory();
      final a = file('a.md');
      expect(history.resolve(a), a);
      history.push(file('b.md'));
      history.push(file('c.md'));
      expect(history.resolve(a)?.name, 'c.md');
      history.back();
      expect(history.resolve(a)?.name, 'b.md');
      history.back();
      expect(history.canGoBack, isFalse);
      expect(history.resolve(a), a);
    });

    test('a different base clears the history', () {
      final history = QuickLookLinkHistory();
      history.resolve(file('a.md'));
      history.push(file('b.md'));
      final other = file('other.md');
      expect(history.resolve(other), other);
      expect(history.canGoBack, isFalse);
    });
  });
}
