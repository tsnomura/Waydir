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

  group('textFrom', () {
    const listing =
        '\r\n7-Zip 26.03 (x64)\r\n\r\nType = zip\r\n\r\n'
        '   Date      Time    Attr  Name\r\n'
        '------------------- ----- ----\r\n'
        '2026-10-20 00:45:03 ....A readme.txt\r\n';

    test('drops everything above the first matching line', () {
      final def = GeneratorDef.fromJson({
        ...base(),
        'textFrom': r'^\s*Date\s+Time',
      });

      expect(def.trimText(listing), startsWith('   Date      Time'));
      expect(def.trimText(listing), endsWith('readme.txt\r\n'));
    });

    test('no pattern, no match or a bad pattern keeps the whole text', () {
      expect(GeneratorDef.fromJson(base()).trimText(listing), listing);
      expect(
        GeneratorDef.fromJson({
          ...base(),
          'textFrom': 'nope',
        }).trimText(listing),
        listing,
      );
      expect(
        GeneratorDef.fromJson({...base(), 'textFrom': '('}).trimText(listing),
        listing,
      );
    });
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
