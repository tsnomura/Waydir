import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/diff/diff_command_config.dart';
import 'package:waydir/features/quick_look/diff/diff_runner.dart';

void main() {
  group('parseDiffLine', () {
    // Fixtures captured from real `diff -y` output (GNU diffutils, via Git
    // for Windows) comparing two small text files — regression coverage for
    // Quick Look's compare-mode diff preview correctly classifying each
    // line kind from the raw tab-delimited format.
    test('a line with no marker field is unchanged, left equals right', () {
      final line = parseDiffLine('alpha\t\t\talpha');
      expect(line.kind, DiffLineKind.unchanged);
      expect(line.left, 'alpha');
      expect(line.right, 'alpha');
    });

    test('a "|" marker field is a changed line, left/right differ', () {
      final line = parseDiffLine('beta\t\t      |\tBETA changed');
      expect(line.kind, DiffLineKind.changed);
      expect(line.left, 'beta');
      expect(line.right, 'BETA changed');
    });

    test(
      'a "<" marker field is a removed (left-only) line, right is empty',
      () {
        final line = parseDiffLine('only-left\t\t      <');
        expect(line.kind, DiffLineKind.removed);
        expect(line.left, 'only-left');
        expect(line.right, '');
      },
    );

    test('a ">" marker field is an added (right-only) line, left is empty', () {
      final line = parseDiffLine('\t\t\t      >\tepsilon');
      expect(line.kind, DiffLineKind.added);
      expect(line.left, '');
      expect(line.right, 'epsilon');
    });

    test('extracts left/right regardless of how much padding is between '
        'them (e.g. a large --width)', () {
      final line = parseDiffLine('beta${'\t' * 200}      |\tBETA changed');
      expect(line.kind, DiffLineKind.changed);
      expect(line.left, 'beta');
      expect(line.right, 'BETA changed');
    });
  });

  group('parseDiffOutput', () {
    test('drops a single trailing empty line from a trailing newline', () {
      final lines = parseDiffOutput('alpha\t\t\talpha\n');
      expect(lines, hasLength(1));
    });

    test('parses every line of real multi-line diff -y output', () {
      const output =
          'alpha\t\t\talpha\n'
          'beta\t\t      |\tBETA changed\n'
          'gamma\t\t\tgamma\n'
          'delta\t\t\tdelta\n'
          '\t\t\t      >\tepsilon\n';
      final lines = parseDiffOutput(output);
      expect(lines, hasLength(5));
      expect(lines.map((l) => l.kind).toList(), [
        DiffLineKind.unchanged,
        DiffLineKind.changed,
        DiffLineKind.unchanged,
        DiffLineKind.unchanged,
        DiffLineKind.added,
      ]);
    });
  });

  group('DiffCommandConfig.fallback', () {
    test('strips trailing CR so Windows CRLF source files diff cleanly', () {
      expect(DiffCommandConfig.fallback.args, contains('--strip-trailing-cr'));
    });

    test('uses -y for side-by-side output', () {
      expect(DiffCommandConfig.fallback.args, contains('-y'));
    });
  });

  group('DiffCommandConfig.fromJson', () {
    test('parses a valid config', () {
      final config = DiffCommandConfig.fromJson({
        'cmd': 'mydiff',
        'args': ['-y', '%LEFT%', '%RIGHT%'],
        'timeoutSeconds': 20,
      });
      expect(config.cmd, 'mydiff');
      expect(config.args, ['-y', '%LEFT%', '%RIGHT%']);
      expect(config.timeout, const Duration(seconds: 20));
    });

    test('defaults timeout when omitted', () {
      final config = DiffCommandConfig.fromJson({
        'cmd': 'mydiff',
        'args': <String>[],
      });
      expect(
        config.timeout,
        const Duration(seconds: defaultDiffTimeoutSeconds),
      );
    });

    test('clamps an excessive timeout to the maximum', () {
      final config = DiffCommandConfig.fromJson({
        'cmd': 'mydiff',
        'args': <String>[],
        'timeoutSeconds': 999,
      });
      expect(config.timeout, const Duration(seconds: maxDiffTimeoutSeconds));
    });

    test('rejects a missing cmd', () {
      expect(
        () => DiffCommandConfig.fromJson({'args': <String>[]}),
        throwsFormatException,
      );
    });

    test('rejects a missing args', () {
      expect(
        () => DiffCommandConfig.fromJson({'cmd': 'mydiff'}),
        throwsFormatException,
      );
    });
  });
}
