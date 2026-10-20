import 'package:signals/signals.dart';

import '../../core/models/file_entry.dart';

class ItemCursor {
  final List<FileEntry> Function() _items;
  final path = signal<String?>(null);
  int _hint = -1;
  List<FileEntry>? _memoList;
  String? _memoPath;
  int _memoIndex = -1;

  ItemCursor(this._items);

  int get value => _resolve(path.value, _items());

  set value(int index) {
    final list = untracked(_items);
    if (index < 0 || index >= list.length) {
      _hint = -1;
      path.value = null;

      return;
    }
    _hint = index;
    path.value = list[index].path;
  }

  int peek() => untracked(() => value);

  int _resolve(String? target, List<FileEntry> list) {
    if (target == null || list.isEmpty) return -1;
    if (identical(list, _memoList) && target == _memoPath) return _memoIndex;
    var index = -1;
    if (_hint >= 0 && _hint < list.length && list[_hint].path == target) {
      index = _hint;
    } else {
      index = list.indexWhere((f) => f.path == target);
    }
    if (index >= 0) {
      _hint = index;
    } else {
      index = _hint < 0 ? 0 : _hint.clamp(0, list.length - 1);
    }
    _memoList = list;
    _memoPath = target;
    _memoIndex = index;

    return index;
  }
}
