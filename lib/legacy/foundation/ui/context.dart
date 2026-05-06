import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';

import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/app/app_page_route.dart';

extension Navigation on BuildContext {
  void pop<T>([T? result]) {
    if (mounted) {
      Navigator.of(this).pop(result);
    }
  }

  bool canPop() {
    return Navigator.of(this).canPop();
  }

  Future<T?> to<T>(Widget Function() builder) {
    final navigator = Navigator.of(this);
    final currentRoute = ModalRoute.of(this);
    final rootNavigator = App.rootNavigatorKey.currentState;
    final mainNavigator = App.mainNavigatorKey?.currentState;
    final isRootNavigator = identical(navigator, rootNavigator);
    final isMainNavigator = identical(navigator, mainNavigator);
    final isNestedNavigator = !isRootNavigator && !isMainNavigator;
    final navigatorRole = isRootNavigator
        ? 'root'
        : (isNestedNavigator ? 'nested' : 'nearest');
    final observerAttached = isMainNavigator
        ? true
        : (isRootNavigator ? false : 'unknown');
    final route = AppPageRoute<T>(builder: (context) => builder());
    emitNavigatorPushHostDiagnostic(
      buildNavigatorPushHostDiagnostic(
        route: route,
        navigator: navigator,
        currentRoute: currentRoute,
        nearestNavigatorHash: navigator.hashCode,
        rootNavigatorHash: rootNavigator?.hashCode,
        mainNavigatorHash: mainNavigator?.hashCode,
        rootNavigator: isRootNavigator,
        observerAttached: observerAttached,
        nestedNavigator: isNestedNavigator,
        navigatorRole: navigatorRole,
      ),
    );
    return navigator.push<T>(route);
  }

  Future<void> toReplacement<T>(Widget Function() builder) {
    final navigator = Navigator.of(this);
    final currentRoute = ModalRoute.of(this);
    final rootNavigator = App.rootNavigatorKey.currentState;
    final mainNavigator = App.mainNavigatorKey?.currentState;
    final isRootNavigator = identical(navigator, rootNavigator);
    final isMainNavigator = identical(navigator, mainNavigator);
    final isNestedNavigator = !isRootNavigator && !isMainNavigator;
    final navigatorRole = isRootNavigator
        ? 'root'
        : (isNestedNavigator ? 'nested' : 'nearest');
    final observerAttached = isMainNavigator
        ? true
        : (isRootNavigator ? false : 'unknown');
    final route = AppPageRoute(builder: (context) => builder());
    emitNavigatorPushHostDiagnostic(
      buildNavigatorPushHostDiagnostic(
        route: route,
        navigator: navigator,
        currentRoute: currentRoute,
        nearestNavigatorHash: navigator.hashCode,
        rootNavigatorHash: rootNavigator?.hashCode,
        mainNavigatorHash: mainNavigator?.hashCode,
        rootNavigator: isRootNavigator,
        observerAttached: observerAttached,
        nestedNavigator: isNestedNavigator,
        navigatorRole: navigatorRole,
      ),
    );
    return navigator.pushReplacement(route);
  }

  double get width => MediaQuery.of(this).size.width;

  double get height => MediaQuery.of(this).size.height;

  EdgeInsets get padding => MediaQuery.of(this).padding;

  EdgeInsets get viewInsets => MediaQuery.of(this).viewInsets;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  Brightness get brightness => Theme.of(this).brightness;

  bool get isDarkMode => brightness == Brightness.dark;

  void showMessage({required String message}) {
    showToast(message: message, context: this);
  }

  Color useBackgroundColor(MaterialColor color) {
    return color[brightness == Brightness.light ? 100 : 800]!;
  }

  Color useTextColor(MaterialColor color) {
    return color[brightness == Brightness.light ? 800 : 100]!;
  }
}
