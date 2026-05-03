import 'dart:async' show Future;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/js/js_engine.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/network/images.dart';
import 'package:venera/utils/io.dart';
import 'base_image_provider.dart';
import 'reader_image.dart' as image_provider;
import 'package:venera/foundation/appdata.dart';

@visibleForTesting
String readerImageFilePathForTesting(String imageKey) {
  if (imageKey.startsWith('file://')) {
    return Uri.parse(imageKey).toFilePath();
  }
  return imageKey;
}

@visibleForTesting
String readerImageLoadContextForTesting({
  required String imageKey,
  String? sourceKey,
  String? canonicalComicId,
  String? upstreamComicRefId,
  String? chapterRefId,
  String? comicId,
  String? chapterId,
  required int page,
}) {
  final resolvedCanonicalComicRefId =
      canonicalComicId ?? comicId ?? '<unknown>';
  final resolvedUpstreamComicRefId =
      upstreamComicRefId ?? resolvedCanonicalComicRefId;
  final resolvedChapterRefId = chapterRefId ?? chapterId ?? '<unknown>';
  final buffer = StringBuffer(
    'imageKey=$imageKey canonicalComicId=$resolvedCanonicalComicRefId upstreamComicRefId=$resolvedUpstreamComicRefId chapterRefId=$resolvedChapterRefId page=$page',
  );
  if (sourceKey != null && sourceKey.isNotEmpty) {
    buffer.write(' sourceKey=$sourceKey');
  }
  return buffer.toString();
}

class ReaderImageProvider
    extends BaseImageProvider<image_provider.ReaderImageProvider> {
  /// Image provider for normal image.
  const ReaderImageProvider(
    this.imageKey,
    this.sourceRef,
    this.canonicalComicId,
    this.upstreamComicRefId,
    this.chapterRefId,
    this.page, {
    this.enableResize = false,
  });

  final String imageKey;

  final SourceRef sourceRef;

  final String canonicalComicId;

  final String upstreamComicRefId;

  final String chapterRefId;

  // Backward-compatible read-only aliases for legacy callsites.
  String get sourceKey => sourceRef.sourceKey;
  String get cid => canonicalComicId;
  String get eid => chapterRefId;

  final int page;

  @override
  final bool enableResize;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    Uint8List? imageBytes;
    final loadMode = imageKey.startsWith('file://') ? 'local' : 'remote';
    var localErrorCode = 'LOCAL_IMAGE_READ_FAILED';
    final diagnosticContext = readerImageLoadContextForTesting(
      imageKey: imageKey,
      sourceKey: sourceRef.sourceKey,
      canonicalComicId: canonicalComicId,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
      page: page,
    );
    final callId = ReaderDiagnostics.beginImageLoad(
      loadMode: loadMode,
      sourceKey: sourceRef.sourceKey,
      comicId: canonicalComicId,
      chapterId: chapterRefId,
      page: page,
      imageKey: imageKey,
    );
    try {
      if (imageKey.startsWith('file://')) {
        var file = File(readerImageFilePathForTesting(imageKey));
        if (await file.exists()) {
          imageBytes = await file.readAsBytes();
        } else {
          localErrorCode = 'LOCAL_PAGE_FILE_MISSING';
          throw "Error: File not found: ${file.path} ($diagnosticContext)";
        }
      } else {
        await for (var event in ImageDownloader.loadComicImage(
          imageKey,
          sourceRef,
          canonicalComicId,
          upstreamComicRefId,
          chapterRefId,
        )) {
          checkStop();
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: event.currentBytes,
              expectedTotalBytes: event.totalBytes,
            ),
          );
          if (event.imageBytes != null) {
            imageBytes = event.imageBytes;
            break;
          }
        }
      }
      if (imageBytes == null) {
        throw "Error: Empty response body. ($diagnosticContext)";
      }
      if (appdata.settings['enableCustomImageProcessing']) {
        var script = appdata.settings['customImageProcessing'].toString();
        if (!script.contains('function processImage')) {
          ReaderDiagnostics.endImageLoad(
            callId: callId,
            loadMode: loadMode,
            sourceKey: sourceRef.sourceKey,
            comicId: canonicalComicId,
            chapterId: chapterRefId,
            page: page,
            imageKey: imageKey,
            byteLength: imageBytes.length,
          );
          return imageBytes;
        }
        var func = JsEngine().runCode('''
        (() => {
          $script
          return processImage;
        })()
      ''');
        if (func is JSInvokable) {
          var autoFreeFunc = JSAutoFreeFunction(func);
          var result = autoFreeFunc([
            imageBytes,
            upstreamComicRefId,
            chapterRefId,
            page,
            sourceRef.sourceKey,
          ]);
          if (result is Uint8List) {
            imageBytes = result;
          } else if (result is Future) {
            var futureResult = await result;
            if (futureResult is Uint8List) {
              imageBytes = futureResult;
            }
          } else if (result is Map) {
            var image = result['image'];
            if (image is Uint8List) {
              imageBytes = image;
            } else if (image is Future) {
              JSAutoFreeFunction? onCancel;
              if (result['onCancel'] is JSInvokable) {
                onCancel = JSAutoFreeFunction(result['onCancel']);
              }
              if (onCancel == null) {
                var futureImage = await image;
                if (futureImage is Uint8List) {
                  imageBytes = futureImage;
                }
              } else {
                dynamic futureImage;
                image.then((value) {
                  futureImage = value;
                  futureImage ??= Uint8List(0);
                });
                while (futureImage == null) {
                  try {
                    checkStop();
                  } catch (e) {
                    onCancel([]);
                    rethrow;
                  }
                  await Future.delayed(Duration(milliseconds: 50));
                }
                if (futureImage is Uint8List) {
                  imageBytes = futureImage;
                }
              }
            }
          }
        }
      }
      final loadedBytes = imageBytes;
      if (loadedBytes == null) {
        throw "Error: Empty processed image body. ($diagnosticContext)";
      }
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: loadMode,
        sourceKey: sourceRef.sourceKey,
        comicId: canonicalComicId,
        chapterId: chapterRefId,
        page: page,
        imageKey: imageKey,
        byteLength: loadedBytes.length,
      );
      return loadedBytes;
    } catch (e, s) {
      if (loadMode == 'local') {
        AppDiagnostics.error(
          'reader.local',
          e,
          message: 'reader.local.render.blocked',
          data: {
            'code': localErrorCode,
            'loadMode': loadMode,
            'sourceKey': sourceRef.sourceKey,
            'comicId': canonicalComicId,
            'chapterId': chapterRefId,
            'page': page,
            'imageKey': imageKey,
          },
        );
      }
      ReaderDiagnostics.failImageLoad(
        callId: callId,
        loadMode: loadMode,
        sourceKey: sourceRef.sourceKey,
        comicId: canonicalComicId,
        chapterId: chapterRefId,
        page: page,
        imageKey: imageKey,
        error: e,
      );
      AppDiagnostics.error(
        'reader.image_provider',
        e,
        stackTrace: s,
        message: 'load_reader_image_failed',
        data: {'diagnosticContext': diagnosticContext.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  void onDecodeSuccess({required Uint8List data, required ui.Codec codec}) {
    ReaderDiagnostics.recordImageDecodeSuccess(
      imageKey: imageKey,
      sourceKey: sourceRef.sourceKey,
      comicId: canonicalComicId,
      chapterId: chapterRefId,
      page: page,
      byteLength: data.length,
    );
  }

  @override
  void onDecodeError({required Object error}) {
    ReaderDiagnostics.recordImageDecodeError(
      imageKey: imageKey,
      sourceKey: sourceRef.sourceKey,
      comicId: canonicalComicId,
      chapterId: chapterRefId,
      page: page,
      error: error,
    );
  }

  @override
  String get key =>
      "$imageKey@${sourceRef.sourceKey}@$canonicalComicId@$upstreamComicRefId@$chapterRefId@$enableResize";
}
