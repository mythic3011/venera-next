import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _methodChannel = MethodChannel(
    'venera/method_channel',
  );
  static const String _runtimeRootOverrideEnvKey = 'VENERA_RUNTIME_ROOT';
  static const String _runtimeRootOverrideLegacyEnvKey =
      'VENERA_RUNTIME_ROOT_OVERRIDE';
  static const String _runtimeRootMethodName = 'getRuntimeRootOverride';

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
  String? _runtimeRootOverridePath;
  String? _runtimeRootBasePath;

  final rootNavigatorKey = GlobalKey<NavigatorState>();

  GlobalKey<NavigatorState>? mainNavigatorKey;

  BuildContext get rootContext => rootNavigatorKey.currentContext!;

  final Appdata data = appdata;

  late AppRepositories repositories;
  late final UnifiedComicsStore _unifiedComicsStore;
  UnifiedComicsStore? _runtimeCanonicalStoreOverride;
  bool _hasUnifiedComicsStore = false;

  @Deprecated(
    'Use App.repositories instead. Direct store access is allowed only for bootstrap, migrations, imports, and legacy compatibility code.',
  )
  UnifiedComicsStore get unifiedComicsStore =>
      _runtimeCanonicalStoreOverride ?? _unifiedComicsStore;

  UnifiedComicsStore? get unifiedComicsStoreOrNull {
    if (_runtimeCanonicalStoreOverride != null) {
      return _runtimeCanonicalStoreOverride;
    }
    if (_hasUnifiedComicsStore) {
      return _unifiedComicsStore;
    }
    return null;
  }

  bool get runtimeRootOverrideActive => _runtimeRootOverridePath != null;

  String? get runtimeRootOverridePath => _runtimeRootOverridePath;

  String? get runtimeRootBasePath => _runtimeRootBasePath;

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
    final runtimeRoot = await _resolveRuntimeRoot();
    dataPath = runtimeRoot.dataPath;
    cachePath = runtimeRoot.cachePath;
    _runtimeRootOverridePath = runtimeRoot.overridePath;
    _runtimeRootBasePath = runtimeRoot.basePath;
    _unifiedComicsStore = UnifiedComicsStore.atCanonicalPath(dataPath);
    _hasUnifiedComicsStore = true;
    _runtimeCanonicalStoreOverride = null;
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
    UnifiedComicsStore? canonicalStore,
    Future<void> Function()? initCanonicalStore,
    Future<void> Function()? seedSourcePlatforms,
  }) async {
    final runtimeStore = canonicalStore ?? _unifiedComicsStore;
    _runtimeCanonicalStoreOverride = canonicalStore;
    await Future.wait([
      (initAppData ?? data.init)(),
      () async {
        await (initCanonicalStore ?? runtimeStore.init)();
        await (seedSourcePlatforms ??
            runtimeStore.seedDefaultSourcePlatforms)();
      }(),
    ]);
    final comicDetailStore = UnifiedComicDetailStoreAdapter(runtimeStore);
    final readerSessionRepository = ReaderSessionRepository(
      store: UnifiedReaderSessionStoreAdapter(runtimeStore),
    );
    repositories = AppRepositories(
      readerSession: readerSessionRepository,
      readerActivity: ReaderActivityRepository(
        store: UnifiedReaderActivityStoreAdapter(runtimeStore),
      ),
      readerStatus: ReaderStatusRepository(
        store: UnifiedReaderStatusStoreAdapter(runtimeStore),
      ),
      comicDetail: UnifiedCanonicalComicDetailRepository(
        store: comicDetailStore,
        readerSessions: readerSessionRepository,
      ),
      comicUserTags: ComicUserTagsRepository(store: comicDetailStore),
      comicDetailStore: comicDetailStore,
      remoteMatch: RemoteMatchRepository(
        store: UnifiedRemoteMatchStoreAdapter(runtimeStore),
      ),
      localLibrary: LocalLibraryRepository(
        store: UnifiedLocalLibraryBrowseStoreAdapter(runtimeStore),
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

  Future<_RuntimeRootResolution> _resolveRuntimeRoot() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final cacheDirectory = await getApplicationCacheDirectory();
    final overridePath = await _resolveRuntimeRootOverride();
    if (overridePath != null) {
      final runtimeRoot = Directory(overridePath).absolute.path;
      return _RuntimeRootResolution(
        dataPath: runtimeRoot,
        cachePath: '$runtimeRoot${Platform.pathSeparator}cache',
        overridePath: runtimeRoot,
        basePath: supportDirectory.path,
      );
    }
    return _RuntimeRootResolution(
      dataPath: supportDirectory.path,
      cachePath: cacheDirectory.path,
      overridePath: null,
      basePath: supportDirectory.path,
    );
  }

  Future<String?> _resolveRuntimeRootOverride() async {
    final fromEnvironment = _readRuntimeRootDefine();
    if (fromEnvironment != null) {
      return fromEnvironment;
    }
    if (!isDesktop) {
      return null;
    }
    try {
      final result = await _methodChannel.invokeMethod<String>(
        _runtimeRootMethodName,
      );
      if (result == null || result.trim().isEmpty) {
        return null;
      }
      return result.trim();
    } catch (_) {
      return null;
    }
  }

  String? _readRuntimeRootDefine() {
    const value = String.fromEnvironment(_runtimeRootOverrideEnvKey);
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
    const legacy = String.fromEnvironment(_runtimeRootOverrideLegacyEnvKey);
    if (legacy.trim().isNotEmpty) {
      return legacy.trim();
    }
    return null;
  }
}

class _RuntimeRootResolution {
  final String dataPath;
  final String cachePath;
  final String? overridePath;
  final String basePath;

  const _RuntimeRootResolution({
    required this.dataPath,
    required this.cachePath,
    required this.overridePath,
    required this.basePath,
  });
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
