import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/foundation/sources/source_ref.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    ReaderDiagnostics.clearPendingProviderSubscriptionsForTesting();
    AppDiagnostics.resetForTesting();
  });

  tearDownAll(() {
    final file = File('/tmp/reader-load-visibility-1x1.png');
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  test('build_reader_image_provider_keeps_requested_page', () {
    final provider = buildReaderImageProvider(
      imageKey: 'https://example.com/page-3.jpg',
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-9',
        chapterId: 'ep-5',
      ),
      canonicalComicId: 'remote:copymanga:comic-9',
      upstreamComicRefId: 'comic-9',
      chapterRefId: 'ep-5',
      page: 3,
      enableResize: true,
    );

    expect(provider.page, 3);
    expect(provider.enableResize, isTrue);
  });

  test('reader image provider emits local page terminal diagnostics', () {
    buildReaderImageProvider(
      imageKey: 'file:///tmp/page-1.jpg',
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-1',
        chapterId: 'comic-1:__imported__',
      ),
      canonicalComicId: 'comic-1',
      upstreamComicRefId: 'comic-1',
      chapterRefId: 'comic-1:__imported__',
      page: 1,
      enableResize: true,
    );

    final event = DevDiagnosticsApi.recent(
      channel: 'reader.render',
    ).singleWhere((event) => event.message == 'reader.render.page.attached');
    expect(event.data['page'], 1);
    expect(event.data['chapterId'], 'comic-1:__imported__');
    final providerCreated = DevDiagnosticsApi.recent(channel: 'reader.render')
        .singleWhere(
          (event) => event.message == 'reader.render.page.provider.created',
        );
    expect(providerCreated.data['loadMode'], 'local');
    expect(providerCreated.data['imageKey'], 'file:///tmp/page-1.jpg');
  });

  test('reader image provider emits remote page terminal diagnostics', () {
    buildReaderImageProvider(
      imageKey: 'https://example.com/page-3.jpg',
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-9',
        chapterId: 'ep-5',
      ),
      canonicalComicId: 'remote:copymanga:comic-9',
      upstreamComicRefId: 'comic-9',
      chapterRefId: 'ep-5',
      page: 3,
      enableResize: true,
    );

    final messages = DevDiagnosticsApi.recent(
      channel: 'reader.render',
    ).map((event) => event.message);
    expect(messages, contains('reader.render.page.attached'));
    expect(messages, contains('reader.render.page.provider.created'));
    final providerCreated = DevDiagnosticsApi.recent(channel: 'reader.render')
        .singleWhere(
          (event) => event.message == 'reader.render.page.provider.created',
        );
    expect(providerCreated.data['loadMode'], 'remote');
    expect(providerCreated.data['imageKey'], 'https://example.com/page-3.jpg');
  });

  test(
    'reader emits render terminal diagnostic after page provider is created',
    () {
      buildReaderImageProvider(
        imageKey: 'https://example.com/page-terminal.jpg',
        sourceRef: SourceRef.fromLegacyRemote(
          sourceKey: 'copymanga',
          comicId: 'comic-9',
          chapterId: 'ep-5',
        ),
        canonicalComicId: 'remote:copymanga:comic-9',
        upstreamComicRefId: 'comic-9',
        chapterRefId: 'ep-5',
        page: 4,
        enableResize: true,
      );

      final messages = DevDiagnosticsApi.recent(
        channel: 'reader.render',
      ).map((event) => event.message).toList(growable: false);
      expect(messages, contains('reader.render.page.provider.created'));
      expect(messages, contains('reader.render.provider.created'));
    },
  );

  testWidgets(
    'reader emits provider not subscribed when provider is genuinely never listened to',
    (tester) async {
      ReaderDiagnostics.markImageProviderAwaitingSubscription(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-local',
        chapterId: 'comic-local:__imported__',
        page: 1,
        imageKey: 'file:///tmp/local-unsubscribed-page.jpg',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 55));
      final emitted = ReaderDiagnostics.recordProviderNotSubscribedIfPending(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-local',
        chapterId: 'comic-local:__imported__',
        page: 1,
        imageKey: 'file:///tmp/local-unsubscribed-page.jpg',
        owner: 'reader.render.postFrame',
      );

      final events = DevDiagnosticsApi.recent(channel: 'reader.render');
      expect(emitted, isTrue);
      expect(
        events.where(
          (event) => event.message == 'reader.render.provider.notSubscribed',
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'reader suppresses immediate notSubscribed when pageAttached exists without load yet',
    (tester) async {
      buildReaderImageProvider(
        imageKey: 'file:///tmp/local-attached-no-load-yet.jpg',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-local',
          chapterId: 'comic-local:__imported__',
        ),
        canonicalComicId: 'comic-local',
        upstreamComicRefId: 'comic-local',
        chapterRefId: 'comic-local:__imported__',
        page: 2,
        enableResize: false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 60));

      final events = DevDiagnosticsApi.recent(channel: 'reader.render');
      expect(
        events.where(
          (event) => event.message == 'reader.render.provider.notSubscribed',
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'reader does not emit provider not subscribed for normal subscribed render path',
    (tester) async {
      final file = File('/tmp/reader-load-visibility-1x1.png');
      file.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=',
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ComicImage(
            image: buildReaderImageProvider(
              imageKey: file.uri.toString(),
              sourceRef: SourceRef.fromLegacyLocal(
                localType: 'local',
                localComicId: 'comic-local',
                chapterId: 'comic-local:__imported__',
              ),
              canonicalComicId: 'comic-local',
              upstreamComicRefId: 'comic-local',
              chapterRefId: 'comic-local:__imported__',
              page: 1,
              enableResize: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final events = DevDiagnosticsApi.recent(channel: 'reader.render');
      expect(
        events.where(
          (event) => event.message == 'reader.render.provider.notSubscribed',
        ),
        isEmpty,
      );
      expect(
        events.where(
          (event) => event.message == 'reader.render.provider.created',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'reader local load success is followed by provider-created diagnostic',
    () {
      buildReaderImageProvider(
        imageKey: 'file:///tmp/local-success-page.jpg',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-local',
          chapterId: 'comic-local:__imported__',
        ),
        canonicalComicId: 'comic-local',
        upstreamComicRefId: 'comic-local',
        chapterRefId: 'comic-local:__imported__',
        page: 1,
        enableResize: false,
      );

      final providerCreated = DevDiagnosticsApi.recent(channel: 'reader.render')
          .singleWhere(
            (event) => event.message == 'reader.render.provider.created',
          );
      expect(providerCreated.data['loadMode'], 'local');
      expect(
        providerCreated.data['imageKey'],
        'file:///tmp/local-success-page.jpg',
      );
    },
  );

  test('reader image diagnostics include comic chapter and source context', () {
    final context = readerImageLoadContextForTesting(
      imageKey: 'https://example.com/page-3.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-9',
      chapterId: 'ep-5',
      page: 3,
    );

    expect(
      context,
      'imageKey=https://example.com/page-3.jpg canonicalComicId=comic-9 upstreamComicRefId=comic-9 chapterRefId=ep-5 page=3 sourceKey=copymanga',
    );
  });

  test('empty local page list surfaces diagnostic with chapter context', () {
    final error = resolveReaderEmptyPageListError(
      images: const [],
      loadMode: 'local',
      comicId: 'comic-1',
      chapterIndex: 2,
      chapterId: 'ch-2',
      sourceKey: 'local',
    );

    expect(
      error,
      'EMPTY_PAGE_LIST: loadMode=local canonicalComicRefId=comic-1 chapterIndex=2 chapterId=ch-2 sourceKey=local',
    );
  });

  test('empty remote page list surfaces diagnostic with source key', () {
    final error = resolveReaderEmptyPageListError(
      images: const [],
      loadMode: 'remote',
      comicId: 'comic-9',
      chapterIndex: 5,
      chapterId: 'ep-5',
      sourceKey: 'copymanga',
    );

    expect(
      error,
      'EMPTY_PAGE_LIST: loadMode=remote canonicalComicRefId=comic-9 chapterIndex=5 chapterId=ep-5 sourceKey=copymanga',
    );
  });

  test('non-empty page list does not surface error', () {
    final error = resolveReaderEmptyPageListError(
      images: const ['p1'],
      loadMode: 'remote',
      comicId: 'comic-9',
      chapterIndex: 5,
      chapterId: 'ep-5',
      sourceKey: 'copymanga',
    );

    expect(error, isNull);
  });

  test('source unavailable errors include suffixed source diagnostics', () {
    expect(
      isReaderSourceUnavailableErrorForTesting('SOURCE_NOT_AVAILABLE'),
      isTrue,
    );
    expect(
      isReaderSourceUnavailableErrorForTesting(
        'SOURCE_NOT_AVAILABLE:Unknown:122396838',
      ),
      isTrue,
    );
    expect(
      isReaderSourceUnavailableErrorForTesting('LOCAL_ASSET_MISSING'),
      isFalse,
    );
  });

  test('unknown reader type falls back to local when local comic exists', () {
    final shouldLoadLocal = shouldLoadReaderPagesLocallyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: '1',
      isDownloaded: (_, _) => false,
      hasLocalComic: (comicId) => comicId == '1',
    );
    final localTypeKey = readerLocalTypeKeyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: '1',
      hasLocalComic: (comicId) => comicId == '1',
    );

    expect(shouldLoadLocal, isTrue);
    expect(localTypeKey, 'local');
  });

  test('unknown reader type stays remote when no local comic exists', () {
    final shouldLoadLocal = shouldLoadReaderPagesLocallyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: 'missing',
      isDownloaded: (_, _) => false,
      hasLocalComic: (_) => false,
    );

    expect(shouldLoadLocal, isFalse);
  });
}
