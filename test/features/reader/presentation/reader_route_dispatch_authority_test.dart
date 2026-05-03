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
        openLegacyRoute: (request) async {
          openedRequest = request;
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
      expect(events.single.data['navigatorTarget'], 'root');
    },
  );

  test(
    'approved ReaderNext dispatch uses injected executor through one centralized executor path',
    () async {
      ReaderNextOpenRequest? dispatchedRequest;
      ReaderNextApprovedExecutor? dispatchedExecutor;
      final injectedExecutor = (ReaderNextOpenRequest request) async {};
      final ReaderNextExecutorDispatcher dispatcher =
          ({
            required ReaderNextOpenRequest request,
            required ReaderNextApprovedExecutor executor,
          }) async {
            dispatchedRequest = request;
            dispatchedExecutor = executor;
          };
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
      final approvedExecutor = (ReaderNextOpenRequest request) async {};
      final ReaderNextExecutorDispatcher dispatcher =
          ({
            required ReaderNextOpenRequest request,
            required ReaderNextApprovedExecutor executor,
          }) async {
            dispatchedRequest = request;
            dispatchedExecutor = executor;
          };
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
