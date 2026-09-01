import 'package:signals/signals.dart';

/// Shared paging state between Quick Look's PageUp/PageDown handling and
/// whichever [GeneratorPreview] is currently shown. The key handler lives
/// above `_Body` in the widget tree and doesn't know what kind of content is
/// currently rendered, so it defers to [pageCount] here to decide whether
/// PageUp/PageDown pages through a multi-frame generator preview or falls
/// back to scrolling the content as usual.
class GeneratorPageController {
  final position = signal(0);
  int pageCount = 1;

  void next() {
    if (position.value < pageCount - 1) position.value++;
  }

  void prev() {
    if (position.value > 0) position.value--;
  }

  void reset() {
    pageCount = 1;
    position.value = 0;
  }

  void dispose() => position.dispose();
}
