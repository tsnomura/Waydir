import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/files/path_ellipsis.dart';

TextFits maxChars(int n) =>
    (text) => text.length <= n;

void main() {
  group('ellipsizePathStart', () {
    test('returns the path unchanged when it fits', () {
      expect(ellipsizePathStart('a/b/c', maxChars(10)), 'a/b/c');
    });

    test('drops leading components first', () {
      expect(ellipsizePathStart('alpha/beta/gamma', maxChars(10)), '…/gamma');
      expect(
        ellipsizePathStart('alpha/beta/gamma', maxChars(14)),
        '…/beta/gamma',
      );
    });

    test('cuts the last component from the left when nothing else fits', () {
      expect(ellipsizePathStart('alpha/verylongname', maxChars(5)), '…name');
    });

    test('honours a custom separator', () {
      expect(
        ellipsizePathStart(r'alpha\beta\gamma', maxChars(8), separator: r'\'),
        r'…\gamma',
      );
    });
  });

  group('ellipsizeMiddle', () {
    test('returns the text unchanged when it fits', () {
      expect(ellipsizeMiddle('report.pdf', maxChars(20)), 'report.pdf');
    });

    test('keeps the requested tail', () {
      final name = 'quarterly_financial_report_v3.pdf';
      final shown = ellipsizeMiddle(
        name,
        maxChars(20),
        keepTail: fileNameTailLength(name),
      );
      expect(shown.length, lessThanOrEqualTo(20));
      expect(shown, endsWith('_v3.pdf'));
      expect(shown, startsWith('quarterly'));
      expect(shown, contains('…'));
    });

    test('shrinks the tail when the space is too small for it', () {
      final shown = ellipsizeMiddle(
        'abcdefghij.extension',
        maxChars(6),
        keepTail: 10,
      );
      expect(shown.length, lessThanOrEqualTo(6));
      expect(shown, contains('…'));
    });
  });

  group('fileNameTailLength', () {
    test('keeps the extension plus a few characters', () {
      expect(fileNameTailLength('quarterly_report_v3.pdf'), 10);
    });

    test('keeps only the extension for short stems', () {
      expect(fileNameTailLength('ab.txt'), 4);
    });

    test('handles names without an extension', () {
      expect(fileNameTailLength('README_FOR_EVERYONE'), 6);
      expect(fileNameTailLength('.bashrc'), 0);
    });
  });
}
