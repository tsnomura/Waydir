import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:waydir/features/quick_look/markdown_mermaid.dart';

List<md.Node> parse(String source) {
  final doc = md.Document(
    blockSyntaxes: const [MermaidBlockSyntax()],
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  return doc.parseLines(source.split('\n'));
}

void main() {
  group('MermaidBlockSyntax', () {
    test('turns a mermaid fence into a mermaid element', () {
      final nodes = parse(
        '# Title\n\n```mermaid\nflowchart LR\n  A --> B\n```\n',
      );
      final el = nodes.whereType<md.Element>().last;
      expect(el.tag, mermaidTag);
      expect(el.textContent, 'flowchart LR\n  A --> B');
    });

    test('accepts tilde fences and longer closing fences', () {
      final nodes = parse('~~~ Mermaid\nsequenceDiagram\n~~~~\nafter\n');
      final el = nodes.whereType<md.Element>().first;
      expect(el.tag, mermaidTag);
      expect(el.textContent, 'sequenceDiagram');
      expect(nodes.whereType<md.Element>().last.textContent, 'after');
    });

    test('a shorter or different fence does not close the block', () {
      final nodes = parse('````mermaid\na\n```\n~~~~\nb\n````\n');
      expect(nodes.single is md.Element, isTrue);
      expect((nodes.single as md.Element).textContent, 'a\n```\n~~~~\nb');
    });

    test('other fenced languages stay code blocks', () {
      final nodes = parse('```dart\nvoid main() {}\n```\n');
      expect((nodes.single as md.Element).tag, 'pre');
    });
  });

  group('MermaidRenderer', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('mermaid_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String script(String name, String body) {
      final f = File(p.join(tmp.path, name))
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);

      return f.path;
    }

    MermaidRenderer renderer(String? exe) => MermaidRenderer(
      locate: () async => exe,
      cacheDir: () async => tmp.path,
    );

    test('reports a missing tool', () async {
      final result = await renderer(null).render('graph TD', dark: true);
      expect(result, isA<MermaidMissingTool>());
    });

    test('caches the image from stdout and passes the theme', () async {
      final args = p.join(tmp.path, 'args');
      final exe = script(
        'ok',
        'echo "\$@" > $args\ncat > /dev/null\nprintf PNGDATA',
      );
      final first = await renderer(exe).render('graph TD', dark: true);
      expect(first, isA<MermaidImage>());
      final path = (first as MermaidImage).path;
      expect(File(path).readAsStringSync(), 'PNGDATA');
      expect(File(args).readAsStringSync(), contains('--theme dark'));

      File(exe).deleteSync();
      final again = await renderer(exe).render('graph TD', dark: true);
      expect((again as MermaidImage).path, path);
    });

    test('surfaces stderr when the tool fails', () async {
      final exe = script(
        'bad',
        'cat > /dev/null\necho "parse error" >&2\nexit 2',
      );
      final result = await renderer(exe).render('nope', dark: false);
      expect(result, isA<MermaidFailure>());
      expect((result as MermaidFailure).message, 'parse error');
    });
  }, skip: Platform.isWindows);
}
