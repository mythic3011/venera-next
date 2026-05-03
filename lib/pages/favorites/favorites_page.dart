import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/features/favorites/data/favorites_runtime_repository.dart';
import 'package:venera/foundation/download_queue_legacy_bridge.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/features/reader/data/reader_status_repository.dart';
import 'package:venera/features/reader/presentation/reader_route_dispatch_authority.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/bridge/favorites_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/network/download.dart';
import 'package:venera/network/cache.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/tags_translation.dart';
import 'package:venera/utils/translations.dart';

part 'favorite_actions.dart';
part 'side_bar.dart';
part 'local_favorites_page.dart';
part 'network_favorites_page.dart';

const _kLeftBarWidth = 256.0;

const _kTwoPanelChangeWidth = 720.0;

const favoritesRepo = FavoritesRuntimeRepository();

Map<String, dynamic>? readFavoritesFolderSelection() {
  recordAppdataAuthorityDiagnostic(
    channel: 'appdata.audit',
    event: 'appdata.authority.access',
    key: 'favoriteFolder',
    storage: AppdataAuditStorage.implicitData,
    access: 'read',
    data: const <String, Object?>{'owner': 'FavoritesPage'},
  );
  final data = appdata.implicitData['favoriteFolder'];
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  return null;
}

bool isFavoritesReaderNextFlagEnabled(Object? rawValue) => rawValue == true;

typedef ReaderNextFavoritesOpenExecutorFactory =
    ReaderNextFavoritesOpenExecutor Function();

ReaderNextFavoritesOpenExecutor? resolveFavoritesReaderNextExecutor({
  ReaderNextFavoritesOpenExecutor? injectedExecutor,
  ReaderNextFavoritesOpenExecutorFactory? injectedFactory,
  ReaderNextFavoritesOpenExecutorFactory approvedFactory =
      createApprovedReaderNextNavigationExecutor,
}) {
  return resolveApprovedReaderNextExecutor(
    injectedExecutor: injectedExecutor,
    injectedFactory: injectedFactory,
    approvedFactory: approvedFactory,
  );
}

FavoritesRouteCutoverResult evaluateFavoritesPreflightForRowContext({
  required FavoritesRouteCutoverController controller,
  required FavoriteItem comic,
  required String folderName,
  required ReadinessArtifact readinessArtifact,
  bool isRowStale = false,
}) {
  return controller.evaluate(
    input: IdentityCoverageInput.favorite(
      recordId: comic.id,
      sourceKey: comic.sourceKey,
      folderName: folderName,
      canonicalComicId: null,
      sourceRef: null,
      explicitSnapshotAlreadyPersisted: false,
    ),
    artifact: readinessArtifact,
    isRowStale: isRowStale,
  );
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    this.readerNextOpenExecutor,
    this.readerNextOpenExecutorFactory,
    this.onDiagnostic,
  });

  final ReaderNextFavoritesOpenExecutor? readerNextOpenExecutor;
  final ReaderNextFavoritesOpenExecutorFactory? readerNextOpenExecutorFactory;
  final FavoritesDiagnosticSink? onDiagnostic;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String? folder;

  bool isNetwork = false;
  bool _isReady = false;

  FolderList? folderList;

  void setFolder(bool isNetwork, String? folder) {
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    folderList?.update();
    appdata.implicitData['favoriteFolder'] = {
      'name': folder,
      'isNetwork': isNetwork,
    };
    appdata.writeImplicitData();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await favoritesRepo.init();
    var data = readFavoritesFolderSelection();
    if (data != null) {
      folder = data['name'];
      isNetwork = data['isNetwork'] ?? false;
    }
    if (folder != null && !isNetwork && !favoritesRepo.existsFolder(folder!)) {
      folder = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const SizedBox.shrink();
    }
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.secondary),
      child: Stack(
        children: [
          AnimatedPositioned(
            left: context.width <= _kTwoPanelChangeWidth ? -_kLeftBarWidth : 0,
            top: 0,
            bottom: 0,
            duration: const Duration(milliseconds: 200),
            child: (const _LeftBar()).fixWidth(_kLeftBarWidth),
          ),
          Positioned(
            top: 0,
            left: context.width <= _kTwoPanelChangeWidth ? 0 : _kLeftBarWidth,
            right: 0,
            bottom: 0,
            child: buildBody(),
          ),
        ],
      ),
    );
  }

  void showFolderSelector() {
    Navigator.of(App.rootContext).push(
      PageRouteBuilder(
        barrierDismissible: true,
        fullscreenDialog: true,
        opaque: false,
        barrierColor: Colors.black.toOpacity(0.36),
        pageBuilder: (context, animation, secondary) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Material(
              child: SizedBox(
                width: min(300, context.width - 16),
                child: _LeftBar(
                  withAppbar: true,
                  favPage: this,
                  onSelected: () {
                    context.pop();
                  },
                ),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondary, child) {
          var offset = Tween<Offset>(
            begin: const Offset(-1, 0),
            end: const Offset(0, 0),
          );
          return SlideTransition(
            position: offset.animate(
              CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget buildBody() {
    if (folder == null) {
      return CustomScrollView(
        slivers: [
          SliverAppbar(
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= _kTwoPanelChangeWidth
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      color: context.colorScheme.primary,
                      onPressed: showFolderSelector,
                    )
                  : null,
            ),
            title: GestureDetector(
              onTap: context.width < _kTwoPanelChangeWidth
                  ? showFolderSelector
                  : null,
              child: Text("Unselected".tl),
            ),
          ),
        ],
      );
    }
    if (!isNetwork) {
      return _LocalFavoritesPage(
        folder: folder!,
        key: PageStorageKey("local_$folder"),
      );
    } else {
      var favoriteData = getFavoriteDataOrNull(folder!);
      if (favoriteData == null) {
        folder = null;
        return buildBody();
      } else {
        return NetworkFavoritePage(
          favoriteData,
          key: PageStorageKey("network_$folder"),
        );
      }
    }
  }
}

abstract interface class FolderList {
  void update();

  void updateFolders();
}
