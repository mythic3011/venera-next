import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:venera/foundation/db/unified_comics_store.dart'
    show PageRecord, UnifiedComicSnapshot;
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/sources/identity/constants.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/utils/io.dart';

enum LocalReaderRuntimeFailureCode {
  invalidInput,
  localComicNotFound,
  defaultChapterMissingPages,
  pageOutOfRange,
  imageReadFailed,
  decodeFailed,
  sessionPersistFailed,
}

class LocalReaderRuntimeFailure {
  const LocalReaderRuntimeFailure({
    required this.code,
    required this.message,
    required this.diagnostic,
  });

  final LocalReaderRuntimeFailureCode code;
  final String message;
  final String diagnostic;
}

class LocalReaderRuntimeInput {
  const LocalReaderRuntimeInput({
    required this.comicId,
    required this.sourceKey,
    required this.loadMode,
    this.chapterId,
    this.page,
  });

  final String comicId;
  final String sourceKey;
  final String loadMode;
  final String? chapterId;
  final int? page;
}

class LocalReaderRuntimeTarget {
  const LocalReaderRuntimeTarget({
    required this.comicId,
    required this.chapterId,
    required this.sourceRef,
    required this.sourceRefId,
    required this.sourceKey,
    required this.loadMode,
    required this.page,
  });

  final String comicId;
  final String chapterId;
  final SourceRef sourceRef;
  final String sourceRefId;
  final String sourceKey;
  final String loadMode;
  final int page;
}

class LocalReaderPageEntry {
  const LocalReaderPageEntry({required this.imageKey, required this.imageUrl});

  final String imageKey;
  final String imageUrl;
}

class LocalReaderSessionPersistOutcome {
  const LocalReaderSessionPersistOutcome({
    required this.written,
    this.skipReason,
  });

  final bool written;
  final String? skipReason;
}

sealed class LocalReaderRuntimeOpenResult {
  const LocalReaderRuntimeOpenResult();
}

class LocalReaderRuntimeOpenSuccess extends LocalReaderRuntimeOpenResult {
  const LocalReaderRuntimeOpenSuccess({
    required this.target,
    required this.pageList,
    required this.firstPage,
    required this.firstPageBytes,
    required this.sessionPersist,
    required this.pageOrderId,
  });

  final LocalReaderRuntimeTarget target;
  final List<LocalReaderPageEntry> pageList;
  final LocalReaderPageEntry firstPage;
  final Uint8List firstPageBytes;
  final LocalReaderSessionPersistOutcome sessionPersist;
  final String? pageOrderId;
}

class LocalReaderRuntimeOpenFailure extends LocalReaderRuntimeOpenResult {
  const LocalReaderRuntimeOpenFailure({required this.error, this.target});

  final LocalReaderRuntimeFailure error;
  final LocalReaderRuntimeTarget? target;
}

abstract interface class LocalReaderSessionWriter {
  Future<LocalReaderSessionPersistOutcome> persist({
    required String comicId,
    required String chapterId,
    required int page,
    required SourceRef sourceRef,
    String? pageOrderId,
  });
}

typedef DecodeLocalReaderImage = Future<void> Function(Uint8List bytes);
typedef ReadLocalReaderImageBytes = Future<Uint8List> Function(String imageUrl);

class LocalReaderRuntimeSmokeService {
  const LocalReaderRuntimeSmokeService({
    required this.store,
    required this.sessionWriter,
    this.decodeFirstPage,
    this.readImageBytes,
  });

  final ComicDetailStorePort store;
  final LocalReaderSessionWriter sessionWriter;
  final DecodeLocalReaderImage? decodeFirstPage;
  final ReadLocalReaderImageBytes? readImageBytes;

  Future<LocalReaderRuntimeOpenResult> open(
    LocalReaderRuntimeInput input,
  ) async {
    final normalizedComicId = input.comicId.trim();
    final normalizedChapterId = input.chapterId?.trim().isNotEmpty == true
        ? input.chapterId!.trim()
        : '$normalizedComicId:__imported__';
    final initialPage = input.page ?? 1;
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: localSourceKey,
      localComicId: normalizedComicId,
      chapterId: normalizedChapterId,
    );
    final target = LocalReaderRuntimeTarget(
      comicId: normalizedComicId,
      chapterId: normalizedChapterId,
      sourceRef: sourceRef,
      sourceRefId: sourceRef.id,
      sourceKey: sourceRef.sourceKey,
      loadMode: input.loadMode,
      page: initialPage,
    );

    final validationError = _validateInput(input, target);
    if (validationError != null) {
      return validationError;
    }

    List<String> pageUrls;
    try {
      pageUrls = await _loadLocalPages(
        localComicId: normalizedComicId,
        chapterId: normalizedChapterId,
      );
    } catch (error) {
      return _mapCanonicalPageLoadFailure(error, target);
    }

    if (pageUrls.isEmpty) {
      return _missingPagesFailure(target);
    }

    final pageList = List<LocalReaderPageEntry>.generate(pageUrls.length, (
      index,
    ) {
      return LocalReaderPageEntry(
        imageKey: 'local:$normalizedChapterId:$index',
        imageUrl: pageUrls[index],
      );
    }, growable: false);

    if (initialPage < 1 || initialPage > pageList.length) {
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.pageOutOfRange,
          message: 'Requested page is outside the available local page list.',
          diagnostic: 'reader.local.page.out_of_range',
        ),
        target: target,
      );
    }

    final firstPage = pageList[initialPage - 1];
    Uint8List firstPageBytes;
    try {
      firstPageBytes = await (readImageBytes ?? _readImageBytes).call(
        firstPage.imageUrl,
      );
    } catch (error) {
      AppDiagnostics.error(
        'reader.local',
        error,
        message: 'reader.local.page.read_failed',
        data: _targetData(target, imageKey: firstPage.imageKey),
      );
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.imageReadFailed,
          message: 'Failed to read the first local reader page.',
          diagnostic: 'reader.local.page.read_failed',
        ),
        target: target,
      );
    }

    try {
      await decodeFirstPage?.call(firstPageBytes);
      AppDiagnostics.trace(
        'reader.decode',
        'image.decode.success',
        data: <String, Object?>{
          'sourceKey': sourceRef.sourceKey,
          'comicId': normalizedComicId,
          'chapterId': normalizedChapterId,
          'page': initialPage,
          'imageKey': firstPage.imageUrl,
          'byteLength': firstPageBytes.length,
        },
      );
    } catch (error) {
      AppDiagnostics.error(
        'reader.decode',
        error,
        message: 'image.decode.error',
        data: <String, Object?>{
          'sourceKey': sourceRef.sourceKey,
          'comicId': normalizedComicId,
          'chapterId': normalizedChapterId,
          'page': initialPage,
          'imageKey': firstPage.imageUrl,
        },
      );
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.decodeFailed,
          message: 'Failed to decode the first local reader page.',
          diagnostic: 'reader.local.decode_failed',
        ),
        target: target,
      );
    }

    final pageOrder = await store.loadActivePageOrderForChapter(
      normalizedChapterId,
    );
    try {
      final sessionPersist = await sessionWriter.persist(
        comicId: normalizedComicId,
        chapterId: normalizedChapterId,
        page: initialPage,
        sourceRef: sourceRef,
        pageOrderId: pageOrder?.id,
      );
      AppDiagnostics.info(
        'reader.local',
        'reader.local.runtime.success',
        data: {
          ..._targetData(
            target,
            pageCount: pageList.length,
            imageKey: firstPage.imageKey,
          ),
          'pageOrderId': pageOrder?.id,
          'sessionWritten': sessionPersist.written,
          'sessionSkipReason': sessionPersist.skipReason,
        },
      );
      return LocalReaderRuntimeOpenSuccess(
        target: target,
        pageList: pageList,
        firstPage: firstPage,
        firstPageBytes: firstPageBytes,
        sessionPersist: sessionPersist,
        pageOrderId: pageOrder?.id,
      );
    } catch (error) {
      AppDiagnostics.error(
        'reader.local',
        error,
        message: 'reader.local.session.persist_failed',
        data: _targetData(target, pageOrderId: pageOrder?.id),
      );
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.sessionPersistFailed,
          message: 'Failed to persist canonical reader session state.',
          diagnostic: 'reader.local.session.persist_failed',
        ),
        target: target,
      );
    }
  }

  LocalReaderRuntimeOpenFailure? _validateInput(
    LocalReaderRuntimeInput input,
    LocalReaderRuntimeTarget target,
  ) {
    if (target.comicId.isEmpty ||
        input.sourceKey.trim() != localSourceKey ||
        input.loadMode.trim() != 'local' ||
        target.page < 1 ||
        target.sourceRefId.endsWith(':_')) {
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.invalidInput,
          message:
              'Local runtime input must resolve to canonical local reader target.',
          diagnostic: 'reader.local.runtime.invalid_input',
        ),
        target: target,
      );
    }
    return null;
  }

  LocalReaderRuntimeOpenFailure _mapCanonicalPageLoadFailure(
    Object error,
    LocalReaderRuntimeTarget target,
  ) {
    final text = error.toString();
    if (text.contains('CANONICAL_LOCAL_COMIC_NOT_FOUND')) {
      return LocalReaderRuntimeOpenFailure(
        error: const LocalReaderRuntimeFailure(
          code: LocalReaderRuntimeFailureCode.localComicNotFound,
          message: 'Canonical local comic was not found.',
          diagnostic: 'reader.local.comic.not_found',
        ),
        target: target,
      );
    }
    if (text.contains('CANONICAL_PAGE_ORDER_NOT_FOUND') ||
        text.contains('CANONICAL_CHAPTER_NOT_FOUND')) {
      return _missingPagesFailure(target);
    }
    return LocalReaderRuntimeOpenFailure(
      error: LocalReaderRuntimeFailure(
        code: LocalReaderRuntimeFailureCode.imageReadFailed,
        message: text,
        diagnostic: 'reader.local.runtime.unexpected_error',
      ),
      target: target,
    );
  }

  LocalReaderRuntimeOpenFailure _missingPagesFailure(
    LocalReaderRuntimeTarget target,
  ) {
    AppDiagnostics.warn(
      'reader.local',
      'reader.local.default_chapter.missing_pages',
      data: _targetData(target),
    );
    return const LocalReaderRuntimeOpenFailure(
      error: LocalReaderRuntimeFailure(
        code: LocalReaderRuntimeFailureCode.defaultChapterMissingPages,
        message: 'Local imported reader default chapter has no readable pages.',
        diagnostic: 'reader.local.default_chapter.missing_pages',
      ),
    ).copyWithTarget(target);
  }

  Future<List<String>> _loadLocalPages({
    required String localComicId,
    required String chapterId,
  }) async {
    final snapshot = await store.loadComicSnapshot(localComicId);
    if (snapshot == null || snapshot.localLibraryItems.isEmpty) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$localComicId');
    }
    final pages = await _loadActivePages(chapterId: chapterId);
    if (pages.isEmpty) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$chapterId');
    }
    return pages.map((page) => Uri.file(page.localPath).toString()).toList();
  }

  Future<List<PageRecord>> _loadActivePages({required String chapterId}) async {
    final snapshot = await store.loadComicSnapshot(
      _comicIdFromChapter(chapterId),
    );
    if (snapshot == null) {
      return const <PageRecord>[];
    }
    final targetChapterId = _resolveChapterId(
      snapshot: snapshot,
      requestedChapterId: chapterId,
    );
    return store.loadActivePageOrderPages(targetChapterId);
  }

  String _resolveChapterId({
    required UnifiedComicSnapshot snapshot,
    required String requestedChapterId,
  }) {
    if (requestedChapterId.isNotEmpty) {
      return requestedChapterId;
    }
    if (snapshot.chapters.isNotEmpty) {
      return snapshot.chapters.first.id;
    }
    return '${snapshot.comic.id}:__imported__';
  }

  String _comicIdFromChapter(String chapterId) {
    final index = chapterId.indexOf(':');
    if (index <= 0) {
      return chapterId;
    }
    return chapterId.substring(0, index);
  }

  Map<String, Object?> _targetData(
    LocalReaderRuntimeTarget target, {
    int? pageCount,
    String? imageKey,
    String? pageOrderId,
  }) {
    return <String, Object?>{
      'comicId': target.comicId,
      'chapterId': target.chapterId,
      'sourceKey': target.sourceKey,
      'sourceRefId': target.sourceRefId,
      'loadMode': target.loadMode,
      'page': target.page,
      if (pageCount != null) 'pageCount': pageCount,
      if (imageKey != null) 'imageKey': imageKey,
      if (pageOrderId != null) 'pageOrderId': pageOrderId,
    };
  }
}

extension on LocalReaderRuntimeOpenFailure {
  LocalReaderRuntimeOpenFailure copyWithTarget(
    LocalReaderRuntimeTarget target,
  ) {
    return LocalReaderRuntimeOpenFailure(error: error, target: target);
  }
}

@visibleForTesting
Future<Uint8List> readLocalReaderImageBytesForTesting(String imageUrl) {
  return _readImageBytes(imageUrl);
}

Future<Uint8List> _readImageBytes(String imageUrl) async {
  final path = imageUrl.startsWith('file://')
      ? Uri.parse(imageUrl).toFilePath()
      : imageUrl;
  return Uint8List.fromList(await File(path).readAsBytes());
}
