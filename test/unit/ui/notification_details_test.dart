import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/app_notification.dart';
import 'package:waydir/core/models/file_operation.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:waydir/ui/overlays/notification_overlay.dart';
import 'package:waydir/ui/overlays/notification_store.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  Widget buildApp(NotificationStore store) {
    return MaterialApp(
      theme: AppTheme.build(),
      home: Stack(children: [NotificationOverlay(store: store)]),
    );
  }

  testWidgets('tapping a notification with errors shows the error details', (
    tester,
  ) async {
    final store = NotificationStore();
    store.add(
      AppNotification(
        id: 'op_failed',
        title: 'Copy 2 files',
        message: 'Completed with 1 error',
        type: NotificationType.persistent,
        errors: [
          TaskError(
            path: '/home/user/secret.txt',
            message: 'Permission denied',
          ),
        ],
      ),
    );

    await tester.pumpWidget(buildApp(store));
    await tester.pumpAndSettle();

    expect(find.text('Completed with 1 error'), findsOneWidget);

    await tester.tap(find.text('Completed with 1 error'));
    await tester.pumpAndSettle();

    expect(find.text('Errors (1)'), findsOneWidget);
    expect(find.text('secret.txt'), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
  });

  testWidgets('tapping a notification without errors does not open a dialog', (
    tester,
  ) async {
    final store = NotificationStore();
    store.add(
      AppNotification(
        id: 'op_ok',
        title: 'Copy 2 files',
        message: 'Completed',
        type: NotificationType.persistent,
      ),
    );

    await tester.pumpWidget(buildApp(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsNothing);
  });

  testWidgets('dismissing the card still removes the notification', (
    tester,
  ) async {
    final store = NotificationStore();
    store.add(
      AppNotification(
        id: 'op_failed',
        title: 'Copy 2 files',
        message: 'Completed with 1 error',
        type: NotificationType.persistent,
        errors: [TaskError(path: '/home/user/a.txt', message: 'denied')],
      ),
    );

    await tester.pumpWidget(buildApp(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(WaydirIconsRegular.x));
    await tester.pumpAndSettle();

    expect(find.text('Completed with 1 error'), findsNothing);
  });
}
