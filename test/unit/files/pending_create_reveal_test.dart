import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/files/file_view.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  testWidgets('starting a new folder scrolls its name field into view', (
    tester,
  ) async {
    String? renamingPath;
    var cursor = 150;
    late StateSetter setState;

    final pending = FileEntry(
      name: '',
      path: '__pending_create__',
      type: FileItemType.folder,
      size: 0,
      modified: DateTime.now(),
    );
    final existing = [
      for (var i = 0; i < 200; i++)
        FileEntry(
          name: 'item$i',
          path: '/tmp/item$i',
          type: FileItemType.file,
          size: 0,
          modified: DateTime.now(),
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, s) {
              setState = s;
              return FileList(
                files: renamingPath == null ? existing : [pending, ...existing],
                currentPath: '/tmp',
                cursorIndex: cursor,
                onSelect: (_) {},
                onOpen: (_) {},
                renamingPath: renamingPath,
                onRenameSubmit: (_) {},
                onRenameCancel: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('item150'), findsOneWidget);
    expect(find.text('item0'), findsNothing);

    setState(() {
      renamingPath = '__pending_create__';
      cursor = 151;
    });
    await tester.pumpAndSettle();

    expect(find.byType(EditableText), findsOneWidget);
  });
}
