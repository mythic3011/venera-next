import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/pages/aggregated_search_page.dart';

bool _isHandling = false;

/// Handle text share event.
/// App will navigate to [AggregatedSearchPage] with the shared text as keyword.
void handleTextShare() async {
  if (_isHandling) return;
  _isHandling = true;

  var channel = EventChannel('venera/text_share');
  await for (var event in channel.receiveBroadcastStream()) {
    final navigator = await _waitForMainNavigatorState();
    if (event is String) {
      await navigator?.push(
        MaterialPageRoute(
          builder: (context) => AggregatedSearchPage(keyword: event),
        ),
      );
    }
  }
}

Future<NavigatorState?> _waitForMainNavigatorState() async {
  for (var i = 0; i < 10; i++) {
    final navigator = App.mainNavigatorKey?.currentState;
    if (navigator != null) {
      return navigator;
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return null;
}
