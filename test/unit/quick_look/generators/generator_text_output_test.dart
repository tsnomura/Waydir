import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';

void main() {
  Map<String, dynamic> base() => {
    'id': 'archive-list',
    'extensions': ['zip'],
    'cmd': '7z',
    'args': ['l', '%INPUT%'],
  };

  test('defaults to an image written by the command itself', () {
    final def = GeneratorDef.fromJson(base());

    expect(def.captureStdout, isFalse);
    expect(def.textOutput, isFalse);
  });

  test('"stdout": true captures stdout', () {
    final def = GeneratorDef.fromJson({...base(), 'stdout': true});

    expect(def.captureStdout, isTrue);
  });

  test('"outputExt": "txt" is text output, case-insensitively', () {
    expect(
      GeneratorDef.fromJson({...base(), 'outputExt': 'txt'}).textOutput,
      isTrue,
    );
    expect(
      GeneratorDef.fromJson({...base(), 'outputExt': 'TXT'}).textOutput,
      isTrue,
    );
    expect(
      GeneratorDef.fromJson({...base(), 'outputExt': 'png'}).textOutput,
      isFalse,
    );
  });
}
