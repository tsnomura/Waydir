import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';
import 'package:waydir/features/quick_look/generators/generator_runner.dart';
import 'package:waydir/features/quick_look/markdown_generated.dart';

Map<String, dynamic> base() => {
  'id': 'graphviz',
  'extensions': ['dot', 'gv'],
  'cmd': 'dot',
  'args': ['-Tpng', '%INPUT%', '-o', '%OUTPUT%'],
};

List<md.Node> parse(String source) => md.Document(
  blockSyntaxes: const [GeneratorFenceBlockSyntax()],
  extensionSet: md.ExtensionSet.gitHubFlavored,
).parseLines(source.split('\n'));

void main() {
  group('GeneratorDef markdown fields', () {
    test('defaults', () {
      final def = GeneratorDef.fromJson(base());
      expect(def.fences, isEmpty);
      expect(def.imageScale, 1.0);
      expect(def.usesTheme, isFalse);
      expect(def.themeArg(dark: true), 'dark');
      expect(def.themeArg(dark: false), 'light');
    });

    test('parses fences, imageScale and themeNames', () {
      final def = GeneratorDef.fromJson({
        ...base(),
        'args': ['--theme', '%THEME%', '%INPUT%'],
        'fences': ['DOT', 'graphviz'],
        'imageScale': 2,
        'themeNames': {'light': 'default'},
      });
      expect(def.fences, {'dot', 'graphviz'});
      expect(def.imageScale, 2.0);
      expect(def.usesTheme, isTrue);
      expect(def.themeArg(dark: true), 'dark');
      expect(def.themeArg(dark: false), 'default');
    });

    test('clamps imageScale', () {
      expect(
        GeneratorDef.fromJson({...base(), 'imageScale': 100}).imageScale,
        8.0,
      );
    });
  });

  group('markdown integration', () {
    tearDown(GeneratorRegistry.instance.clearForTesting);

    test('only fences claimed by a generator are taken', () {
      GeneratorRegistry.instance.registerForTesting(
        GeneratorDef.fromJson({
          ...base(),
          'fences': ['dot'],
        }),
      );
      final nodes = parse('```dot\ndigraph { a -> b }\n```\n\n```gv\nx\n```');
      final elements = nodes.whereType<md.Element>().toList();
      expect(elements.first.tag, generatedFenceTag);
      expect(elements.first.attributes['language'], 'dot');
      expect(elements.first.textContent, 'digraph { a -> b }');
      expect(elements.last.tag, 'pre');
    });

    test('image paths go to a generator unless natively shown', () {
      GeneratorRegistry.instance.registerForTesting(
        GeneratorDef.fromJson({
          ...base(),
          'extensions': ['dxf', 'svg'],
        }),
      );
      expect(wantsGeneratedImage('/a/drawing.DXF'), isTrue);
      expect(wantsGeneratedImage('/a/logo.svg'), isFalse);
      expect(wantsGeneratedImage('/a/photo.png'), isFalse);
      expect(wantsGeneratedImage('/a/model.step'), isFalse);
    });
  });

  group('GeneratorRunner.previewFence', () {
    late Directory tmp;
    late Future<String> Function() savedCache;
    late bool Function() savedTheme;
    var dark = true;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fence_test');
      savedCache = GeneratorRunner.cacheDirectory;
      savedTheme = GeneratorRunner.darkTheme;
      GeneratorRunner.cacheDirectory = () async => tmp.path;
      GeneratorRunner.darkTheme = () => dark;
    });

    tearDown(() {
      GeneratorRunner.cacheDirectory = savedCache;
      GeneratorRunner.darkTheme = savedTheme;
      GeneratorRegistry.instance.clearForTesting();
      tmp.deleteSync(recursive: true);
    });

    test(
      'writes the body to a file and runs the generator with the theme',
      () async {
        final script = File(p.join(tmp.path, 'gen.sh'))
          ..writeAsStringSync('#!/bin/sh\nprintf "%s:" "\$1"; cat "\$2"\n');
        Process.runSync('chmod', ['+x', script.path]);
        GeneratorRegistry.instance.registerForTesting(
          GeneratorDef.fromJson({
            'id': 'echo',
            'extensions': ['dot'],
            'fences': ['dot'],
            'cmd': script.path,
            'args': ['%THEME%', '%INPUT%'],
            'stdout': true,
            'outputExt': 'txt',
            'themeNames': {'light': 'default'},
          }),
        );

        final darkOut = (await GeneratorRunner.previewFence(
          'DOT',
          'a -> b',
        )).path;
        expect(File(darkOut!).readAsStringSync(), 'dark:a -> b');
        expect(
          Directory(p.join(tmp.path, 'fences')).listSync().single.path,
          endsWith('.dot'),
        );

        dark = false;
        final lightOut = (await GeneratorRunner.previewFence(
          'dot',
          'a -> b',
        )).path;
        expect(File(lightOut!).readAsStringSync(), 'default:a -> b');
        expect(lightOut, isNot(darkOut));
      },
    );

    test('returns nothing for unclaimed languages', () async {
      final result = await GeneratorRunner.previewFence('dot', 'x');
      expect(result.path, isNull);
      expect(result.error, isNull);
    });

    test('reports the last lines of stderr when the generator fails', () async {
      final script = File(p.join(tmp.path, 'bad.sh'))
        ..writeAsStringSync(
          '#!/bin/sh\necho noise >&2\necho a >&2\necho b >&2\n'
          'echo "parse error at line 2" >&2\nexit 1\n',
        );
      Process.runSync('chmod', ['+x', script.path]);
      GeneratorRegistry.instance.registerForTesting(
        GeneratorDef.fromJson({
          'id': 'bad',
          'extensions': ['mmd'],
          'fences': ['mermaid'],
          'cmd': script.path,
          'args': ['%INPUT%', '%OUTPUT%'],
        }),
      );

      final first = await GeneratorRunner.previewFence('mermaid', 'graph');
      expect(first.path, isNull);
      expect(first.error, 'a\nb\nparse error at line 2');

      final cached = await GeneratorRunner.previewFence('mermaid', 'graph');
      expect(cached.error, first.error);
    });

    test('reports a missing executable', () async {
      GeneratorRegistry.instance.registerForTesting(
        GeneratorDef.fromJson({
          'id': 'missing',
          'extensions': ['mmd'],
          'fences': ['mermaid'],
          'cmd': p.join(tmp.path, 'no-such-tool'),
          'args': ['%INPUT%', '%OUTPUT%'],
        }),
      );

      final result = await GeneratorRunner.previewFence('mermaid', 'other');
      expect(result.path, isNull);
      expect(result.error, contains('no-such-tool'));
    });
  }, skip: Platform.isWindows);
}
