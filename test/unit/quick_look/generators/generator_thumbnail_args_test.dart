import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';

void main() {
  Map<String, dynamic> base() => {
    'id': 'font-preview',
    'extensions': ['ttf'],
    'cmd': 'powershell',
    'args': ['%INPUT%', '%OUTPUT%'],
  };

  test('thumbnailArgs is null when omitted', () {
    final def = GeneratorDef.fromJson(base());

    expect(def.thumbnailArgs, isNull);
  });

  test('thumbnailArgs parses independently of args', () {
    final def = GeneratorDef.fromJson({
      ...base(),
      'thumbnailArgs': ['-Ag', '%OUTPUT%'],
    });

    expect(def.thumbnailArgs, ['-Ag', '%OUTPUT%']);
    expect(def.args, ['%INPUT%', '%OUTPUT%']);
  });
}
