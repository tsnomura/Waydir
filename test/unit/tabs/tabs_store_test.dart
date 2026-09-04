import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/tabs/tabs_store.dart';

late OperationStore _ops;
late TabsStore _tabs;

void main() {
  setUp(() {
    _ops = OperationStore();
    _tabs = TabsStore.fromPaths(
      operationStore: _ops,
      paths: const ['/one', '/two', '/three'],
      activeTabIndex: 1,
    );
    addTearDown(() {
      _tabs.dispose();
      _ops.dispose();
    });
  });

  group('TabsStore.fromPaths', () {
    test('falls back to home when paths list is empty', () {
      final store = TabsStore.fromPaths(operationStore: _ops, paths: []);
      addTearDown(store.dispose);

      expect(store.tabs.value.length, 1);
    });

    test('clamps activeTabIndex to valid range', () {
      final store = TabsStore.fromPaths(
        operationStore: _ops,
        paths: ['/a', '/b'],
        activeTabIndex: 99,
      );
      addTearDown(store.dispose);

      expect(store.activeIndex.value, 1);
    });
  });

  group('TabsStore.reorderTab', () {
    test('moves tab forward and tracks active tab by identity', () {
      final activeId = _tabs.activeTab.value.id;

      _tabs.reorderTab(1, 0);

      expect(_tabs.tabs.value.map((t) => t.store.currentPath.value), [
        '/two',
        '/one',
        '/three',
      ]);
      expect(_tabs.activeTab.value.id, activeId);
      expect(_tabs.activeIndex.value, 0);
    });

    test('moves tab backward', () {
      _tabs.reorderTab(0, 2);

      expect(_tabs.tabs.value.map((t) => t.store.currentPath.value), [
        '/two',
        '/three',
        '/one',
      ]);
    });

    test('is a no-op when from equals to', () {
      final before = _tabs.tabs.value.map((t) => t.id).toList();

      _tabs.reorderTab(1, 1);

      expect(_tabs.tabs.value.map((t) => t.id).toList(), before);
    });

    test('ignores out-of-range from index', () {
      final before = _tabs.tabs.value.map((t) => t.id).toList();

      _tabs.reorderTab(-1, 0);

      expect(_tabs.tabs.value.map((t) => t.id).toList(), before);
    });

    test('ignores out-of-range to index', () {
      final before = _tabs.tabs.value.map((t) => t.id).toList();

      _tabs.reorderTab(0, 99);

      expect(_tabs.tabs.value.map((t) => t.id).toList(), before);
    });
  });

  group('TabsStore.addTab', () {
    test('appends and activates the new tab', () {
      _tabs.addTab('/four');

      expect(_tabs.tabs.value.length, 4);
      expect(_tabs.activeIndex.value, 3);
      expect(_tabs.activeTab.value.store.currentPath.value, '/four');
    });

    test('appends without changing activeIndex when activate is false', () {
      final prevIndex = _tabs.activeIndex.value;

      _tabs.addTab('/four', activate: false);

      expect(_tabs.tabs.value.length, 4);
      expect(_tabs.activeIndex.value, prevIndex);
    });
  });

  group('TabsStore.closeTab', () {
    test(
      'shifts activeIndex left when closing a tab before the active one',
      () {
        final activeId = _tabs.activeTab.value.id;

        _tabs.closeTab(_tabs.tabs.value.first.id);

        expect(_tabs.tabs.value.length, 2);
        expect(_tabs.activeTab.value.id, activeId);
        expect(_tabs.activeIndex.value, 0);
      },
    );

    test(
      'moves activeIndex to last when closing the last tab while active',
      () {
        _tabs.selectTab(2);

        _tabs.closeTab(_tabs.tabs.value[2].id);

        expect(_tabs.tabs.value.length, 2);
        expect(_tabs.activeIndex.value, 1);
      },
    );

    test('does not close the last remaining tab', () {
      final store = TabsStore.fromPaths(operationStore: _ops, paths: ['/only']);
      addTearDown(store.dispose);

      store.closeTab(store.tabs.value.first.id);

      expect(store.tabs.value.length, 1);
    });

    test('ignores an unknown tab id', () {
      _tabs.closeTab('no-such-id');

      expect(_tabs.tabs.value.length, 3);
    });
  });

  group('TabsStore.takeTab', () {
    test('removes and returns the tab without disposing its store', () {
      final target = _tabs.tabs.value[0];

      final taken = _tabs.takeTab(target.id);

      expect(taken, isNotNull);
      expect(taken!.id, target.id);
      expect(_tabs.tabs.value.length, 2);
      // Not disposed: still readable.
      expect(taken.store.currentPath.value, '/one');
    });

    test('shifts activeIndex left when taking a tab before the active one', () {
      final activeId = _tabs.activeTab.value.id;

      _tabs.takeTab(_tabs.tabs.value.first.id);

      expect(_tabs.activeTab.value.id, activeId);
      expect(_tabs.activeIndex.value, 0);
    });

    test('refuses to take the last remaining tab', () {
      final store = TabsStore.fromPaths(operationStore: _ops, paths: ['/only']);
      addTearDown(store.dispose);

      final taken = store.takeTab(store.tabs.value.first.id);

      expect(taken, isNull);
      expect(store.tabs.value.length, 1);
    });

    test('returns null for an unknown tab id', () {
      expect(_tabs.takeTab('no-such-id'), isNull);
      expect(_tabs.tabs.value.length, 3);
    });
  });

  group('TabsStore.insertTab', () {
    test('inserts and activates a tab taken from another store', () {
      final other = TabsStore.fromPaths(
        operationStore: _ops,
        paths: const ['/moved', '/stays'],
      );
      final taken = other.takeTab(other.tabs.value.first.id);
      addTearDown(other.dispose);

      _tabs.insertTab(taken!);

      expect(_tabs.tabs.value.length, 4);
      expect(_tabs.activeTab.value.id, taken.id);
      expect(_tabs.activeTab.value.store.currentPath.value, '/moved');
    });

    test('inserts at a specific index without activating', () {
      final other = TabsStore.fromPaths(
        operationStore: _ops,
        paths: const ['/moved', '/stays'],
      );
      final taken = other.takeTab(other.tabs.value.first.id);
      addTearDown(other.dispose);
      final prevActiveId = _tabs.activeTab.value.id;

      _tabs.insertTab(taken!, index: 0, activate: false);

      expect(_tabs.tabs.value.map((t) => t.id).first, taken.id);
      expect(_tabs.activeTab.value.id, prevActiveId);
    });
  });

  group('TabsStore.selectTab', () {
    test('updates activeIndex for a valid index', () {
      _tabs.selectTab(2);

      expect(_tabs.activeIndex.value, 2);
      expect(_tabs.activeTab.value.store.currentPath.value, '/three');
    });

    test('ignores negative index', () {
      _tabs.selectTab(-1);

      expect(_tabs.activeIndex.value, 1);
    });

    test('ignores index beyond last tab', () {
      _tabs.selectTab(99);

      expect(_tabs.activeIndex.value, 1);
    });
  });
}
