import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';
import 'package:waydir/features/quick_look/quick_look_io.dart';
import 'package:waydir/features/quick_look/rendered_source.dart';

void main() {
  FileEntry file(String name) => FileEntry.raw(
    name: name,
    path: '/tmp/$name',
    type: FileItemType.file,
    size: 10,
    modifiedMs: 1000,
  );

  setUp(() {
    RenderedSource.reset();
    GeneratorRegistry.instance.clearForTesting();
    GeneratorRegistry.instance.registerForTesting(
      GeneratorDef(
        id: 'test-render',
        extensions: {'svg', 'pdf'},
        cmd: 'true',
        args: const [],
        timeout: const Duration(seconds: 1),
        outputExt: 'png',
      ),
    );
    RenderedSource.probe = (entry) async =>
        Probe(entry.extension == 'svg' ? QlKind.text : QlKind.binary);
  });

  tearDown(() {
    GeneratorRegistry.instance.clearForTesting();
    RenderedSource.probe = probeFile;
    RenderedSource.reset();
  });

  test('markdown always has a source view', () {
    expect(RenderedSource.available(file('a.md')), isTrue);
  });

  test('plain text without a renderer has no toggle', () {
    expect(RenderedSource.available(file('a.txt')), isFalse);
  });

  test('a rendered text file gains the toggle once probed', () async {
    final svg = file('a.svg');
    expect(RenderedSource.available(svg), isFalse);
    await pumpEventQueue();
    expect(RenderedSource.available(svg), isTrue);
  });

  test('a rendered binary file never gets the toggle', () async {
    final pdf = file('a.pdf');
    expect(RenderedSource.available(pdf), isFalse);
    await pumpEventQueue();
    expect(RenderedSource.available(pdf), isFalse);
  });
}
