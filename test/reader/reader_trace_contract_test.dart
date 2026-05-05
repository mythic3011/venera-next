import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/app/app_page_route.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/features/reader/presentation/reader.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
    clearNavigatorRouteDiagnosticsForTesting();
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
    clearNavigatorRouteDiagnosticsForTesting();
  });

  test('required_event_name_and_phase_serialize_consistently', () {
    final recorder = ReaderTraceRecorder();
    recorder.record(
      ReaderTraceEvent(
        event: 'pageList.load.start',
        timestamp: DateTime.utc(2026, 1, 1),
        loadMode: 'remote',
        sourceKey: 'copymanga',
        comicId: 'comic-1',
        chapterId: 'ch-1',
        chapterIndex: 3,
        page: 7,
        phase: ReaderTracePhase.pageList,
      ),
    );

    final json = recorder.toDiagnosticsJson();
    final event =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    expect(event['event'], 'pageList.load.start');
    expect(event['phase'], 'pageList');
    expect(event['loadMode'], 'remote');
    expect(event['sourceKey'], 'copymanga');
    expect(event['comicId'], 'comic-1');
    expect(event['chapterId'], 'ch-1');
    expect(event['chapterIndex'], 3);
    expect(event['page'], 7);
  });

  test('reader route lifecycle trace includes push and pop route identity', () {
    AppDiagnostics.resetForTesting();
    AppDiagnostics.configureSinksForTesting(const []);
    final route = AppPageRoute<void>(
      builder: (_) => const SizedBox(),
      settings: const RouteSettings(name: '/reader'),
    )..label = 'ReaderWithLoading';
    final previousRoute = AppPageRoute<void>(
      builder: (_) => const SizedBox(),
      settings: const RouteSettings(name: '/detail'),
    )..label = 'ComicPage';

    final pushData = buildNavigatorRouteLifecycleDiagnostic(
      event: 'didPush',
      route: route,
      previousRoute: previousRoute,
      pageCountBeforeEvent: 2,
      timestamp: DateTime.utc(2026, 1, 1),
    );
    emitNavigatorRouteLifecycleDiagnostic(pushData);

    final popData = buildNavigatorRouteLifecycleDiagnostic(
      event: 'didPop',
      route: route,
      previousRoute: previousRoute,
      pageCountBeforeEvent: 2,
      timestamp: DateTime.utc(2026, 1, 1, 0, 0, 1),
    );
    emitNavigatorRouteLifecycleDiagnostic(popData);

    final events = DevDiagnosticsApi.recent(channel: 'navigator.lifecycle')
        .where(
          (event) =>
              event.data['timestamp'] == '2026-01-01T00:00:00.000Z' ||
              event.data['timestamp'] == '2026-01-01T00:00:01.000Z',
        )
        .toList();
    expect(events.map((event) => event.message), ['didPush', 'didPop']);
    expect(events.first.data['routeHash'], route.hashCode);
    expect(
      events.first.data['routeDiagnosticIdentity'],
      contains('label=ReaderWithLoading'),
    );
    expect(events.first.data['previousRouteHash'], previousRoute.hashCode);
    expect(events.first.data['pageCountBeforeEvent'], 2);
    expect(
      events.last.data['previousRouteDiagnosticIdentity'],
      contains('label=ComicPage'),
    );
  });

  test(
    'reader parent dispose route hash can be correlated with navigator observer route hash',
    () {
      final route = AppPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/reader'),
      )..label = 'ReaderWithLoading';

      final lifecycle = buildNavigatorRouteLifecycleDiagnostic(
        event: 'didPush',
        route: route,
        previousRoute: null,
        pageCountBeforeEvent: 1,
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final parentDispose = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.parentUnmount',
        branch: 'content',
        readerChildMounted: false,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: '/reader',
        routeSnapshot: {'routeHash': route.hashCode},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        reason: 'parentState.dispose',
        openDurationMs: 1800,
      );

      expect(parentDispose['routeHash'], lifecycle['routeHash']);
    },
  );

  test('all_phases_serialize_to_stable_names', () {
    expect(ReaderTracePhase.sourceResolution.name, 'sourceResolution');
    expect(ReaderTracePhase.pageList.name, 'pageList');
    expect(ReaderTracePhase.thumbnail.name, 'thumbnail');
    expect(ReaderTracePhase.imageProvider.name, 'imageProvider');
    expect(ReaderTracePhase.decode.name, 'decode');
    expect(ReaderTracePhase.cache.name, 'cache');
  });

  test('reader dispose trace keeps expected diagnostic fields', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
    );

    final json = ReaderDiagnostics.toDiagnosticsJson();
    final recordedEvent =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;

    expect(recordedEvent['event'], 'reader.dispose');
    expect(recordedEvent['phase'], 'sourceResolution');
    expect(recordedEvent['loadMode'], 'local');
    expect(recordedEvent['sourceKey'], 'local');
    expect(recordedEvent['comicId'], 'comic-7');
    expect(recordedEvent['chapterId'], 'ch-3');
    expect(recordedEvent['chapterIndex'], 3);
    expect(recordedEvent['page'], 9);
  });

  test('reader lifecycle also emits structured diagnostic event', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.open',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
    );

    final event = DevDiagnosticsApi.recent(channel: 'reader.lifecycle').single;
    expect(event.message, 'reader.open');
    expect(event.data['sourceKey'], 'local');
    expect(event.data['comicId'], 'comic-7');
    expect(event.data['chapterId'], 'ch-3');
    expect(event.data['page'], 9);
  });

  test('reader dispose lifecycle carries cause tab and duration metadata', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
      resultSummary:
          'cause=State.dispose owner=Reader.dispose expectedReaderTabId=tab-7 openDurationMs=2700',
      data: const {
        'disposeCause': 'State.dispose',
        'disposeOwner': 'Reader.dispose',
        'expectedReaderTabId': 'tab-7',
        'openDurationMs': 2700,
      },
    );

    final json = ReaderDiagnostics.toDiagnosticsJson();
    final recordedEvent =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    final diagnosticEvent = DevDiagnosticsApi.recent(
      channel: 'reader.lifecycle',
    ).single;

    expect(recordedEvent['event'], 'reader.dispose');
    expect(recordedEvent['resultSummary'], contains('openDurationMs=2700'));
    expect(diagnosticEvent.data['disposeCause'], 'State.dispose');
    expect(diagnosticEvent.data['disposeOwner'], 'Reader.dispose');
    expect(diagnosticEvent.data['expectedReaderTabId'], 'tab-7');
    expect(diagnosticEvent.data['openDurationMs'], 2700);
  });

  test('local reader tab remains active after page list load success', () {
    final data = buildReaderTabRetentionDiagnosticForTesting(
      expectedReaderTabId: 'local:local:1:1:__imported__',
      activeReaderTabId: 'local:local:1:1:__imported__',
      pageOrderId: '1:__imported__:source_default',
      comicId: '1',
      loadMode: 'local',
      sourceKey: 'local',
      chapterId: '1:__imported__',
      chapterIndex: 1,
      page: 1,
    );

    expect(data['retained'], isTrue);
    expect(data['status'], 'active');
    expect(data['activeReaderTabId'], data['expectedReaderTabId']);
    expect(data['pageOrderId'], '1:__imported__:source_default');
  });

  test(
    'reader emits tab retention diagnostic after local page list success',
    () {
      final data = buildReaderTabRetentionDiagnosticForTesting(
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
      );

      emitReaderTabRetentionDiagnosticForTesting(data);

      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).single;
      expect(diagnosticEvent.message, 'reader.tab.retention.afterPageList');
      expect(
        diagnosticEvent.data['activeReaderTabId'],
        'local:local:1:1:__imported__',
      );
      expect(
        diagnosticEvent.data['expectedReaderTabId'],
        'local:local:1:1:__imported__',
      );
      expect(
        diagnosticEvent.data['pageOrderId'],
        '1:__imported__:source_default',
      );
    },
  );

  test(
    'reader tab retention warning fires when active tab is missing after page list success',
    () {
      final data = buildReaderTabRetentionDiagnosticForTesting(
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: null,
        pageOrderId: null,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
      );

      emitReaderTabRetentionDiagnosticForTesting(data);

      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).single;
      expect(diagnosticEvent.message, 'reader.tab.retention.missing');
      expect(diagnosticEvent.data['status'], 'missingActiveTab');
      expect(diagnosticEvent.data['expectedReaderTabId'], isNotNull);
      expect(diagnosticEvent.data['activeReaderTabId'], isNull);
    },
  );

  test('route diagnostic snapshot omits unavailable fields safely', () {
    final data = buildReaderRouteDiagnosticSnapshotForTesting(
      routeHash: 42,
      routeName: '/reader',
    );

    expect(data['routeHash'], 42);
    expect(data['routeName'], '/reader');
    expect(data.containsKey('routeSettingsArgumentsType'), isFalse);
    expect(data.containsKey('routeDiagnosticIdentity'), isFalse);
  });

  test(
    'reader route host snapshot records navigator identity and reports observer miss when lifecycle is absent',
    () {
      emitNavigatorPushHostDiagnostic({
        'event': 'pushHost',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'routeHash': 42,
        'navigatorHash': 7,
        'nearestNavigatorHash': 7,
        'rootNavigatorHash': 1,
        'mainNavigatorHash': 2,
        'rootNavigator': false,
        'nestedNavigator': true,
        'navigatorRole': 'nested',
        'observerAttached': 'unknown',
        'previousRouteHash': 11,
        'previousRouteDiagnosticIdentity': 'ComicDetailPage',
      });

      final host = navigatorPushHostDiagnosticForRouteHash(42)!;
      final lifecycle = navigatorLifecycleDiagnosticForRouteHash(42);
      final snapshot = buildReaderRouteDiagnosticSnapshotForTesting(
        routeHash: 42,
        navigatorHash: host['navigatorHash'] as int?,
        rootNavigatorHash: host['rootNavigatorHash'] as int?,
        nearestNavigatorHash: host['nearestNavigatorHash'] as int?,
        mainNavigatorHash: host['mainNavigatorHash'] as int?,
        rootNavigator: host['rootNavigator'] as bool?,
        nestedNavigator: host['nestedNavigator'] as bool?,
        observerAttached: host['observerAttached'],
        navigatorRole: host['navigatorRole'] as String?,
        observerStatus: lifecycle == null ? 'observer_miss' : 'observer_seen',
        previousRouteHash: host['previousRouteHash'] as int?,
        previousRouteDiagnosticIdentity:
            host['previousRouteDiagnosticIdentity'] as String?,
      );

      expect(snapshot['navigatorHash'], 7);
      expect(snapshot['nearestNavigatorHash'], 7);
      expect(snapshot['rootNavigatorHash'], 1);
      expect(snapshot['mainNavigatorHash'], 2);
      expect(snapshot['rootNavigator'], isFalse);
      expect(snapshot['nestedNavigator'], isTrue);
      expect(snapshot['navigatorRole'], 'nested');
      expect(snapshot['observerAttached'], 'unknown');
      expect(snapshot['observerStatus'], 'observer_miss');
      expect(snapshot['previousRouteHash'], 11);
    },
  );

  test(
    'reader route host snapshot correlates route hash to navigator lifecycle when observer sees push',
    () {
      final route = AppPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/reader'),
      )..label = 'ReaderWithLoading';
      emitNavigatorPushHostDiagnostic({
        'event': 'pushHost',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'routeHash': route.hashCode,
        'navigatorHash': 9,
        'nearestNavigatorHash': 9,
        'rootNavigatorHash': 9,
        'mainNavigatorHash': 9,
        'rootNavigator': true,
        'nestedNavigator': false,
        'navigatorRole': 'root',
        'observerAttached': true,
        'previousRouteHash': 12,
        'previousRouteDiagnosticIdentity': 'ComicDetailPage',
      });
      emitNavigatorRouteLifecycleDiagnostic(
        buildNavigatorRouteLifecycleDiagnostic(
          event: 'didPush',
          route: route,
          previousRoute: null,
          pageCountBeforeEvent: 1,
          timestamp: DateTime.utc(2026, 1, 1),
        ),
      );

      final host = navigatorPushHostDiagnosticForRouteHash(route.hashCode)!;
      final lifecycle = navigatorLifecycleDiagnosticForRouteHash(
        route.hashCode,
      );
      final snapshot = buildReaderRouteDiagnosticSnapshotForTesting(
        routeHash: route.hashCode,
        navigatorHash: host['navigatorHash'] as int?,
        rootNavigatorHash: host['rootNavigatorHash'] as int?,
        nearestNavigatorHash: host['nearestNavigatorHash'] as int?,
        mainNavigatorHash: host['mainNavigatorHash'] as int?,
        rootNavigator: host['rootNavigator'] as bool?,
        nestedNavigator: host['nestedNavigator'] as bool?,
        observerAttached: host['observerAttached'],
        navigatorRole: host['navigatorRole'] as String?,
        observerStatus: lifecycle == null ? 'observer_miss' : 'observer_seen',
        previousRouteHash: host['previousRouteHash'] as int?,
        previousRouteDiagnosticIdentity:
            host['previousRouteDiagnosticIdentity'] as String?,
        navigatorLifecycleEvent: lifecycle?['event'] as String?,
      );

      expect(snapshot['observerStatus'], 'observer_seen');
      expect(snapshot['navigatorHash'], 9);
      expect(snapshot['nearestNavigatorHash'], 9);
      expect(snapshot['rootNavigatorHash'], 9);
      expect(snapshot['mainNavigatorHash'], 9);
      expect(snapshot['rootNavigator'], isTrue);
      expect(snapshot['nestedNavigator'], isFalse);
      expect(snapshot['navigatorRole'], 'root');
      expect(snapshot['navigatorLifecycleEvent'], 'didPush');
    },
  );

  test(
    'navigator ownership diagnostic handles missing route index without throwing',
    () {
      expect(
        () => buildReaderParentShellDiagnosticForTesting(
          owner: 'ReaderWithLoading.buildFrame',
          branch: 'content',
          readerChildMounted: true,
          comicId: 'comic-1',
          loadMode: 'remote',
          sourceKey: 'nhentai',
          chapterId: safeElementAtOrNullForDiagnostics(const ['ch-1'], -1),
          chapterIndex: null,
          page: 1,
          selectedIndex: -1,
          currentPage: 1,
          routeName: '/reader',
          expectedReaderTabId: 'tab-1',
          activeReaderTabId: 'tab-1',
          pageOrderId: 'order-1',
        ),
        returnsNormally,
      );
      final data = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.buildFrame',
        branch: 'content',
        readerChildMounted: true,
        comicId: 'comic-1',
        loadMode: 'remote',
        sourceKey: 'nhentai',
        chapterId: safeElementAtOrNullForDiagnostics(const ['ch-1'], -1),
        chapterIndex: null,
        page: 1,
        selectedIndex: -1,
        currentPage: 1,
        routeName: '/reader',
        expectedReaderTabId: 'tab-1',
        activeReaderTabId: 'tab-1',
        pageOrderId: 'order-1',
      );

      expect(data['chapterId'], isNull);
      expect(data['chapterIndex'], isNull);
    },
  );

  test(
    'navigator ownership diagnostic does not call elementAtOrNull with negative index',
    () {
      expect(
        safeElementAtOrNullForDiagnostics(const ['ch-1', 'ch-2'], -1),
        isNull,
      );
      expect(
        safeElementAtOrNullForDiagnostics(const ['ch-1', 'ch-2'], 0),
        'ch-1',
      );
    },
  );

  test(
    'shell keeps reader child mounted when active tab id matches expected local reader tab',
    () {
      final data = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.buildFrame',
        branch: 'content',
        readerChildMounted: true,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: null,
        routeSnapshot: const {'routeHash': 101},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
      );

      expect(data['readerChildMounted'], isTrue);
      expect(data['retainedTab'], isTrue);
      expect(data['branch'], 'content');
    },
  );

  test(
    'reader parent unmount diagnostic includes entrypoint route and request identity',
    () {
      final data = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.parentUnmount',
        branch: 'content',
        readerChildMounted: false,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: '/reader',
        routeSnapshot: const {
          'routeHash': 42,
          'routeSettingsName': '/reader',
          'routeSettingsArgumentsType': 'ReaderRouteArgs',
        },
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        requestEntrypoint: 'local_favorites.item',
        requestCaller: '_LocalFavoritesPageState._openFavoriteComic',
        requestSourceRefId: 'local:local:1:1:__imported__',
        parentStateHash: 777,
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
        reason: 'parentState.dispose',
        openDurationMs: 88,
      );

      expect(data['requestEntrypoint'], 'local_favorites.item');
      expect(data['requestSourceRefId'], 'local:local:1:1:__imported__');
      expect(data['routeHash'], 42);
      expect(data['routeSettingsName'], '/reader');
      expect(data['routeSettingsArgumentsType'], 'ReaderRouteArgs');
      expect(data['parentStateHash'], 777);
      expect(data['disposeReason'], 'parentState.dispose');
    },
  );

  test(
    'reader short dispose with retained tab emits parent unmount diagnostic',
    () {
      // Regression note:
      // A duplicate Hero tag in the route subtree can throw from HeroController
      // during route transition and then cascade into a reader short-dispose /
      // black-screen symptom. When retained-tab diagnostics look correct, do not
      // assume the root cause is in the reader pipeline before ruling out Hero
      // collisions on the parent route tree.
      final data = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.parentUnmount',
        branch: 'loading',
        readerChildMounted: false,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: null,
        routeSnapshot: const {'routeHash': 101},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
        reason: 'branch_switched_loading',
        openDurationMs: 1885,
      );

      emitReaderParentUnmountDiagnosticForTesting(data);

      final diagnosticEvent =
          DevDiagnosticsApi.recent(channel: 'reader.lifecycle').lastWhere(
            (event) => event.message == 'reader.parent.unmount.retainedTab',
          );
      expect(diagnosticEvent.message, 'reader.parent.unmount.retainedTab');
      expect(
        diagnosticEvent.data['activeReaderTabId'],
        data['activeReaderTabId'],
      );
      expect(
        diagnosticEvent.data['expectedReaderTabId'],
        data['expectedReaderTabId'],
      );
      expect(diagnosticEvent.data['reason'], 'branch_switched_loading');
    },
  );

  test(
    'reader parent unmount diagnostic is suppressed for expected didPop teardown',
    () {
      emitReaderParentUnmountDiagnosticForTesting(
        buildReaderParentShellDiagnosticForTesting(
          owner: 'ReaderWithLoading.parentUnmount',
          branch: 'content',
          readerChildMounted: false,
          comicId: '1',
          loadMode: 'local',
          sourceKey: 'local',
          chapterId: '1:__imported__',
          chapterIndex: 1,
          page: 1,
          selectedIndex: 1,
          currentPage: 1,
          routeName: '/reader',
          routeSnapshot: const {
            'routeHash': 101,
            'routeLifecycleEvent': 'didPop',
          },
          expectedReaderTabId: 'local:local:1:1:__imported__',
          activeReaderTabId: 'local:local:1:1:__imported__',
          pageOrderId: '1:__imported__:source_default',
          reason: 'parentState.dispose',
          openDurationMs: 880,
        ),
      );

      final messages = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).map((event) => event.message);
      expect(messages, isNot(contains('reader.parent.unmount.retainedTab')));
    },
  );

  test('short lived reader dispose warning is suppressed for didRemove', () {
    expect(shouldWarnOnShortLivedReaderDisposeForTesting('didRemove'), isFalse);
    expect(shouldWarnOnShortLivedReaderDisposeForTesting('didPop'), isFalse);
    expect(
      shouldWarnOnShortLivedReaderDisposeForTesting('didReplace'),
      isFalse,
    );
    expect(shouldWarnOnShortLivedReaderDisposeForTesting('didPush'), isTrue);
    expect(shouldWarnOnShortLivedReaderDisposeForTesting(null), isTrue);
  });

  test(
    'short lived reader dispose diagnostic is suppressed for expected didRemove teardown',
    () {
      emitReaderShortLivedDisposeDiagnosticForTesting({
        'routeLifecycleEvent': 'didRemove',
        'disposeCause': 'State.dispose',
        'disposeOwner': 'Reader.dispose',
        'comicId': '1',
      });

      final messages = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).map((event) => event.message);
      expect(messages, isNot(contains('reader.dispose.short_lived')));
    },
  );

  test(
    'short lived reader dispose diagnostic still emits for unexpected teardown',
    () {
      emitReaderShortLivedDisposeDiagnosticForTesting({
        'routeLifecycleEvent': 'didPush',
        'disposeCause': 'State.dispose',
        'disposeOwner': 'Reader.dispose',
        'comicId': '1',
        'openDurationMs': 800,
      });

      final event = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).lastWhere((event) => event.message == 'reader.dispose.short_lived');
      expect(event.data['routeLifecycleEvent'], 'didPush');
      expect(event.data['disposeOwner'], 'Reader.dispose');
    },
  );

  test(
    'shell build diagnostic includes active tab id expected tab id and page order id',
    () {
      final data = buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.buildFrame',
        branch: 'content',
        readerChildMounted: true,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: null,
        routeSnapshot: const {'routeHash': 101},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
      );

      emitReaderParentShellBuildDiagnosticForTesting(data);

      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).lastWhere((event) => event.message == 'reader.parent.shell.build');
      expect(diagnosticEvent.message, 'reader.parent.shell.build');
      expect(
        diagnosticEvent.data['activeReaderTabId'],
        'local:local:1:1:__imported__',
      );
      expect(
        diagnosticEvent.data['expectedReaderTabId'],
        'local:local:1:1:__imported__',
      );
      expect(
        diagnosticEvent.data['pageOrderId'],
        '1:__imported__:source_default',
      );
    },
  );

  test('parent diagnostics are included in reader trace snapshot', () {
    readerTraceRecorder.clear();

    emitReaderParentShellBuildDiagnosticForTesting(
      buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.buildFrame',
        branch: 'content',
        readerChildMounted: true,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: null,
        routeSnapshot: const {'routeHash': 101},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
      ),
    );
    emitReaderParentUnmountDiagnosticForTesting(
      buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.parentUnmount',
        branch: 'loading',
        readerChildMounted: false,
        comicId: '1',
        loadMode: 'local',
        sourceKey: 'local',
        chapterId: '1:__imported__',
        chapterIndex: 1,
        page: 1,
        selectedIndex: 1,
        currentPage: 1,
        routeName: null,
        routeSnapshot: const {'routeHash': 101},
        expectedReaderTabId: 'local:local:1:1:__imported__',
        activeReaderTabId: 'local:local:1:1:__imported__',
        pageOrderId: '1:__imported__:source_default',
        parentKey: 'parent-key',
        readerChildKey: 'reader:1:local:local:1:1:__imported__',
        reason: 'branch_switched_loading',
        openDurationMs: 1885,
      ),
    );

    final events =
        (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                as Map<String, dynamic>)['events']
            as List<dynamic>;
    final messages = events
        .map((event) => (event as Map<String, dynamic>)['event'])
        .toList();

    expect(messages, contains('reader.parent.shell.build'));
    expect(messages, contains('reader.parent.unmount.retainedTab'));
  });

  test('dispose diagnostics can skip layout dependent pagination reads', () {
    final snapshot = buildReaderPaginationDiagnosticsForTesting(
      includePagination: false,
      imageCount: 3,
      maxPage: () => throw StateError('maxPage should not be read'),
      imagesPerPage: () => throw StateError('imagesPerPage should not be read'),
    );

    expect(snapshot.maxPage, isNull);
    expect(snapshot.imagesPerPage, isNull);
  });

  test('pagination diagnostics degrade when layout reads fail', () {
    final snapshot = buildReaderPaginationDiagnosticsForTesting(
      includePagination: true,
      imageCount: 3,
      maxPage: () => throw StateError('layout unavailable'),
      imagesPerPage: () => throw StateError('layout unavailable'),
    );

    expect(snapshot.imageCount, 3);
    expect(snapshot.maxPage, isNull);
    expect(snapshot.imagesPerPage, isNull);
    final diagnosticEvent = DevDiagnosticsApi.recent(
      channel: 'reader.lifecycle',
    ).single;
    expect(diagnosticEvent.message, 'pagination.diagnostics.unavailable');
    expect(diagnosticEvent.data['reason'], 'pagination_snapshot_unavailable');
    expect(diagnosticEvent.data.containsKey('stackTrace'), isFalse);
  });

  test(
    'dispose diagnostics use context unavailable reason without stack spam',
    () {
      buildReaderPaginationDiagnosticsForTesting(
        includePagination: true,
        imageCount: 3,
        maxPage: () => throw StateError('layout unavailable during dispose'),
        imagesPerPage: () =>
            throw StateError('layout unavailable during dispose'),
        unavailableReason: 'context_unavailable_during_dispose',
      );

      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).single;
      expect(diagnosticEvent.message, 'pagination.diagnostics.unavailable');
      expect(
        diagnosticEvent.data['reason'],
        'context_unavailable_during_dispose',
      );
      expect(diagnosticEvent.data.containsKey('stackTrace'), isFalse);
    },
  );

  test(
    'reader image load calls keep source comic chapter and page context',
    () {
      readerTraceRecorder.clear();
      final callId = ReaderDiagnostics.beginImageLoad(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
      );
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
        byteLength: 1234,
      );

      final json = ReaderDiagnostics.toDiagnosticsJson();
      final events =
          (json['readerTrace'] as Map<String, dynamic>)['events']
              as List<dynamic>;
      final start = events.first as Map<String, dynamic>;
      final end = events.last as Map<String, dynamic>;

      expect(start['functionName'], 'ReaderImageProvider.load');
      expect(start['phase'], 'imageProvider');
      expect(start['sourceKey'], 'local');
      expect(start['comicId'], 'comic-7');
      expect(start['chapterId'], 'ch-3');
      expect(start['page'], 4);
      expect(end['resultSummary'], 'bytes=1234');
    },
  );

  test(
    'provider pending clears after load/decode path and does not emit notSubscribed',
    () {
      readerTraceRecorder.clear();
      ReaderDiagnostics.clearPendingProviderSubscriptionsForTesting();
      ReaderDiagnostics.markImageProviderAwaitingSubscription(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
      );

      final callId = ReaderDiagnostics.beginImageLoad(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
      );
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
        byteLength: 1234,
      );
      ReaderDiagnostics.recordImageDecodeSuccess(
        imageKey: 'file:///tmp/page-4.jpg',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        byteLength: 1234,
      );

      final emitted = ReaderDiagnostics.recordProviderNotSubscribedIfPending(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
        owner: 'reader.render.postFrame',
      );
      expect(emitted, isFalse);

      final warningEvents = DevDiagnosticsApi.recent(channel: 'reader.render');
      expect(
        warningEvents.where(
          (event) => event.message == 'reader.render.provider.notSubscribed',
        ),
        isEmpty,
      );
    },
  );

  test('provider never listened still emits notSubscribed warning', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.clearPendingProviderSubscriptionsForTesting();
    ReaderDiagnostics.markImageProviderAwaitingSubscription(
      loadMode: 'local',
      sourceKey: 'local',
      comicId: 'comic-8',
      chapterId: 'ch-4',
      page: 1,
      imageKey: 'file:///tmp/page-1.jpg',
    );

    final emitted = ReaderDiagnostics.recordProviderNotSubscribedIfPending(
      loadMode: 'local',
      sourceKey: 'local',
      comicId: 'comic-8',
      chapterId: 'ch-4',
      page: 1,
      imageKey: 'file:///tmp/page-1.jpg',
      owner: 'reader.render.postFrame',
    );
    expect(emitted, isTrue);

    final warning = DevDiagnosticsApi.recent(channel: 'reader.render').single;
    expect(warning.message, 'reader.render.provider.notSubscribed');
    expect(warning.data['code'], 'PROVIDER_NOT_SUBSCRIBED');
  });

  test(
    'provider recreated for same imageKey after prior success does not emit notSubscribed',
    () {
      readerTraceRecorder.clear();
      ReaderDiagnostics.clearPendingProviderSubscriptionsForTesting();

      ReaderDiagnostics.markImageProviderAwaitingSubscription(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        imageKey: 'file:///tmp/page-rebuild.jpg',
        providerTrackingKey: 'provider-A',
      );
      final callId = ReaderDiagnostics.beginImageLoad(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        imageKey: 'file:///tmp/page-rebuild.jpg',
        providerTrackingKey: 'provider-A',
      );
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        imageKey: 'file:///tmp/page-rebuild.jpg',
        byteLength: 256,
      );
      ReaderDiagnostics.recordImageDecodeSuccess(
        imageKey: 'file:///tmp/page-rebuild.jpg',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        byteLength: 256,
      );

      ReaderDiagnostics.markImageProviderAwaitingSubscription(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        imageKey: 'file:///tmp/page-rebuild.jpg',
        providerTrackingKey: 'provider-B',
      );

      final emitted = ReaderDiagnostics.recordProviderNotSubscribedIfPending(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-9',
        chapterId: 'ch-6',
        page: 1,
        imageKey: 'file:///tmp/page-rebuild.jpg',
        owner: 'reader.render.postFrame',
        providerTrackingKey: 'provider-B',
      );
      expect(emitted, isFalse);

      final warningEvents = DevDiagnosticsApi.recent(channel: 'reader.render');
      expect(
        warningEvents.where(
          (event) => event.message == 'reader.render.provider.notSubscribed',
        ),
        isEmpty,
      );
    },
  );

  test(
    'reader image decode errors keep source comic chapter and page context',
    () {
      readerTraceRecorder.clear();
      ReaderDiagnostics.recordImageLoadError(
        error: 'decode failed',
        imageKey: 'https://example.com/page-4.jpg',
        sourceKey: 'copymanga',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
      );

      final json = ReaderDiagnostics.toDiagnosticsJson();
      final recordedEvent =
          (json['readerTrace'] as Map<String, dynamic>)['events'][0]
              as Map<String, dynamic>;
      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.decode',
      ).single;

      expect(recordedEvent['sourceKey'], 'copymanga');
      expect(recordedEvent['comicId'], 'comic-7');
      expect(recordedEvent['chapterId'], 'ch-3');
      expect(recordedEvent['page'], 4);
      expect(recordedEvent['imageKey'], 'https://example.com/page-4.jpg');
      expect(diagnosticEvent.data['sourceKey'], 'copymanga');
      expect(diagnosticEvent.data['comicId'], 'comic-7');
      expect(diagnosticEvent.data['chapterId'], 'ch-3');
      expect(diagnosticEvent.data['page'], 4);
    },
  );

  test('reader decode success/error and frame events are distinguishable', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordImageDecodeSuccess(
      imageKey: 'https://example.com/page-5.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 5,
      byteLength: 2048,
    );
    ReaderDiagnostics.recordImageDecodeError(
      imageKey: 'https://example.com/page-6.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 6,
      error: 'bad codec',
    );
    ReaderDiagnostics.recordImageFrameRendered(
      imageKey: 'https://example.com/page-5.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 5,
      frameNumber: 0,
      synchronousCall: false,
      widgetType: 'ComicImage',
    );

    final events =
        (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                as Map<String, dynamic>)['events']
            as List<dynamic>;
    expect(events[0]['event'], 'image.decode.success');
    expect(events[1]['event'], 'image.decode.error');
    expect(events[2]['event'], 'image.frame.rendered');
    expect(events[0]['phase'], 'decode');
    expect(events[1]['phase'], 'decode');
    expect(events[2]['phase'], 'decode');

    final decodeEvents = DevDiagnosticsApi.recent(channel: 'reader.decode');
    expect(decodeEvents.map((e) => e.message), [
      'image.decode.success',
      'bad codec',
      'image.frame.rendered',
    ]);
  });

  test('canonical session events serialize as structured diagnostics', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordCanonicalSessionEvent(
      event: 'reader.session.upsert.success',
      loadMode: 'local',
      sourceKey: 'local',
      comicId: 'comic-9',
      chapterId: '0',
      chapterIndex: 1,
      page: 6,
      sessionId: 'reader-session:comic-9',
      tabId: 'local:local:comic-9:_',
    );

    final traceEvent =
        (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    final structured = DevDiagnosticsApi.recent(
      channel: 'reader.session',
    ).single;

    expect(traceEvent['event'], 'reader.session.upsert.success');
    expect(traceEvent['sourceKey'], 'local');
    expect(traceEvent['chapterId'], '0');
    expect(traceEvent['resultSummary'], contains('sessionId='));
    expect(structured.data['sessionId'], isNotNull);
    expect(structured.data['tabId'], isNotNull);
  });

  test(
    'normalized reader context stays stable across page list image provider and dispose',
    () {
      readerTraceRecorder.clear();
      final context = buildReaderRuntimeContextForTesting(
        comicId: 'comic-10',
        type: ComicType.local,
        chapterIndex: 1,
        page: 3,
        chapterId: null,
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-10',
          chapterId: null,
        ),
      );

      ReaderDiagnostics.beginPageListLoad(
        loadMode: context.loadMode,
        sourceKey: context.sourceKey,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
      );
      ReaderDiagnostics.recordImageProviderCreated(
        type: ComicType.local,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
        imageKey: 'file:///tmp/page-3.jpg',
      );
      ReaderDiagnostics.recordReaderLifecycle(
        event: 'reader.dispose',
        type: ComicType.local,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
        sourceKey: context.sourceKey,
        loadMode: context.loadMode,
      );

      final events =
          (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                  as Map<String, dynamic>)['events']
              as List<dynamic>;

      expect(
        events.every(
          (event) => (event as Map<String, dynamic>)['sourceKey'] == 'local',
        ),
        isTrue,
      );
      expect(
        events.every(
          (event) => (event as Map<String, dynamic>)['chapterId'] == '0',
        ),
        isTrue,
      );
      expect(normalizeReaderChapterIdForTesting(null), '0');
    },
  );
}
