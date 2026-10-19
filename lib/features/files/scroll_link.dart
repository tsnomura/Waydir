import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:signals/signals.dart';

class ScrollRequest {
  final double offset;
  final int serial;

  const ScrollRequest(this.offset, this.serial);
}

class ScrollLink {
  final reported = signal<double>(0);
  final requested = signal<ScrollRequest?>(null);
  int _serial = 0;
  final _offsets = <String, double>{};

  void report(double offset) => reported.value = offset;

  double offsetFor(String key) => _offsets[key] ?? 0;

  void remember(String key, double offset) {
    if (offset > 0) {
      _offsets[key] = offset;
    } else {
      _offsets.remove(key);
    }
  }

  void request(double offset) =>
      requested.value = ScrollRequest(offset, ++_serial);
}

mixin ScrollLinkBinding<T extends StatefulWidget> on State<T> {
  ScrollController get linkedScrollController;
  ScrollLink? get scrollLink;
  String get scrollMemoryKey;

  ScrollLink? _bound;
  void Function()? _requestDisposer;
  bool _applyingRemote = false;
  int _lastSerial = 0;

  void initScrollLink() {
    linkedScrollController.addListener(_reportScroll);
    _bind(scrollLink);
  }

  void updateScrollLink() {
    if (!identical(_bound, scrollLink)) _bind(scrollLink);
  }

  void switchScrollMemory(String fromKey) {
    final link = _bound;
    if (link == null || fromKey == scrollMemoryKey) return;
    if (linkedScrollController.hasClients) {
      link.remember(fromKey, linkedScrollController.offset);
    }
    final target = link.offsetFor(scrollMemoryKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !linkedScrollController.hasClients) return;
      final position = linkedScrollController.position;
      linkedScrollController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  void disposeScrollLink() {
    linkedScrollController.removeListener(_reportScroll);
    _requestDisposer?.call();
    _requestDisposer = null;
  }

  void _bind(ScrollLink? link) {
    _requestDisposer?.call();
    _requestDisposer = null;
    _bound = link;
    if (link == null) return;
    _lastSerial = link.requested.value?.serial ?? 0;
    _requestDisposer = effect(() {
      final request = link.requested.value;
      if (request == null || request.serial == _lastSerial) return;
      _lastSerial = request.serial;
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
        _apply(request);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _apply(request));
      }
    });
  }

  void _apply(ScrollRequest request) {
    if (!mounted || !linkedScrollController.hasClients) return;
    final position = linkedScrollController.position;
    final target = request.offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((position.pixels - target).abs() < 0.5) return;
    _applyingRemote = true;
    try {
      linkedScrollController.jumpTo(target);
    } finally {
      _applyingRemote = false;
    }
  }

  void _reportScroll() {
    if (!linkedScrollController.hasClients) return;
    _bound?.remember(scrollMemoryKey, linkedScrollController.offset);
    if (_applyingRemote) return;
    _bound?.report(linkedScrollController.offset);
  }
}
