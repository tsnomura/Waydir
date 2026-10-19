import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/files/scroll_link.dart';

class _Harness extends StatefulWidget {
  final String path;
  final ScrollLink link;

  const _Harness({super.key, required this.path, required this.link});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with ScrollLinkBinding {
  late final _controller = ScrollController(
    initialScrollOffset: widget.link.offsetFor(scrollMemoryKey),
  );

  @override
  ScrollController get linkedScrollController => _controller;

  @override
  ScrollLink? get scrollLink => widget.link;

  @override
  String get scrollMemoryKey => 'list|${widget.path}';

  @override
  void initState() {
    super.initState();
    initScrollLink();
  }

  @override
  void didUpdateWidget(covariant _Harness oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateScrollLink();
    if (oldWidget.path != widget.path) {
      switchScrollMemory('list|${oldWidget.path}');
    }
  }

  @override
  void dispose() {
    disposeScrollLink();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemExtent: 20,
      itemCount: 500,
      itemBuilder: (context, i) => Text('$i'),
    );
  }
}

void main() {
  late ScrollLink link;
  setUp(() => link = ScrollLink());

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 400, child: child)),
  );

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  testWidgets('a recreated list starts at the offset it was left at', (
    tester,
  ) async {
    await tester.pumpWidget(host(_Harness(path: 'A', link: link)));
    position(tester).jumpTo(1200);
    await tester.pump();

    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpWidget(host(_Harness(path: 'B', link: link)));
    expect(position(tester).pixels, 0);

    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpWidget(host(_Harness(path: 'A', link: link)));
    expect(position(tester).pixels, 1200);
  });

  testWidgets('a list kept across a path change swaps offsets', (tester) async {
    const key = ValueKey('list');
    await tester.pumpWidget(host(_Harness(key: key, path: 'A', link: link)));
    position(tester).jumpTo(800);
    await tester.pump();

    await tester.pumpWidget(host(_Harness(key: key, path: 'B', link: link)));
    await tester.pump();
    expect(position(tester).pixels, 0);
    position(tester).jumpTo(300);
    await tester.pump();

    await tester.pumpWidget(host(_Harness(key: key, path: 'A', link: link)));
    await tester.pump();
    expect(position(tester).pixels, 800);

    await tester.pumpWidget(host(_Harness(key: key, path: 'B', link: link)));
    await tester.pump();
    expect(position(tester).pixels, 300);
  });

  test('remembering offset 0 forgets the key', () {
    link.remember('list|A', 50);
    expect(link.offsetFor('list|A'), 50);
    link.remember('list|A', 0);
    expect(link.offsetFor('list|A'), 0);
  });
}
