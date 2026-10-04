import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/player/player_config.dart';

void main() {
  group('PlayerConfig.fromJson', () {
    test('parses cmd and args', () {
      final config = PlayerConfig.fromJson({
        'cmd': 'ffplay',
        'args': ['-nodisp', '-ss', '%START%', '%INPUT%'],
      });
      expect(config.cmd, 'ffplay');
      expect(config.args, ['-nodisp', '-ss', '%START%', '%INPUT%']);
    });

    test('rejects a missing cmd', () {
      expect(
        () => PlayerConfig.fromJson({
          'args': ['%INPUT%'],
        }),
        throwsFormatException,
      );
    });

    test('rejects an empty cmd', () {
      expect(
        () => PlayerConfig.fromJson({'cmd': '', 'args': <String>[]}),
        throwsFormatException,
      );
    });

    test('rejects a missing args list', () {
      expect(
        () => PlayerConfig.fromJson({'cmd': 'ffplay'}),
        throwsFormatException,
      );
    });
  });
}
