import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

void handleLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    handleAppLink(uri);
  });
}

Future<bool> handleAppLink(Uri uri) async {
  for (var source in ComicSource.all()) {
    if (source.linkHandler != null) {
      if (source.linkHandler!.domains.contains(uri.host)) {
        var id = source.linkHandler!.linkToId(uri.toString());
        if (id != null) {
          final navigator = await _waitForMainNavigatorState();
          if (navigator == null) {
            return false;
          }
          await navigator.push(
            MaterialPageRoute(
              builder: (context) => ComicPage(id: id, sourceKey: source.key),
            ),
          );
          return true;
        }
        return false;
      }
    }
  }
  return false;
}

Future<NavigatorState?> _waitForMainNavigatorState() async {
  // App links can arrive during Android cold start before MainPage installs
  // the nested navigator; wait briefly instead of force-unwrapping it.
  for (var i = 0; i < 10; i++) {
    final navigator = App.mainNavigatorKey?.currentState;
    if (navigator != null) {
      return navigator;
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return null;
}
