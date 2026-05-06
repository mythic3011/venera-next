import 'package:flutter/material.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/app/app_page_route.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

class AppRouter {
  const AppRouter._();

  static Future<bool> openReader(
    BuildContext context,
    ReaderOpenRequest request,
  ) async {
    final requestedContextMounted = context.mounted;
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
          'requestContextMounted': requestedContextMounted,
          'entrypoint': request.diagnosticEntrypoint ?? '<unknown>',
          'caller': request.diagnosticCaller ?? '<unknown>',
        },
      );
      return false;
    }

    final route = AppPageRoute<void>(
      builder: (routeContext) => ReaderWithLoading.fromRequest(
        request: request,
      ),
    );
    await navigator.push<void>(route);
    AppDiagnostics.info(
      'reader.route',
      'open_success',
      data: <String, Object?>{
        'target': 'legacy',
        'selectedNavigatorRole': 'main',
        'observerExpected': true,
        'selectedNavigatorSource': 'App.mainNavigatorKey.currentState',
        'requestedRootNavigator': false,
        'requestContextMounted': requestedContextMounted,
        'entrypoint': request.diagnosticEntrypoint ?? '<unknown>',
        'caller': request.diagnosticCaller ?? '<unknown>',
      },
    );
    return true;
  }
}
