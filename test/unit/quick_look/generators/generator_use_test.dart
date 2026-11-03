import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';

void main() {
  Map<String, dynamic> base() => {
    'id': 'pdf',
    'extensions': ['pdf'],
    'fences': ['pdfsrc'],
    'cmd': 'mutool',
    'args': ['%INPUT%', '%OUTPUT%'],
  };

  tearDown(GeneratorRegistry.instance.clearForTesting);

  test('every use is on when the keys are omitted', () {
    final def = GeneratorDef.fromJson(base());

    expect(def.uses, GeneratorUse.values.toSet());
  });

  test('a false key turns that use off', () {
    final def = GeneratorDef.fromJson({
      ...base(),
      'quickLook': false,
      'markdown': true,
    });

    expect(def.usedFor(GeneratorUse.quickLook), isFalse);
    expect(def.usedFor(GeneratorUse.thumbnail), isTrue);
    expect(def.usedFor(GeneratorUse.markdown), isTrue);
  });

  test('registry lookups skip a generator turned off for that use', () {
    GeneratorRegistry.instance.registerForTesting(
      GeneratorDef.fromJson({...base(), 'thumbnail': false, 'markdown': false}),
    );
    final registry = GeneratorRegistry.instance;

    expect(registry.forExtension('pdf', GeneratorUse.quickLook), isNotNull);
    expect(registry.forExtension('PDF', GeneratorUse.thumbnail), isNull);
    expect(registry.forExtension('pdf', GeneratorUse.markdown), isNull);
    expect(registry.forFence('pdfsrc'), isNull);
  });
}
