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

  group('sameDrivesForDisplay', () {
    Drive spaced(int free) => Drive(
      id: '/dev/sdb1',
      label: 'data',
      mountPoint: '/mnt/data',
      isRemovable: false,
      space: DriveSpace(totalBytes: 1000000, freeBytes: free),
    );

    test('ignores free space changes below 0.1% of the disk', () {
      expect(sameDrivesForDisplay([spaced(500000)], [spaced(500999)]), isTrue);
    });

    test('reports free space changes of 0.1% or more', () {
      expect(sameDrivesForDisplay([spaced(500000)], [spaced(501000)]), isFalse);
    });

    test('reports any other change', () {
      expect(
        sameDrivesForDisplay([spaced(500000)], [_drive('/dev/sdb1')]),
        isFalse,
      );
      expect(sameDrivesForDisplay([spaced(500000)], []), isFalse);
      expect(
        sameDrivesForDisplay(
          [spaced(500000)],
          [
            Drive(
              id: '/dev/sdb1',
              label: 'renamed',
              mountPoint: '/mnt/data',
              isRemovable: false,
              space: const DriveSpace(totalBytes: 1000000, freeBytes: 500000),
            ),
          ],
        ),
        isFalse,
      );
    });
  });

  test('small free space drift accumulates until it is published', () async {
    final service = _SlowDriveService();
    final store = DriveStore(service: service);
    addTearDown(store.dispose);
    Drive at(int free) => Drive(
      id: '/',
      label: 'root',
      isRemovable: false,
      space: DriveSpace(totalBytes: 1000000, freeBytes: free),
    );

    service.pending.last.complete([at(500000)]);
    await pumpEventQueue();
    final shown = store.drives.value;

    for (final free in [500400, 500800]) {
      store.refresh();
      service.pending.last.complete([at(free)]);
      await pumpEventQueue();
      expect(identical(store.drives.value, shown), isTrue);
    }

    store.refresh();
    service.pending.last.complete([at(501200)]);
    await pumpEventQueue();
    expect(store.drives.value.single.space!.freeBytes, 501200);
  });
}
