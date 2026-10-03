import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/player/playback_math.dart';

void main() {
  group('startSecondsForPage', () {
    test('splits duration evenly across pages', () {
      expect(startSecondsForPage(page: 0, duration: 100, pageCount: 10), 0);
      expect(startSecondsForPage(page: 5, duration: 100, pageCount: 10), 50);
      expect(startSecondsForPage(page: 9, duration: 100, pageCount: 10), 90);
    });

    test('is always 0 when there is only one page', () {
      expect(startSecondsForPage(page: 0, duration: 42, pageCount: 1), 0);
    });
  });

  group('pageForElapsed', () {
    test('buckets elapsed time into the matching page', () {
      expect(
        pageForElapsed(elapsedSeconds: 0, duration: 100, pageCount: 10),
        0,
      );
      expect(
        pageForElapsed(elapsedSeconds: 49, duration: 100, pageCount: 10),
        4,
      );
      expect(
        pageForElapsed(elapsedSeconds: 50, duration: 100, pageCount: 10),
        5,
      );
    });

    test('clamps to the last page instead of overflowing at/after the end', () {
      expect(
        pageForElapsed(elapsedSeconds: 100, duration: 100, pageCount: 10),
        9,
      );
      expect(
        pageForElapsed(elapsedSeconds: 1000, duration: 100, pageCount: 10),
        9,
      );
    });

    test('is always 0 for a zero/negative duration or a single page', () {
      expect(pageForElapsed(elapsedSeconds: 5, duration: 0, pageCount: 10), 0);
      expect(pageForElapsed(elapsedSeconds: 5, duration: 100, pageCount: 1), 0);
    });
  });
}
