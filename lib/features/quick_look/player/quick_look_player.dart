/// Quick Look's view of audio playback: start playing a file from a given
/// position, or stop whatever's currently playing. Paging, auto-advance,
/// debouncing and every other rule about *when* to call these live in
/// [QuickLookPlaybackController] — an implementation only ever does what
/// it's told.
abstract class QuickLookPlayer {
  Future<void> play(String path, double startSeconds);
  Future<void> stop();
}
