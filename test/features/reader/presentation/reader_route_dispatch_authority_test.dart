import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/features/reader/presentation/reader_route_dispatch_authority.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  setUp(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'legacy dispatch uses one centralized opener and emits diagnostics',
    () async {
      ReaderOpenRequest? openedRequest;
      final authority = ReaderRouteDispatchAuthority(
        openLegacyRoute: (request, context) async {
          openedRequest = request;
          return true;
        },
      );
      final request = ReaderOpenRequest(
        comicId: '646922',
        sourceKey: 'nhentai',
        initialEp: 2,
        initialPage: 3,
        diagnosticEntrypoint: 'test.entry',
        diagnosticCaller: 'reader_route_dispatch_authority_test',
      );

      await authority.openLegacy(request);

      expect(openedRequest, same(request));
      final events = AppDiagnostics.recent(channel: 'reader.route');
      expect(events, hasLength(1));
      expect(events.single.message, 'reader.route.dispatch');
      expect(events.single.data['target'], 'legacy');
      expect(events.single.data['entrypoint'], 'test.entry');
      expect(events.single.data['navigatorTarget'], 'main');
      expect(events.single.data['routeFactory'], 'AppRouter.openReader');
    },
  );

  test('legacy dispatch returns opener status', () async {
    final authority = ReaderRouteDispatchAuthority(
      openLegacyRoute: (request, context) async => false,
    );
    final request = ReaderOpenRequest(
      comicId: '646922',
      sourceKey: 'nhentai',
      initialEp: 2,
      initialPage: 3,
    );

    final opened = await authority.openLegacy(request);
    expect(opened, isFalse);
  });

  test('legacy dispatch fail-closed when main navigator is unavailable', () async {
    final authority = const ReaderRouteDispatchAuthority();
    final request = ReaderOpenRequest(
      comicId: '646922',
      sourceKey: 'nhentai',
      initialEp: 2,
      initialPage: 3,
      diagnosticEntrypoint: 'test.blocked',
      diagnosticCaller: 'reader_route_dispatch_authority_test',
    );

    final opened = await authority.openLegacy(request);
    expect(opened, isFalse);
    final events = AppDiagnostics.recent(channel: 'reader.route');
    expect(events.map((event) => event.message), contains('open_blocked'));
    final blockedEvent = events.firstWhere(
      (event) => event.message == 'open_blocked',
    );
    expect(blockedEvent.data['selectedNavigatorRole'], 'main');
    expect(blockedEvent.data['observerExpected'], true);
    expect(
      blockedEvent.data['selectedNavigatorSource'],
      'App.mainNavigatorKey.currentState',
    );
    expect(blockedEvent.data['requestedRootNavigator'], false);
  });

  test('reader route opens are centralized through router/dispatch authority', () {
    final repoRoot = Directory.current.path;
    final allowedFiles = <String>{
      'lib/features/reader/presentation/loading.dart',
      'lib/app/router.dart',
    };
    final matches = <String>[];
    for (final entity in Directory('$repoRoot/lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()) {
      final relative = entity.path.replaceFirst('$repoRoot/', '');
      if (!relative.endsWith('.dart')) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (content.contains('ReaderWithLoading.fromRequest(')) {
        matches.add(relative);
      }
    }
    expect(matches.toSet(), equals(allowedFiles));
    expect(
      matches,
      everyElement(isNot(contains('reader_route_dispatch_authority.dart'))),
    );
    expect(
      matches,
      everyElement(isNot(contains('local/local_comic.dart'))),
    );
  });

  test(
    'approved ReaderNext dispatch uses injected executor through one centralized executor path',
    () async {
      ReaderNextOpenRequest? dispatchedRequest;
      ReaderNextApprovedExecutor? dispatchedExecutor;
      Future<void> injectedExecutor(ReaderNextOpenRequest request) async {}
      Future<void> dispatcher({
        required ReaderNextOpenRequest request,
        required ReaderNextApprovedExecutor executor,
      }) async {
        dispatchedRequest = request;
        dispatchedExecutor = executor;
      }
      final authority = ReaderRouteDispatchAuthority(
        dispatchApprovedReaderNextExecutor: dispatcher,
      );
      final request = ReaderNextOpenRequest.remote(
        canonicalComicId: CanonicalComicId.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
        ),
        sourceRef: SourceRef.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '1',
        ),
        initialPage: 1,
      );

      await authority.openApprovedReaderNext(
        request: request,
        injectedExecutor: injectedExecutor,
      );

      expect(dispatchedRequest, same(request));
      expect(dispatchedExecutor, same(injectedExecutor));
      final events = AppDiagnostics.recent(channel: 'reader.route');
      expect(events, hasLength(1));
      expect(events.single.data['target'], 'reader_next');
      expect(events.single.data['navigatorTarget'], 'approved_executor');
    },
  );

  test(
    'approved ReaderNext dispatch falls back to approved factory when no injected executor is provided',
    () async {
      ReaderNextOpenRequest? dispatchedRequest;
      ReaderNextApprovedExecutor? dispatchedExecutor;
      var approvedFactoryCalls = 0;
      Future<void> approvedExecutor(ReaderNextOpenRequest request) async {}
      Future<void> dispatcher({
        required ReaderNextOpenRequest request,
        required ReaderNextApprovedExecutor executor,
      }) async {
        dispatchedRequest = request;
        dispatchedExecutor = executor;
      }
      final authority = ReaderRouteDispatchAuthority(
        dispatchApprovedReaderNextExecutor: dispatcher,
      );
      final request = ReaderNextOpenRequest.remote(
        canonicalComicId: CanonicalComicId.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
        ),
        sourceRef: SourceRef.remote(
          sourceKey: 'nhentai',
          upstreamComicRefId: '646922',
          chapterRefId: '1',
        ),
        initialPage: 1,
      );

      await authority.openApprovedReaderNext(
        request: request,
        approvedFactory: () {
          approvedFactoryCalls += 1;
          return approvedExecutor;
        },
      );
      expect(approvedFactoryCalls, 1);
      expect(dispatchedRequest, same(request));
      expect(dispatchedExecutor, same(approvedExecutor));
      final events = AppDiagnostics.recent(channel: 'reader.route');
      expect(events, hasLength(1));
      expect(events.single.data['target'], 'reader_next');
    },
  );
}
