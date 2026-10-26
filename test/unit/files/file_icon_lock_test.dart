import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_reader.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/files/file_icons.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('waydir_icon_lock');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  FileEntry zipEntry(String name) => FileEntry.raw(
    name: name,
    path: p.join(tmp.path, name),
    type: FileItemType.file,
    size: 10,
    modifiedMs: 1000,
  );

  List<String> assetsOf(WidgetTester tester) => tester
      .widgetList<SvgPicture>(find.byType(SvgPicture))
      .map((w) => (w.bytesLoader as SvgAssetLoader).assetName)
      .toList();

  testWidgets('shows a lock badge on an encrypted zip', (tester) async {
    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: zipEntry('data.zip'),
          size: 20,
          isEncrypted: (_) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(assetsOf(tester), [
      'assets/icons/material/zip.svg',
      'assets/icons/material/lock.svg',
    ]);
  });

  testWidgets('keeps archive icon for an unencrypted zip', (tester) async {
    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: zipEntry('data.zip'),
          size: 20,
          isEncrypted: (_) async => false,
        ),
      ),
    );
    await tester.pump();

    expect(assetsOf(tester), ['assets/icons/material/zip.svg']);
  });

  testWidgets('does not check encryption for non-zip files', (tester) async {
    var called = false;
    final entry = FileEntry.raw(
      name: 'doc.txt',
      path: p.join(tmp.path, 'doc.txt'),
      type: FileItemType.file,
      size: 10,
      modifiedMs: 1000,
    );

    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: entry,
          size: 20,
          isEncrypted: (_) async {
            called = true;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(called, isFalse);
    expect(assetsOf(tester), ['assets/icons/material/document.svg']);
  });

  testWidgets('cached result is reused without querying again', (tester) async {
    final entry = zipEntry('cached.zip');
    await tester.pumpWidget(
      wrap(
        FileEntryIcon(entry: entry, size: 20, isEncrypted: (_) async => true),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: entry,
          size: 20,
          isEncrypted: (_) async => throw StateError('must not be called'),
        ),
      ),
    );
    await tester.pump();

    expect(assetsOf(tester), [
      'assets/icons/material/zip.svg',
      'assets/icons/material/lock.svg',
    ]);
  });

  testWidgets('real password zip made by ZipEncoder gets the badge', (
    tester,
  ) async {
    final path = p.join(tmp.path, 'enc.zip');
    final archive = Archive()..addFile(ArchiveFile.string('note.txt', 'hello'));
    File(path).writeAsBytesSync(ZipEncoder(password: 'secret').encode(archive));

    final entry = FileEntry.raw(
      name: 'enc.zip',
      path: path,
      type: FileItemType.file,
      size: 10,
      modifiedMs: 1000,
    );

    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: entry,
          size: 20,
          isEncrypted: ArchiveReader.isEncrypted,
        ),
      ),
    );
    await tester.pump();

    expect(assetsOf(tester), [
      'assets/icons/material/zip.svg',
      'assets/icons/material/lock.svg',
    ]);
  });

  testWidgets('an entry flagged encrypted shows a full lock icon', (
    tester,
  ) async {
    var called = false;
    final entry = FileEntry.raw(
      name: 'secret.txt',
      path: p.join(tmp.path, 'mixed.zip', 'secret.txt'),
      type: FileItemType.file,
      size: 10,
      modifiedMs: 1000,
      encrypted: true,
    );

    await tester.pumpWidget(
      wrap(
        FileEntryIcon(
          entry: entry,
          size: 20,
          isEncrypted: (_) async {
            called = true;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(called, isFalse);
    expect(assetsOf(tester), ['assets/icons/material/lock.svg']);
  });

  testWidgets('unflagged entries inside an archive keep their file icon', (
    tester,
  ) async {
    final entry = FileEntry.raw(
      name: 'open.txt',
      path: p.join(tmp.path, 'mixed.zip', 'open.txt'),
      type: FileItemType.file,
      size: 10,
      modifiedMs: 1000,
    );

    await tester.pumpWidget(
      wrap(
        FileEntryIcon(entry: entry, size: 20, isEncrypted: (_) async => false),
      ),
    );
    await tester.pump();

    expect(assetsOf(tester), ['assets/icons/material/document.svg']);
  });
}
