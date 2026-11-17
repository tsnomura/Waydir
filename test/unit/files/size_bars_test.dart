import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/files/file_view.dart';
import 'package:waydir/ui/theme/app_theme.dart';

FileEntry _entry(String name, FileItemType type, int size) => FileEntry(
  name: name,
  path: '/tmp/$name',
  type: type,
  size: size,
  modified: DateTime(2026),
);

List<double> _barFractions(WidgetTester tester) => [
  for (final box in tester.widgetList<Container>(find.byType(Container)))
    if (box.decoration case BoxDecoration(
      gradient: LinearGradient(:final stops?),
    ))
      stops[1],
];

Future<void> _pump(WidgetTester tester, {required bool sizeBars}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: FileList(
          files: [
            _entry('big.bin', FileItemType.file, 400),
            _entry('small.txt', FileItemType.file, 100),
            _entry('dir', FileItemType.folder, 0),
            _entry('unknown', FileItemType.folder, 0),
          ],
          currentPath: '/tmp',
          onSelect: (_) {},
          onOpen: (_) {},
          folderSizes: const {'/tmp/dir': 200},
          sizeBars: sizeBars,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('rows show bars scaled to the largest item', (tester) async {
    await _pump(tester, sizeBars: true);

    expect(_barFractions(tester), [1.0, 0.25, 0.5]);
  });

  testWidgets('rows show no bars when size bars are off', (tester) async {
    await _pump(tester, sizeBars: false);

    expect(_barFractions(tester), isEmpty);
  });
}
