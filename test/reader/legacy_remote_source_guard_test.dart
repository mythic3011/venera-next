import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/reader/local_page_provider.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/pages/reader/reader.dart';

ComicSource _fakeSource({LoadComicPagesFunc? loadComicPages}) {
  return ComicSource(
    'Fake Source',
    'fake',
    null,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    null,
    loadComicPages,
    null,
    null,
    '/tmp/fake.js',
    'https://example.com',
    '1.0.0',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
  );
}

void main() {
  test(
    'unknown_prefix_key_returns_source_not_available_and_prevents_legacy_load',
    () async {
      var legacyLoadCalled = false;

      final guardError = resolveLegacyRemoteSourceUnavailableErrorForTesting(
        'Unknown:copymanga',
        findSource: (_) => _fakeSource(
          loadComicPages: (_, __) async {
            legacyLoadCalled = true;
            return const Res([]);
          },
        ),
      );

      if (guardError == null) {
        legacyLoadCalled = true;
      }

      expect(guardError, 'SOURCE_NOT_AVAILABLE:Unknown:copymanga');
      expect(legacyLoadCalled, isFalse);
    },
  );

  test(
    'missing_remote_source_returns_source_not_available_and_prevents_legacy_load',
    () async {
      var legacyLoadCalled = false;

      final guardError = resolveLegacyRemoteSourceUnavailableErrorForTesting(
        'missing-source',
        findSource: (_) => null,
      );

      if (guardError == null) {
        legacyLoadCalled = true;
      }

      expect(guardError, 'SOURCE_NOT_AVAILABLE:missing-source');
      expect(legacyLoadCalled, isFalse);
    },
  );

  test('null_and_empty_source_key_return_unknown_source_not_available', () {
    expect(
      resolveLegacyRemoteSourceUnavailableErrorForTesting(null),
      'SOURCE_NOT_AVAILABLE:<unknown>',
    );
    expect(
      resolveLegacyRemoteSourceUnavailableErrorForTesting(''),
      'SOURCE_NOT_AVAILABLE:<unknown>',
    );
  });

  test('visible_guard_message_includes_source_not_available_code', () {
    final guardError = resolveLegacyRemoteSourceUnavailableErrorForTesting(
      'missing-source',
      findSource: (_) => null,
    );

    expect(guardError, isNotNull);
    expect(guardError, contains('SOURCE_NOT_AVAILABLE:missing-source'));
  });

  test(
    'valid_remote_source_returns_null_and_legacy_load_can_proceed',
    () async {
      var legacyLoadCalled = false;
      final source = _fakeSource(
        loadComicPages: (_, __) async {
          legacyLoadCalled = true;
          return const Res(['p1']);
        },
      );

      final guardError = resolveLegacyRemoteSourceUnavailableErrorForTesting(
        'copymanga',
        findSource: (_) => source,
      );

      if (guardError == null) {
        await source.loadComicPages!('comic-1', 'ch-1');
      }

      expect(guardError, isNull);
      expect(legacyLoadCalled, isTrue);
    },
  );

  test(
    'resolver_enabled_behavior_remains_fail_closed_for_unknown_remote_source',
    () {
      final resolver = SourceRefResolver(
        localProvider: LocalPageProvider(
          loadLocalPages:
              ({required localType, required localComicId, chapterId}) async =>
                  ['local-page'],
        ),
        remoteProviderFactory: (_) =>
            throw StateError('remote provider should not be constructed'),
        sourceExists: (_) => false,
      );
      final ref = SourceRef.fromLegacyRemote(
        sourceKey: 'unknown-source',
        comicId: 'comic-1',
        chapterId: 'chapter-1',
      );

      expect(
        () => resolver.resolve(ref),
        throwsA(
          isA<SourceRefDiagnostic>().having(
            (e) => e.message,
            'message',
            'SOURCE_NOT_AVAILABLE',
          ),
        ),
      );
    },
  );

  test('local_path_behavior_remains_unchanged', () async {
    final provider = LocalPageProvider(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            return ['local-page-1'];
          },
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'chapter-1',
    );

    final res = await provider.loadPages(ref);
    expect(res.error, isFalse);
    expect(res.data, ['local-page-1']);
  });
}
