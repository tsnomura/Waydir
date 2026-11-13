import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/media_info.dart';
import 'package:waydir/features/quick_look/player/in_app_video.dart';
import 'package:waydir/features/quick_look/quick_look_common.dart';

FileEntry _videoEntry(String name, String path) => FileEntry.raw(
  name: name,
  path: path,
  type: FileItemType.file,
  size: 1,
  modifiedMs: 0,
);

void main() {
  group('Quick Look extension sets do not overlap', () {
    test('pdf and binary sets are disjoint', () {
      expect(pdfExts.intersection(binaryExts), isEmpty);
    });

    test('pdf and image sets are disjoint', () {
      expect(pdfExts.intersection(imageExts), isEmpty);
    });

    test('image and binary sets are disjoint', () {
      expect(imageExts.intersection(binaryExts), isEmpty);
    });
  });

  group('PDF routing', () {
    test('pdf routes to PDF preview', () {
      expect(pdfExts.contains('pdf'), isTrue);
    });

    test('pdf is not in binary fallback', () {
      expect(binaryExts.contains('pdf'), isFalse);
    });
  });

  group('Image routing', () {
    final imageTypes = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'];

    for (final ext in imageTypes) {
      test('.$ext routes to image preview', () {
        expect(imageExts.contains(ext), isTrue);
        expect(binaryExts.contains(ext), isFalse);
      });
    }
  });

  group('Markdown routing', () {
    test('markdown and binary sets are disjoint', () {
      expect(markdownExts.intersection(binaryExts), isEmpty);
    });

    test('.md and .markdown route to markdown preview', () {
      expect(markdownExts.contains('md'), isTrue);
      expect(markdownExts.contains('markdown'), isTrue);
      expect(binaryExts.contains('md'), isFalse);
      expect(imageExts.contains('md'), isFalse);
      expect(pdfExts.contains('md'), isFalse);
    });
  });

  group('Binary fallback routing', () {
    final archiveTypes = ['zip', 'tar', '7z', 'gz', 'bz2', 'rar', 'xz'];
    final mediaTypes = ['mp3', 'mp4', 'mkv', 'wav', 'flac', 'ogg', 'aac'];
    final officeTypes = ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'];
    final execTypes = ['exe', 'dll', 'so', 'dylib'];

    for (final ext in [
      ...archiveTypes,
      ...mediaTypes,
      ...officeTypes,
      ...execTypes,
    ]) {
      test('.$ext routes to binary fallback', () {
        expect(binaryExts.contains(ext), isTrue);
      });
    }
  });

  group('Video routing', () {
    test('video and image sets are disjoint', () {
      expect(mediaVideoExts.intersection(imageExts), isEmpty);
    });

    test('local video routes to the in-app preview', () {
      final entry = _videoEntry('clip.mp4', '/tmp/clip.mp4');
      expect(InAppVideoPlayer.canPreview(entry), isTrue);
    });

    test('remote video does not route to the in-app preview', () {
      final entry = _videoEntry('clip.mp4', 'sftp://example.com/clip.mp4');
      expect(InAppVideoPlayer.canPreview(entry), isFalse);
    });
  });
}
