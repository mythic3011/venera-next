import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';

void main() {
  test('ComicTileMeta normalizes zero history page outside build', () {
    final history = History.fromMap({
      'type': ComicType.local.value,
      'time': DateTime(2026).millisecondsSinceEpoch,
      'title': 'Title',
      'subtitle': '',
      'cover': '',
      'ep': 1,
      'page': 0,
      'id': 'comic-1',
      'readEpisode': const <String>[],
      'max_page': 10,
    });

    final meta = ComicTileMeta.fromStatus(
      isFavorite: true,
      history: history,
      displayMode: 'brief',
    );

    expect(meta.isFavorite, isTrue);
    expect(meta.history?.page, 1);
    expect(history.page, 0);
  });

  test('ComicTileMeta defaults are deterministic manager-free values', () {
    final meta = ComicTileMeta.defaults();

    expect(meta.displayMode, 'brief');
    expect(meta.isFavorite, isFalse);
    expect(meta.history, isNull);
    expect(meta.localCoverFile, isNull);
  });

  testWidgets('ComicTile local source uses only supplied localCoverFile metadata',
      (tester) async {
    final comic = Comic(
      'Local',
      '',
      'local-1',
      '',
      const <String>[],
      '',
      'local',
      null,
      null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicTile(
            comic: comic,
            meta: ComicTileMeta.defaults(),
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedImage), findsNothing);

    final file = File(
      '${Directory.systemTemp.path}/comic_tile_meta_local_cover_test.jpg',
    );
    file.writeAsBytesSync(const <int>[0, 1, 2, 3], flush: true);
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicTile(
            comic: comic,
            meta: ComicTileMeta.fromStatus(
              isFavorite: false,
              history: null,
              displayMode: 'brief',
              localCoverFile: file,
            ),
          ),
        ),
      ),
    );

    final animatedImage =
        tester.widget<AnimatedImage>(find.byType(AnimatedImage));
    expect(animatedImage.image, isA<FileImage>());
    final fileImage = animatedImage.image as FileImage;
    expect(fileImage.file.path, file.path);
  });
}
