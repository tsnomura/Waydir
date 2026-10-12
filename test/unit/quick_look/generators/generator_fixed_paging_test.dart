import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_runner.dart';

void main() {
  Map<String, dynamic> base() => {
    'id': '3d-model',
    'extensions': ['stl'],
    'cmd': 'f3d',
    'args': ['%INPUT%', '--camera-azimuth-angle=%ANGLE%', '--output=%OUTPUT%'],
  };

  test('fixed paging keeps its page count without a probe', () {
    final def = GeneratorDef.fromJson({
      ...base(),
      'paging': 'fixed',
      'pageCount': 10,
    });

    expect(def.pagingMode, PagingMode.fixed);
    expect(def.pageCount, 10);
    expect(def.probeCmd, isNull);
  });

  test('fixed paging needs more than one page', () {
    expect(
      () => GeneratorDef.fromJson({...base(), 'paging': 'fixed'}),
      throwsFormatException,
    );
  });

  test('time paging still requires a probe', () {
    expect(
      () =>
          GeneratorDef.fromJson({...base(), 'paging': 'time', 'pageCount': 4}),
      throwsFormatException,
    );
  });

  test('angle splits a full turn across the pages', () {
    expect(
      [for (var i = 0; i < 10; i++) GeneratorRunner.formatAngle(i, 10)],
      ['0', '36', '72', '108', '144', '180', '216', '252', '288', '324'],
    );
    expect(GeneratorRunner.formatAngle(1, 7), '51.429');
    expect(GeneratorRunner.formatAngle(0, 1), '0');
  });
}
