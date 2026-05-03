import 'dart:async';

import 'package:display_mode/display_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:rhttp/rhttp.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/js/js_engine.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/app/navigation/app_links.dart';
import 'package:venera/app/navigation/handle_text_share.dart';
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/tags_translation.dart';
import 'package:venera/utils/translations.dart';
import 'foundation/appdata.dart';

extension _FutureInit<T> on Future<T> {
  /// Prevent unhandled exception
  ///
  /// A unhandled exception occurred in init() will cause the app to crash.
  Future<void> wait() async {
    try {
      await this;
    } catch (e, s) {
      AppDiagnostics.error('app.init', e, stackTrace: s);
    }
  }
}

Future<void> init() async {
  await App.init().wait();
  await SingleInstanceCookieJar.createInstance();
  try {
    await OpenCC.init().wait();
    var futures = [
      pdfrxFlutterInitialize().wait(),
      Rhttp.init(),
      App.initComponents(),
      SAFTaskWorker().init().wait(),
      AppTranslation.init().wait(),
      JsEngine().init().wait(),
      ComicSourceManager().init().wait(),
    ];
    await Future.wait(futures);
    await TagsTranslation.readData().wait();
  } catch (e, s) {
    AppDiagnostics.error('app.init', e, stackTrace: s);
  }
  CacheManager().setLimitSize(appdata.settings['cacheSize']);
  _checkOldConfigs();
  if (App.isAndroid) {
    handleLinks();
    handleTextShare();
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      AppDiagnostics.error('app.init', e, message: 'set_high_refresh_rate_failed');
    }
  }
  FlutterError.onError = (details) {
    AppDiagnostics.error(
      'app.unhandled',
      details.exception,
      stackTrace: details.stack,
      message: details.exception.toString(),
      data: {
        'exceptionMessage': details.exception.toString(),
        'exceptionType': details.exception.runtimeType.toString(),
        'exceptionStack': details.stack?.toString(),
      },
    );
  };
  if (App.isWindows) {
    // Report to the monitor thread that the app is running
    // https://github.com/venera-app/venera/issues/343
    Timer.periodic(const Duration(seconds: 1), (_) {
      const methodChannel = MethodChannel('venera/method_channel');
      methodChannel.invokeMethod("heartBeat");
    });
  }
}

void _checkOldConfigs() {
  if (appdata.settings['searchSources'] == null) {
    appdata.settings['searchSources'] = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
  }

  if (appdata.implicitData['webdavAutoSync'] == null) {
    var webdavConfig = appdata.settings['webdav'];
    if (webdavConfig is List &&
        webdavConfig.length == 3 &&
        webdavConfig.whereType<String>().length == 3) {
      appdata.implicitData['webdavAutoSync'] = true;
    } else {
      appdata.implicitData['webdavAutoSync'] = false;
    }
    appdata.writeImplicitData();
  }

}

Future<void> _checkAppUpdates() async {
  var lastCheck = appdata.implicitData['lastCheckUpdate'] ?? 0;
  var now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastCheck < 24 * 60 * 60 * 1000) {
    return;
  }
  appdata.implicitData['lastCheckUpdate'] = now;
  appdata.writeImplicitData();
  ComicSourcePage.checkComicSourceUpdate();
  if (appdata.settings['checkUpdateOnStart']) {
    final updateContext =
        App.rootNavigatorKey.currentState?.context ??
        App.mainNavigatorKey?.currentState?.context;
    if (updateContext == null) {
      return;
    }
    await checkUpdateUi(
      context: updateContext,
      showMessageIfNoUpdate: false,
      delay: true,
    );
  }
}

void checkUpdates() {
  _checkAppUpdates();
  FollowUpdatesService.initChecker();
}
