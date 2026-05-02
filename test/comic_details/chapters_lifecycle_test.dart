import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

class _DependencyMarker extends InheritedWidget {
  const _DependencyMarker({
    required this.tick,
    required super.child,
  });

  final int tick;

  @override
  bool updateShouldNotify(covariant _DependencyMarker oldWidget) {
    return tick != oldWidget.tick;
  }
}

class _ControllerHarness extends StatefulWidget {
  const _ControllerHarness({
    super.key,
    required this.tick,
    required this.length,
    required this.stateKey,
  });

  final int tick;
  final int length;
  final GlobalKey<_ControllerHarnessState> stateKey;

  @override
  State<_ControllerHarness> createState() => _ControllerHarnessState();
}

class _ControllerHarnessState extends State<_ControllerHarness>
    with SingleTickerProviderStateMixin {
  TabController? controller;
  int listenerCalls = 0;

  void _listener() {
    listenerCalls++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.dependOnInheritedWidgetOfExactType<_DependencyMarker>();
    controller = syncGroupedChapterTabControllerForTesting(
      current: controller,
      requestedIndex: controller?.index ?? 0,
      length: widget.length,
      vsync: this,
      listener: _listener,
    );
  }

  @override
  void dispose() {
    controller?.removeListener(_listener);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ShowAllHarness extends StatefulWidget {
  const _ShowAllHarness({
    super.key,
    required this.tick,
    required this.sourceKey,
    required this.comicId,
    required this.stateKey,
  });

  final int tick;
  final String sourceKey;
  final String comicId;
  final GlobalKey<_ShowAllHarnessState> stateKey;

  @override
  State<_ShowAllHarness> createState() => _ShowAllHarnessState();
}

class _ShowAllHarnessState extends State<_ShowAllHarness> {
  bool showAll = false;
  String? identity;

  void collapse() {
    setState(() {
      showAll = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.dependOnInheritedWidgetOfExactType<_DependencyMarker>();
    final nextIdentity = '${widget.sourceKey}:${widget.comicId}';
    showAll = updateChapterShowAllForDependencyForTesting(
      currentShowAll: showAll,
      isLocalSource: widget.sourceKey == localSourceKey,
      previousIdentity: identity,
      nextIdentity: nextIdentity,
    );
    identity = nextIdentity;
  }

  @override
  Widget build(BuildContext context) => Text('showAll=$showAll');
}

void main() {
  testWidgets(
    'chapter tab controller does not accumulate listeners after dependency changes',
    (tester) async {
      final key = GlobalKey<_ControllerHarnessState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _DependencyMarker(
            tick: 0,
            child: _ControllerHarness(
              tick: 0,
              length: 3,
              stateKey: key,
              key: key,
            ),
          ),
        ),
      );

      key.currentState!.controller!.index = 1;
      await tester.pump();
      expect(key.currentState!.listenerCalls, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: _DependencyMarker(
            tick: 1,
            child: _ControllerHarness(
              tick: 1,
              length: 3,
              stateKey: key,
              key: key,
            ),
          ),
        ),
      );

      key.currentState!.controller!.index = 2;
      await tester.pump();
      expect(key.currentState!.listenerCalls, 2);
    },
  );

  testWidgets(
    'grouped chapters keep visited state mapped to source index when reversed',
    (tester) async {
      final history = History.fromMap({
        'type': ComicType.local.value,
        'time': DateTime(2026).millisecondsSinceEpoch,
        'title': 'Title',
        'subtitle': '',
        'cover': '',
        'ep': 1,
        'page': 1,
        'id': 'comic-1',
        'group': 2,
        'readEpisode': const <String>['5', '2-3'],
      });

      final selection = resolveGroupedChapterSelectionForTesting(
        groupLengths: const [2, 3],
        groupIndex: 1,
        displayIndex: 0,
        reverse: true,
      );

      expect(selection.sourceIndex, 2);
      expect(selection.chapterIndex, 4);
      expect(selection.rawIndex, '5');
      expect(selection.groupedIndex, '2-3');
      expect(
        comicChapterIsVisited(
          history,
          rawIndex: selection.rawIndex,
          groupedIndex: selection.groupedIndex,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'chapter list does not reset showAll on unrelated dependency rebuild',
    (tester) async {
      final key = GlobalKey<_ShowAllHarnessState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _DependencyMarker(
            tick: 0,
            child: _ShowAllHarness(
              tick: 0,
              sourceKey: localSourceKey,
              comicId: 'comic-1',
              stateKey: key,
              key: key,
            ),
          ),
        ),
      );

      expect(key.currentState!.showAll, isTrue);
      key.currentState!.collapse();
      await tester.pump();
      expect(key.currentState!.showAll, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: _DependencyMarker(
            tick: 1,
            child: _ShowAllHarness(
              tick: 1,
              sourceKey: localSourceKey,
              comicId: 'comic-1',
              stateKey: key,
              key: key,
            ),
          ),
        ),
      );

      expect(key.currentState!.showAll, isFalse);
    },
  );
}
