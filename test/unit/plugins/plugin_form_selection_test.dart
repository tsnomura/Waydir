import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/plugins/plugin_form_dialog.dart';
import 'package:waydir/features/plugins/plugin_models.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  group('pluginFieldSelection', () {
    test('all selects the whole text', () {
      final s = pluginFieldSelection('report.final.md', 'all');
      expect([s.start, s.end], [0, 15]);
    });

    test('stem stops before the last dot', () {
      final s = pluginFieldSelection('report.final.md', 'stem');
      expect([s.start, s.end], [0, 12]);
    });

    test('stem selects everything without an extension', () {
      expect(pluginFieldSelection('README', 'stem').end, 6);
      expect(pluginFieldSelection('.bashrc', 'stem').end, 7);
    });

    test('start and the default collapse the caret', () {
      expect(
        pluginFieldSelection('abc', 'start'),
        const TextSelection.collapsed(offset: 0),
      );
      expect(
        pluginFieldSelection('abc', null),
        const TextSelection.collapsed(offset: 3),
      );
    });
  });

  test('field schema reads select', () {
    final f = PluginFormField.fromJson({
      'id': 'name',
      'type': 'input',
      'select': 'ALL',
    });
    expect(f.select, 'all');
    expect(PluginFormField.fromJson({'id': 'x'}).select, isNull);
  });

  testWidgets('the dialog focuses the selected field and keeps the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPluginFormDialog(
              context: context,
              title: 'T',
              fields: const [
                PluginFormField(
                  id: 'note',
                  type: 'input',
                  label: 'Note',
                  defaultValue: 'n',
                ),
                PluginFormField(
                  id: 'name',
                  type: 'input',
                  label: 'Name',
                  defaultValue: 'memo.txt',
                  select: 'stem',
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].focusNode.hasFocus, isFalse);
    expect(fields[1].focusNode.hasFocus, isTrue);
    final sel = fields[1].controller.selection;
    expect([sel.start, sel.end], [0, 4]);
  });
}
