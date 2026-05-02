import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/features/reader/presentation/reader.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test('file URI image keys normalize to readable local file paths', () {
    expect(readerImageFilePathForTesting('file:///tmp/a.jpg'), '/tmp/a.jpg');

    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/page.bin')..writeAsBytesSync([1, 2, 3]);
    final normalizedPath = readerImageFilePathForTesting('file://${file.path}');

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('file URI image key with spaces normalizes correctly', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/page with spaces.bin')
      ..writeAsBytesSync([1, 2, 3]);
    final uri = file.uri.toString();
    final normalizedPath = readerImageFilePathForTesting(uri);

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('file URI with absolute path normalizes to local path', () {
    expect(readerImageFilePathForTesting('file:///tmp/a.jpg'), '/tmp/a.jpg');
  });

  test('remote and relative image keys are not normalized as local paths', () {
    const httpsUrl = 'https://example.com/comic/page.jpg';
    const httpUrl = 'http://example.com/comic/page.jpg';
    const relativePath = 'images/page.jpg';

    expect(readerImageFilePathForTesting(httpsUrl), httpsUrl);
    expect(readerImageFilePathForTesting(httpUrl), httpUrl);
    expect(readerImageFilePathForTesting(relativePath), relativePath);
  });

  test('local produced key roundtrips through reader file path parsing', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_local_page_uri_key_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/中文 page 1.bin')
      ..writeAsBytesSync([7, 8, 9]);
    final imageKey = localPageImageKey(file);

    expect(imageKey, file.uri.toString());
    expect(readerImageFilePathForTesting(imageKey), file.path);
  });

  test('reader page local byte reads decode file URIs with spaces', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_page_bytes_space_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final expectedBytes = [1, 2, 3, 4];
    final file = File('${tempDir.path}/page with spaces.bin')
      ..writeAsBytesSync(expectedBytes);

    final bytes = await readReaderImageBytesForTesting(
      imageKey: file.uri.toString(),
      sourceKey: 'local',
      canonicalComicId: 'comic-space',
      upstreamComicRefId: 'comic-space',
      chapterRefId: 'chapter-1',
    );

    expect(bytes, expectedBytes);
  });

  test(
    'reader page local byte reads decode percent-encoded file URIs',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera_reader_page_bytes_percent_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final expectedBytes = [5, 6, 7, 8];
      final file = File('${tempDir.path}/chapter #1%20.bin')
        ..writeAsBytesSync(expectedBytes);
      final uri = Uri(
        scheme: 'file',
        pathSegments: [...file.uri.pathSegments],
      ).toString();

      final bytes = await readReaderImageBytesForTesting(
        imageKey: uri,
        sourceKey: 'local',
        canonicalComicId: 'comic-percent',
        upstreamComicRefId: 'comic-percent',
        chapterRefId: 'chapter-2',
      );

      expect(bytes, expectedBytes);
    },
  );

  test('reader page local byte reads decode non-ascii file URIs', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_page_bytes_unicode_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final expectedBytes = [9, 10, 11, 12];
    final file = File('${tempDir.path}/中文 圖像.bin')
      ..writeAsBytesSync(expectedBytes);

    final bytes = await readReaderImageBytesForTesting(
      imageKey: file.uri.toString(),
      sourceKey: 'local',
      canonicalComicId: 'comic-unicode',
      upstreamComicRefId: 'comic-unicode',
      chapterRefId: 'chapter-3',
    );

    expect(bytes, expectedBytes);
  });

  test('missing local page emits typed render blocked diagnostic', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_page_missing_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final missing = File('${tempDir.path}/missing page.bin');

    await expectLater(
      () => readReaderImageBytesForTesting(
        imageKey: missing.uri.toString(),
        sourceKey: 'local',
        canonicalComicId: 'comic-missing',
        upstreamComicRefId: 'comic-missing',
        chapterRefId: 'chapter-missing',
      ),
      throwsA(isA<FileSystemException>()),
    );

    final event = DevDiagnosticsApi.recent(
      channel: 'reader.render',
    ).singleWhere((event) => event.message == 'reader.render.blocked');
    expect(event.data['code'], 'LOCAL_IMAGE_READ_FAILED');
    expect(event.data['fileName'], 'missing page.bin');
  });

  test(
    'remote cache miss emits structured render blocked diagnostic',
    () async {
      await expectLater(
        () => readReaderImageBytesForTesting(
          imageKey: 'https://example.com/page-miss.jpg',
          sourceKey: 'copymanga',
          canonicalComicId: 'remote:copymanga:comic-miss',
          upstreamComicRefId: 'comic-miss',
          chapterRefId: 'chapter-miss',
          findCache: (_) async => null,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('IMAGE_CACHE_MISS'),
          ),
        ),
      );

      final event = DevDiagnosticsApi.recent(
        channel: 'reader.render',
      ).singleWhere((event) => event.message == 'reader.render.blocked');
      expect(event.data['code'], 'IMAGE_CACHE_MISS');
      expect(event.data['loadMode'], 'remote');
      expect(event.data['sourceKey'], 'copymanga');
      expect(event.data['upstreamComicRefId'], 'comic-miss');
    },
  );
}
