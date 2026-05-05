import 'package:venera/app/router.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:flutter/widgets.dart';

typedef ReaderLegacyRouteOpener =
    Future<bool> Function(ReaderOpenRequest request, BuildContext? context);
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

  Future<bool> openLegacy(
    ReaderLegacyDispatchRequest request, {
    BuildContext? context,
  }) async {
    if (request.sourceRef case final sourceRef?
        when isUnresolvedLocalReaderTarget(sourceRef)) {
      emitUnresolvedLocalReaderTargetDiagnostic(
        comicId: request.comicId,
        sourceRef: sourceRef,
        diagnosticEntrypoint: request.diagnosticEntrypoint,
        diagnosticCaller: request.diagnosticCaller,
      );
      return false;
    }
    final normalizedRequest = switch (request) {
      ReaderOpenRequest request => request,
      ReaderRouteRequest request => request.toReaderOpenRequest(),
      _ => throw ArgumentError(
        'Unsupported legacy reader dispatch request: ${request.runtimeType}',
      ),
    };
    _emitLegacyDispatchDiagnostic(normalizedRequest);
    return _openLegacyRoute(normalizedRequest, context);
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

  static Future<bool> _defaultOpenLegacyRoute(
    ReaderOpenRequest request,
    BuildContext? context,
  ) {
    final navigator = App.mainNavigatorKey?.currentState;
    if (navigator == null) {
      AppDiagnostics.info(
        'reader.route',
        'open_blocked',
        data: <String, Object?>{
          'target': 'legacy',
          'selectedNavigatorRole': 'main',
          'observerExpected': true,
          'selectedNavigatorSource': 'App.mainNavigatorKey.currentState',
          'requestedRootNavigator': false,
          'entrypoint': request.diagnosticEntrypoint ?? '<unknown>',
          'caller': request.diagnosticCaller ?? '<unknown>',
        },
      );
      return Future<bool>.value(false);
    }
    return AppRouter.openReader(context ?? navigator.context, request);
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
        'navigatorTarget': 'main',
        'routeFactory': 'AppRouter.openReader',
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
