import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader_next/runtime/local_resolver.dart';
import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/utils/io.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  group('LegacyLocalReaderPageResolver', () {
    test('maps missing canonical comic to LOCAL_COMIC_NOT_FOUND', () async {
      final resolver = LegacyLocalReaderPageResolver(
        loadCanonicalPages: (_, __) async {
          throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:comic-1');
        },
      );
      final identity = ComicIdentity(
        canonicalComicId: 'local:comic-1',
        sourceRef: SourceRef.local(
          sourceKey: 'local',
          comicRefId: 'comic-1',
          chapterRefId: '1',
        ),
      );

      await expectLater(
        () => resolver.loadReaderPageImages(
          identity: identity,
          chapterRefId: '1',
          page: 1,
        ),
        throwsA(
          isA<ReaderRuntimeException>().having(
            (e) => e.code,
            'code',
            'LOCAL_COMIC_NOT_FOUND',
          ),
        ),
      );
    });

    test(
      'local resolver throws LOCAL_PAGE_FILE_MISSING when page file is absent',
      () async {
        final resolver = LegacyLocalReaderPageResolver(
          loadCanonicalPages: (_, __) async => <String>[
            '/tmp/definitely-missing-reader-next-image.jpg',
          ],
        );
        final identity = ComicIdentity(
          canonicalComicId: 'local:comic-1',
          sourceRef: SourceRef.local(
            sourceKey: 'local',
            comicRefId: 'comic-1',
            chapterRefId: '1',
          ),
        );

        await expectLater(
          () => resolver.loadReaderPageImages(
            identity: identity,
            chapterRefId: '1',
            page: 1,
          ),
          throwsA(
            isA<ReaderRuntimeException>().having(
              (e) => e.code,
              'code',
              'LOCAL_PAGE_FILE_MISSING',
            ),
          ),
        );
        final events = DevDiagnosticsApi.recent(channel: 'reader.local');
        expect(
          events.map((event) => event.message),
          containsAll(<String>[
            'reader.local.resolve.start',
            'reader.local.pageUri.missing',
            'reader.local.render.blocked',
          ]),
        );
      },
    );

    test(
      'local resolver returns renderable local file path when file exists',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'reader-next-local-resolver-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File(FilePath.join(tempDir.path, 'page-1.jpg'));
        file.writeAsBytesSync(<int>[0, 1, 2, 3]);

        final resolver = LegacyLocalReaderPageResolver(
          loadCanonicalPages: (_, __) async => <String>[file.path],
        );
        final identity = ComicIdentity(
          canonicalComicId: 'local:comic-1',
          sourceRef: SourceRef.local(
            sourceKey: 'local',
            comicRefId: 'comic-1',
            chapterRefId: '1',
          ),
        );

        final refs = await resolver.loadReaderPageImages(
          identity: identity,
          chapterRefId: '1',
          page: 1,
        );

        expect(refs, hasLength(1));
        expect(refs.first.imageUrl, file.path);
      },
    );

    test(
      'local imported chapter resolves first actual file and emits terminal result',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'reader-next-local-imported-resolver-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final first = File(FilePath.join(tempDir.path, '001.jpg'))
          ..writeAsBytesSync(<int>[1]);
        final second = File(FilePath.join(tempDir.path, '002.jpg'))
          ..writeAsBytesSync(<int>[2]);

        final resolver = LegacyLocalReaderPageResolver(
          loadCanonicalPages: (_, __) async => <String>[
            first.path,
            second.path,
          ],
        );
        final identity = ComicIdentity(
          canonicalComicId: 'local:1',
          sourceRef: SourceRef.local(
            sourceKey: 'local',
            comicRefId: '1',
            chapterRefId: '1:__imported__',
          ),
        );

        final refs = await resolver.loadReaderPageImages(
          identity: identity,
          chapterRefId: '1:__imported__',
          page: 1,
        );

        expect(refs, hasLength(2));
        expect(refs.first.imageUrl, first.path);
        final result = DevDiagnosticsApi.recent(channel: 'reader.local')
            .singleWhere(
              (event) => event.message == 'reader.local.resolve.result',
            );
        expect(result.data['pageCount'], 2);
        expect(result.data['firstImageKey'], 'local:1:__imported__:0');
        expect(result.data['firstPageUriScheme'], 'file');
      },
    );
  });
}
