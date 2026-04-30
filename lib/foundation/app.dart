import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:venera/features/comic_detail/data/comic_detail_remote_match_repository.dart';
import 'package:venera/features/comic_detail/data/comic_detail_repository.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/features/reader/data/reader_status_repository.dart';
import 'package:venera/foundation/db/adapters/unified_comic_detail_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_local_library_browse_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_activity_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_session_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_status_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_remote_match_store_adapter.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/repositories/comic_user_tags_repository.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

import 'appdata.dart';

export "widget_utils.dart";
export "context.dart";

class _App {
  final version = "1.6.3";

  bool get isAndroid => Platform.isAndroid;

  bool get isIOS => Platform.isIOS;

  bool get isWindows => Platform.isWindows;

  bool get isLinux => Platform.isLinux;

  bool get isMacOS => Platform.isMacOS;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Whether the app has been initialized.
  // If current Isolate is main Isolate, this value is always true.
  bool isInitialized = false;

  Locale get locale {
    Locale deviceLocale = PlatformDispatcher.instance.locale;
    if (deviceLocale.languageCode == "zh" &&
        deviceLocale.scriptCode == "Hant") {
      deviceLocale = const Locale("zh", "TW");
    }
    if (appdata.settings['language'] != 'system') {
      return Locale(
        appdata.settings['language'].split('-')[0],
        appdata.settings['language'].split('-')[1],
      );
    }
    return deviceLocale;
  }

  late String dataPath;
  late String cachePath;
  String? externalStoragePath;

  final rootNavigatorKey = GlobalKey<NavigatorState>();

  GlobalKey<NavigatorState>? mainNavigatorKey;

  BuildContext get rootContext => rootNavigatorKey.currentContext!;

  final Appdata data = appdata;

  late AppRepositories repositories;
  late final UnifiedComicsStore _unifiedComicsStore;

  @Deprecated(
    'Use App.repositories instead. Direct store access is allowed only for bootstrap, migrations, imports, and legacy compatibility code.',
  )
  UnifiedComicsStore get unifiedComicsStore => _unifiedComicsStore;

  void rootPop() {
    rootNavigatorKey.currentState?.maybePop();
  }

  void pop() {
    if (rootNavigatorKey.currentState?.canPop() ?? false) {
      rootNavigatorKey.currentState?.pop();
    } else if (mainNavigatorKey?.currentState?.canPop() ?? false) {
      mainNavigatorKey?.currentState?.pop();
    }
  }

  Future<void> init() async {
    cachePath = (await getApplicationCacheDirectory()).path;
    dataPath = (await getApplicationSupportDirectory()).path;
    _unifiedComicsStore = UnifiedComicsStore.atCanonicalPath(dataPath);
    if (isAndroid) {
      externalStoragePath = (await getExternalStorageDirectory())!.path;
    }
    isInitialized = true;
  }

  Future<void> initComponents() async {
    await initRuntimeComponents();
  }

  Future<void> initRuntimeComponents({
    Future<void> Function()? initAppData,
    Future<void> Function()? initCanonicalStore,
    Future<void> Function()? seedSourcePlatforms,
  }) async {
    await Future.wait([
      (initAppData ?? data.init)(),
      () async {
        await (initCanonicalStore ?? _unifiedComicsStore.init)();
        await (seedSourcePlatforms ??
            _unifiedComicsStore.seedDefaultSourcePlatforms)();
      }(),
    ]);
    final comicDetailStore = UnifiedComicDetailStoreAdapter(
      _unifiedComicsStore,
    );
    repositories = AppRepositories(
      readerSession: ReaderSessionRepository(
        store: UnifiedReaderSessionStoreAdapter(_unifiedComicsStore),
      ),
      readerActivity: ReaderActivityRepository(
        store: UnifiedReaderActivityStoreAdapter(_unifiedComicsStore),
      ),
      readerStatus: ReaderStatusRepository(
        store: UnifiedReaderStatusStoreAdapter(_unifiedComicsStore),
      ),
      comicDetail: UnifiedCanonicalComicDetailRepository(
        store: comicDetailStore,
      ),
      comicUserTags: ComicUserTagsRepository(store: comicDetailStore),
      comicDetailStore: comicDetailStore,
      remoteMatch: RemoteMatchRepository(
        store: UnifiedRemoteMatchStoreAdapter(_unifiedComicsStore),
      ),
      localLibrary: LocalLibraryRepository(
        store: UnifiedLocalLibraryBrowseStoreAdapter(_unifiedComicsStore),
      ),
    );
  }

  Function? _forceRebuildHandler;

  void registerForceRebuild(Function handler) {
    _forceRebuildHandler = handler;
  }

  void forceRebuild() {
    _forceRebuildHandler?.call();
  }
}

class AppRepositories {
  final ReaderSessionRepository readerSession;
  final ReaderActivityRepository readerActivity;
  final ReaderStatusRepository readerStatus;
  final ComicDetailRepository comicDetail;
  final ComicUserTagsRepository comicUserTags;
  final ComicDetailStorePort comicDetailStore;
  final RemoteMatchRepository remoteMatch;
  final LocalLibraryRepository localLibrary;

  const AppRepositories({
    required this.readerSession,
    required this.readerActivity,
    required this.readerStatus,
    required this.comicDetail,
    required this.comicUserTags,
    required this.comicDetailStore,
    required this.remoteMatch,
    required this.localLibrary,
  });
}

// ignore: non_constant_identifier_names
final App = _App();
