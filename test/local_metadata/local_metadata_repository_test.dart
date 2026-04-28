import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local_metadata/local_metadata.dart';
import 'package:venera/utils/io.dart';

LocalComic _buildComic() {
  return LocalComic(
    id: '1',
    title: 'Series',
    subtitle: 'Author',
    tags: const ['tag'],
    directory: 'series',
    chapters: const ComicChapters({'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: const ['c1', 'c2'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<(LocalManager, LocalMetadataRepository, File)> _buildManagerWithRepo({
  required String tempPrefix,
}) async {
  final dir = await Directory.systemTemp.createTemp(tempPrefix);
  final sidecar = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
  final repository = LocalMetadataRepository(sidecar.path);
  await repository.init();
  final manager = LocalManager();
  manager.setMetadataRepositoryForTest(repository);
  return (manager, repository, sidecar);
}

void main() {
  group('LocalMetadataRepository', () {
    test('corrupt sidecar falls back to empty document', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_corrupt_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      await file.writeAsString('{broken json');

      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      expect(repository.document.series, isEmpty);
      expect(repository.document.version, LocalMetadataDocument.currentVersion);
    });

    test('persist uses replace flow and roundtrips', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_write_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));

      final repository = LocalMetadataRepository(file.path);
      await repository.init();
      await repository.upsertSeries(
        LocalSeriesMeta(
          seriesKey: '0:1',
          groups: const [
            LocalChapterGroup(id: 'g1', label: 'Season 1', sortOrder: 0),
          ],
          chapters: const {
            'c1': LocalChapterMeta(
              chapterId: 'c1',
              displayTitle: 'Ep 1',
              groupId: 'g1',
              sortOrder: 0,
            ),
          },
        ),
      );

      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);

      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(payload['version'], LocalMetadataDocument.currentVersion);
      expect((payload['series'] as Map<String, dynamic>).containsKey('0:1'), isTrue);

      final reloaded = LocalMetadataRepository(file.path);
      await reloaded.init();
      final series = reloaded.getSeries('0:1');
      expect(series, isNotNull);
      expect(series!.groups.single.label, 'Season 1');
      expect(series.chapters['c1']!.displayTitle, 'Ep 1');
    });
  });

  group('LocalManager metadata overlay', () {
    test('corrupt sidecar still renders legacy chapters', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_overlay_bad_');
      final sidecar = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      await sidecar.writeAsString('{bad');
      final repository = LocalMetadataRepository(sidecar.path);
      await repository.init();

      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      final effective = manager.readEffectiveChapters(comic);
      expect(effective, isNotNull);
      expect(effective!.groupedChapters.length, 1);
      expect(effective.groupedChapters.keys.single, LocalSeriesMeta.defaultGroupLabel);
      expect(
        effective.groupedChapters[LocalSeriesMeta.defaultGroupLabel],
        LinkedHashMap<String, String>.from({'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
      );
    });

    test('createGroup and renameGroup write sidecar only', () async {
      final (manager, repository, sidecar) = await _buildManagerWithRepo(
        tempPrefix: 'local_meta_group_',
      );
      final comic = _buildComic();
      final sidecarBefore = await sidecar.exists()
          ? await sidecar.readAsString()
          : '';

      await manager.createGroup(comic, groupId: 'g1', label: 'Season One');
      await manager.renameGroup(comic, groupId: 'g1', newLabel: 'Season 1');

      final series = repository.getSeries('0:1');
      expect(series, isNotNull);
      expect(series!.groups.length, 1);
      expect(series.groups.first.id, 'g1');
      expect(series.groups.first.label, 'Season 1');
      expect(await sidecar.readAsString(), isNot(sidecarBefore));
    });

    test('assignChapterToGroup and renameChapter write overrides only', () async {
      final (manager, repository, _) = await _buildManagerWithRepo(
        tempPrefix: 'local_meta_chapter_',
      );
      final comic = _buildComic();
      await manager.createGroup(comic, groupId: 'g1', label: 'Arc 1');

      await manager.assignChapterToGroup(comic, chapterId: 'c1', groupId: 'g1');
      await manager.renameChapter(comic, chapterId: 'c1', newTitle: 'Episode One');

      final series = repository.getSeries('0:1');
      expect(series, isNotNull);
      final c1 = series!.chapters['c1'];
      expect(c1, isNotNull);
      expect(c1!.groupId, 'g1');
      expect(c1.displayTitle, 'Episode One');
      expect(c1.sortOrder, isNull);
    });

    test('reorderChapters stores sidecar sort order only', () async {
      final (manager, repository, _) = await _buildManagerWithRepo(
        tempPrefix: 'local_meta_reorder_',
      );
      final comic = _buildComic();

      await manager.reorderChapters(
        comic,
        groupId: LocalSeriesMeta.defaultGroupId,
        orderedChapterIds: const ['c2', 'c1'],
      );

      final series = repository.getSeries('0:1');
      expect(series, isNotNull);
      expect(series!.chapters['c2']!.sortOrder, 0);
      expect(series.chapters['c1']!.sortOrder, 1);
      expect(series.chapters['c2']!.groupId, LocalSeriesMeta.defaultGroupId);
      expect(series.chapters['c1']!.groupId, LocalSeriesMeta.defaultGroupId);
      expect(comic.chapters!.allChapters['c1'], 'Chapter 1');
      expect(comic.chapters!.allChapters['c2'], 'Chapter 2');
    });

    test('metadata APIs do not mutate local.db or page assets', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_inert_');
      final sidecar = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      final localDb = File(FilePath.join(dir.path, 'local.db'));
      final pageAsset = File(FilePath.join(dir.path, '1.jpg'));
      await localDb.writeAsString('legacy-db-sentinel');
      await pageAsset.writeAsString('image-sentinel');

      final repository = LocalMetadataRepository(sidecar.path);
      await repository.init();
      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      final dbBefore = await localDb.readAsString();
      final pageBefore = await pageAsset.readAsString();

      await manager.createGroup(comic, groupId: 'g1', label: 'Season');
      await manager.renameGroup(comic, groupId: 'g1', newLabel: 'Season 1');
      await manager.assignChapterToGroup(comic, chapterId: 'c1', groupId: 'g1');
      await manager.renameChapter(comic, chapterId: 'c1', newTitle: 'Ep 1');
      await manager.reorderChapters(
        comic,
        groupId: LocalSeriesMeta.defaultGroupId,
        orderedChapterIds: const ['c2', 'c1'],
      );

      expect(await localDb.readAsString(), dbBefore);
      expect(await pageAsset.readAsString(), pageBefore);
    });

    test('no sidecar keeps legacy render identical', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_overlay_1_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      final effective = manager.readEffectiveChapters(comic);
      expect(effective, isNotNull);
      expect(effective!.groupedChapters.length, 1);
      expect(effective.groupedChapters.keys.single, LocalSeriesMeta.defaultGroupLabel);
      expect(
        effective.groupedChapters[LocalSeriesMeta.defaultGroupLabel],
        LinkedHashMap<String, String>.from({'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
      );
      expect(comic.chapters!.allChapters, {'c1': 'Chapter 1', 'c2': 'Chapter 2'});
    });

    test('group and chapter overlays apply in read model only', () async {
      final dir = await Directory.systemTemp.createTemp('local_meta_overlay_2_');
      final file = File(FilePath.join(dir.path, 'local_metadata_v1.json'));
      final repository = LocalMetadataRepository(file.path);
      await repository.init();

      final manager = LocalManager();
      manager.setMetadataRepositoryForTest(repository);
      final comic = _buildComic();

      await manager.createGroup(comic, groupId: 's1', label: 'Season 1');
      await manager.assignChapterToGroup(comic, chapterId: 'c1', groupId: 's1');
      await manager.renameChapter(comic, chapterId: 'c1', newTitle: 'Episode One');
      await manager.reorderChapters(
        comic,
        groupId: LocalSeriesMeta.defaultGroupId,
        orderedChapterIds: const ['c2'],
      );

      final effective = manager.readEffectiveChapters(comic);
      expect(effective, isNotNull);
      expect(effective!.groupedChapters.keys.toList(), ['Chapters', 'Season 1']);
      expect(effective.groupedChapters['Season 1']!['c1'], 'Episode One');
      expect(effective.groupedChapters['Chapters']!['c2'], 'Chapter 2');

      expect(comic.chapters!.allChapters['c1'], 'Chapter 1');
      expect(comic.chapters!.allChapters['c2'], 'Chapter 2');
    });
  });
}
