import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

typedef ReaderLegacyRouteOpener =
    Future<void> Function(ReaderOpenRequest request);
typedef ReaderNextExecutorResolver =
    ReaderNextApprovedExecutor? Function({
      ReaderNextApprovedExecutor? injectedExecutor,
      ReaderNextApprovedExecutorFactory? injectedFactory,
      ReaderNextApprovedExecutorFactory approvedFactory,
    });
typedef ReaderNextExecutorDispatcher =
    Future<void> Function({
      required ReaderNextOpenRequest request,
      required ReaderNextApprovedExecutor executor,
    });

class ReaderRouteDispatchAuthority {
  const ReaderRouteDispatchAuthority({
    ReaderLegacyRouteOpener? openLegacyRoute,
    ReaderNextExecutorResolver? resolveApprovedReaderNextExecutor,
    ReaderNextExecutorDispatcher? dispatchApprovedReaderNextExecutor,
  }) : _openLegacyRoute = openLegacyRoute ?? _defaultOpenLegacyRoute,
       _resolveApprovedReaderNextExecutor =
           resolveApprovedReaderNextExecutor ??
           _defaultResolveApprovedReaderNextExecutor,
       _dispatchApprovedReaderNextExecutor =
           dispatchApprovedReaderNextExecutor ??
           _defaultDispatchApprovedReaderNextExecutor;

  final ReaderLegacyRouteOpener _openLegacyRoute;
  final ReaderNextExecutorResolver _resolveApprovedReaderNextExecutor;
  final ReaderNextExecutorDispatcher _dispatchApprovedReaderNextExecutor;

  Future<void> openLegacy(ReaderOpenRequest request) async {
    _emitLegacyDispatchDiagnostic(request);
    await _openLegacyRoute(request);
  }

  Future<void> openApprovedReaderNext({
    required ReaderNextOpenRequest request,
    ReaderNextApprovedExecutor? injectedExecutor,
    ReaderNextApprovedExecutorFactory? injectedFactory,
    ReaderNextApprovedExecutorFactory approvedFactory =
        createApprovedReaderNextNavigationExecutor,
  }) async {
    final executor = _resolveApprovedReaderNextExecutor(
      injectedExecutor: injectedExecutor,
      injectedFactory: injectedFactory,
      approvedFactory: approvedFactory,
    );
    if (executor == null) {
      throw ReaderNextBoundaryException(
        'READER_NEXT_EXECUTOR_MISSING',
        'Approved ReaderNext executor is required for centralized route dispatch',
      );
    }
    _emitReaderNextDispatchDiagnostic(request);
    await _dispatchApprovedReaderNextExecutor(
      request: request,
      executor: executor,
    );
  }

  static Future<void> _defaultOpenLegacyRoute(ReaderOpenRequest request) async {
    await App.rootContext.to(
      () => ReaderWithLoading.fromRequest(request: request),
    );
  }

  static ReaderNextApprovedExecutor _defaultResolveApprovedReaderNextExecutor({
    ReaderNextApprovedExecutor? injectedExecutor,
    ReaderNextApprovedExecutorFactory? injectedFactory,
    ReaderNextApprovedExecutorFactory approvedFactory =
        createApprovedReaderNextNavigationExecutor,
  }) {
    return resolveApprovedReaderNextExecutor(
      injectedExecutor: injectedExecutor,
      injectedFactory: injectedFactory,
      approvedFactory: approvedFactory,
    );
  }

  static Future<void> _defaultDispatchApprovedReaderNextExecutor({
    required ReaderNextOpenRequest request,
    required ReaderNextApprovedExecutor executor,
  }) {
    return dispatchApprovedReaderNextExecutor(
      request: request,
      executor: executor,
    );
  }

  static void _emitLegacyDispatchDiagnostic(ReaderOpenRequest request) {
    AppDiagnostics.info(
      'reader.route',
      'reader.route.dispatch',
      data: <String, Object?>{
        'target': 'legacy',
        'navigatorTarget': 'root',
        'routeFactory': 'ReaderWithLoading.fromRequest',
        'entrypoint': request.diagnosticEntrypoint ?? '<unknown>',
        'caller': request.diagnosticCaller ?? '<unknown>',
        'comicId': _redact(request.comicId),
        'sourceKey': request.sourceKey ?? '<unknown>',
        'sourceRefId': _redact(request.sourceRefId ?? ''),
      },
    );
  }

  static void _emitReaderNextDispatchDiagnostic(ReaderNextOpenRequest request) {
    AppDiagnostics.info(
      'reader.route',
      'reader.route.dispatch',
      data: <String, Object?>{
        'target': 'reader_next',
        'navigatorTarget': 'approved_executor',
        'routeFactory': 'ApprovedReaderNextNavigationExecutor',
        'canonicalComicId': _redact(request.canonicalComicId.value),
        'sourceKey': request.sourceRef.sourceKey,
        'upstreamComicRefId': _redact(request.sourceRef.upstreamComicRefId),
        'chapterRefId': _redact(request.sourceRef.chapterRefId ?? ''),
      },
    );
  }

  static String _redact(String raw) {
    if (raw.isEmpty) {
      return '<empty>';
    }
    if (raw.length <= 4) {
      return '<redacted>';
    }
    return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
  }
}
