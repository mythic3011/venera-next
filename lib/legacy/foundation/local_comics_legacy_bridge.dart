import 'dart:io';

import 'package:flutter/material.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';

sealed class LegacyLocalComicLookupResult {
  const LegacyLocalComicLookupResult();
}

class LegacyLocalComicLookupFound extends LegacyLocalComicLookupResult {
  final LocalComic comic;

  const LegacyLocalComicLookupFound(this.comic);
}

class LegacyLocalComicLookupNotFound extends LegacyLocalComicLookupResult {
  const LegacyLocalComicLookupNotFound();
}

class LegacyLocalComicLookupUnavailable extends LegacyLocalComicLookupResult {
  final String code;

  const LegacyLocalComicLookupUnavailable({this.code = 'LEGACY_UNAVAILABLE'});
}

bool _isLateInitError(Object error) {
  final asText = error.toString();
  return asText.contains('LateInitializationError') ||
      asText.contains('late initialization');
}

Future<void> legacyEnsureLocalComicsInitialized() {
  return LocalManager().ensureInitialized();
}

bool legacyIsLocalComicsInitialized() {
  return LocalManager().isInitialized;
}

void legacyAddLocalComicsListener(VoidCallback listener) {
  LocalManager().addListener(listener);
}

void legacyRemoveLocalComicsListener(VoidCallback listener) {
  LocalManager().removeListener(listener);
}

List<LocalComic> legacyGetLocalComics(LocalSortType sortType) {
  return LocalManager().getComics(sortType);
}

List<LocalComic> legacyGetRecentLocalComics() {
  return LocalManager().getRecent();
}

int legacyCountLocalComics() {
  return LocalManager().count;
}

List<LocalComic> legacySearchLocalComics(String keyword) {
  return LocalManager().search(keyword);
}

LocalComic? legacyFindLocalComicByName(String name) {
  return LocalManager().findByName(name);
}

LegacyLocalComicLookupResult legacyLookupLocalComicByName(
  String name, {
  LocalComic? Function(String name)? finder,
}) {
  try {
    final comic = (finder ?? legacyFindLocalComicByName).call(name);
    if (comic == null) {
      return const LegacyLocalComicLookupNotFound();
    }
    return LegacyLocalComicLookupFound(comic);
  } catch (error) {
    if (_isLateInitError(error)) {
      return const LegacyLocalComicLookupUnavailable();
    }
    rethrow;
  }
}

String legacyFindValidLocalComicId(ComicType type) {
  return LocalManager().findValidId(type);
}

String legacyReadLocalComicsRootPath() {
  return LocalManager().path;
}

LocalComic? legacyFindLocalComicByIdAndType(String id, ComicType comicType) {
  return LocalManager().find(id, comicType);
}

LocalComic? legacyFindLocalComicBySourceKey(String id, String sourceKey) {
  return LocalManager().findBySourceKey(id, sourceKey);
}

Future<List<String>> legacyLoadLocalComicImages(
  String comicId,
  ComicType comicType,
  Object chapterOrIndex,
) {
  return LocalManager().getImages(comicId, comicType, chapterOrIndex);
}

Future<List<String>> legacyLoadLocalComicImagesBySourceKey(
  String comicId,
  String sourceKey,
  Object chapterOrIndex,
) {
  return LocalManager().getImagesBySourceKey(
    comicId,
    sourceKey,
    chapterOrIndex,
  );
}

String legacyLocalComicsRootPath() {
  return LocalManager().path;
}

Directory legacyLocalComicsDirectory() {
  return LocalManager().directory;
}

LocalComic? legacyFindLocalComicForDownload(String id, ComicType comicType) {
  return LocalManager().find(id, comicType);
}

Future<Directory> legacyFindValidLocalComicDirectory(
  String id,
  ComicType type,
  String name,
) {
  return LocalManager().findValidDirectory(id, type, name);
}

Future<void> legacySaveCurrentDownloadQueueState() {
  return LocalManager().saveCurrentDownloadingTasks();
}

bool legacyIsLocalComicDownloading(String comicId, ComicType type) {
  return LocalManager().isDownloading(comicId, type);
}

bool legacyIsLocalComicDownloaded(String comicId, ComicType type, int ep) {
  return LocalManager().isDownloaded(comicId, type, ep);
}

void legacyRenameLocalComicChapter(
  LocalComic comic,
  String chapterId,
  String newName,
) {
  LocalManager().renameComicChapter(comic, chapterId, newName);
}

void legacyDeleteLocalComicChapters(LocalComic comic, List<String> chapters) {
  LocalManager().deleteComicChapters(comic, chapters);
}

void legacyBatchDeleteLocalComics(
  List<LocalComic> comics,
  bool removeComicFile,
  bool removeFavoriteAndHistory,
) {
  LocalManager().batchDeleteComics(
    comics,
    removeComicFile,
    removeFavoriteAndHistory,
  );
}

Future<void> legacyReorderLocalComicPages(
  LocalComic comic,
  Object chapterOrIndex,
  List<String> pageOrder,
) {
  return LocalManager().reorderComicPages(comic, chapterOrIndex, pageOrder);
}

Future<void> legacySetLocalComicCover(LocalComic comic, String coverPath) {
  return LocalManager().setComicCover(comic, coverPath);
}

Future<void> legacyAddComicsAsLocalChapters(
  LocalComic comic,
  List<LocalComic> sources, {
  required bool deleteSourceComics,
}) {
  return LocalManager().addComicsAsChapters(
    comic,
    sources,
    deleteSourceComics: deleteSourceComics,
  );
}

void legacyReorderLocalComicChapters(
  LocalComic comic,
  List<String> chapterIds,
) {
  LocalManager().reorderComicChapters(comic, chapterIds);
}

void legacyRegisterLocalComic(LocalComic comic, String id) {
  LocalManager().add(comic, id);
}
