import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';

void main() {
  FileEntry entry(String name, FileItemType type, {bool hidden = false}) =>
      FileEntry.raw(
        name: name,
        path: '/d/$name',
        type: type,
        size: 1,
        modifiedMs: 0,
        hiddenAttr: hidden,
      );

  test('the hidden attribute survives an encode/decode round trip', () {
    final decoded = FileEntryCodec.decode(
      FileEntryCodec.encode([
        entry('plain.txt', FileItemType.file),
        entry('secret.txt', FileItemType.file, hidden: true),
        entry('folder', FileItemType.folder),
        entry('hidden_folder', FileItemType.folder, hidden: true),
      ]),
    );

    expect(
      [for (final e in decoded) (e.name, e.type, e.hiddenAttr, e.isHidden)],
      [
        ('plain.txt', FileItemType.file, false, false),
        ('secret.txt', FileItemType.file, true, true),
        ('folder', FileItemType.folder, false, false),
        ('hidden_folder', FileItemType.folder, true, true),
      ],
    );
  });

  test('dot files stay hidden without the attribute', () {
    expect(entry('.env', FileItemType.file).isHidden, isTrue);
  });
}
