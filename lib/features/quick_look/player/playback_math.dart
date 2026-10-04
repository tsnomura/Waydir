/// Which page (0-based) [elapsedSeconds] into playback falls into, out of
/// [pageCount] evenly-spaced pages across [duration] — the same bucketing a
/// `PagingMode.time` generator uses to place its pages, so the displayed
/// thumbnail tracks what's actually playing without restarting the player.
int pageForElapsed({
  required double elapsedSeconds,
  required double duration,
  required int pageCount,
}) {
  if (duration <= 0 || pageCount <= 1) return 0;
  final page = (elapsedSeconds / duration * pageCount).floor();

  return page.clamp(0, pageCount - 1);
}

/// The absolute seek position, in seconds, that [page] (0-based, out of
/// [pageCount]) starts at within a file [duration] seconds long.
double startSecondsForPage({
  required int page,
  required double duration,
  required int pageCount,
}) {
  if (pageCount <= 1) return 0;

  return duration * page / pageCount;
}
