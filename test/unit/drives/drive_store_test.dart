import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/drives/drive_model.dart';
import 'package:waydir/features/drives/drive_service.dart';
import 'package:waydir/features/drives/drive_store.dart';

class _SlowDriveService implements DriveService {
  final pending = <Completer<List<Drive>>>[];

  @override
  Future<List<Drive>> getDrives() {
    final completer = Completer<List<Drive>>();
    pending.add(completer);

    return completer.future;
  }

  @override
  Future<void> mount(Drive drive) async {}

  @override
  Future<void> mountWithPassword(Drive drive, String password) async {}

  @override
  Future<void> unmount(Drive drive) async {}
}

Drive _drive(String id) => Drive(id: id, label: id, isRemovable: false);

void main() {
  test('a slow drive probe never stacks up and keeps the last list', () async {
    final service = _SlowDriveService();
    final store = DriveStore(service: service);
    addTearDown(store.dispose);

    expect(service.pending, hasLength(1));
    store.refresh();
    store.refresh();
    store.refresh();
    expect(service.pending, hasLength(1));

    service.pending.first.complete([_drive('C:\\')]);
    await pumpEventQueue();

    expect(store.drives.value.map((d) => d.id), ['C:\\']);
    expect(service.pending, hasLength(2));

    store.refresh();
    expect(service.pending, hasLength(2));
    service.pending.last.complete([_drive('C:\\'), _drive('D:\\')]);
    await pumpEventQueue();

    expect(store.drives.value.map((d) => d.id), ['C:\\', 'D:\\']);
    expect(service.pending, hasLength(3));
  });
}
