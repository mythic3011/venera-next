import 'package:venera/foundation/db/store_records.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';

class ComicUserTagsRepository {
  const ComicUserTagsRepository({required this.store});

  final ComicDetailStorePort store;

  Future<List<UserTagRecord>> loadUserTagsForComic(String comicId) {
    return store.loadUserTagsForComic(comicId);
  }

  Future<void> saveComicTags({
    required String comicId,
    required List<String> tags,
  }) async {
    final existing = await loadUserTagsForComic(comicId);
    final existingByNormalized = {
      for (final tag in existing) _normalize(tag.name): tag,
    };
    final nextByNormalized = {
      for (final tag in tags)
        if (_normalize(tag).isNotEmpty) _normalize(tag): tag.trim(),
    };

    for (final entry in existingByNormalized.entries) {
      if (!nextByNormalized.containsKey(entry.key)) {
        await store.removeUserTagFromComic(
          comicId: comicId,
          userTagId: entry.value.id,
        );
      }
    }

    for (final entry in nextByNormalized.entries) {
      final id = existingByNormalized[entry.key]?.id ?? 'user_tag:${entry.key}';
      await store.upsertUserTag(
        UserTagRecord(id: id, name: entry.value, normalizedName: entry.key),
      );
      await store.attachUserTagToComic(
        ComicUserTagRecord(comicId: comicId, userTagId: id),
      );
    }
  }
}

String _normalize(String value) => value.trim().toLowerCase();
