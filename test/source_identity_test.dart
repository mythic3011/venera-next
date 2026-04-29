import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/network/download.dart';

ComicSource _fakeSource(String key, {SourceIdentity? identity}) {
  return ComicSource(
    'Fake Source',
    key,
    null,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '/tmp/$key.js',
    'https://example.com/$key',
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
    identity: identity,
  );
}

void main() {
  test('stable source key ids are deterministic and reserve local as zero', () {
    expect(stableSourceKeyId('nhentai'), stableSourceKeyId('nhentai'));
    expect(stableSourceKeyId(localSourceKey), 0);
    expect(sourceTypeValueFromKey(localSourceKey), 0);
  });

  test('unknown source key preserves embedded integer type value', () {
    expect(parseUnknownSourceTypeValue('Unknown:122396838'), 122396838);
    expect(sourceTypeValueFromKey('Unknown:122396838'), 122396838);
    expect(sourceKeyFromTypeValue(122396838), 'Unknown:122396838');
  });

  test('legacy favorite and history type values normalize to stable ids', () {
    expect(legacySourceTypeSourceKeys[5], 'nhentai');
    expect(legacySourceTypeSourceKeys[6], 'nhentai');
    expect(
      normalizeFavoriteJsonTypeValue(
        typeValue: 4,
        coverPath: 'https://example.com/cover.jpg',
      ),
      ComicType.fromKey('wnacg').value,
    );
    expect(
      normalizeLegacyHistoryTypeValue(5),
      ComicType.fromKey('nhentai').value,
    );
  });

  test('legacy imported source key normalizes htmanga to wnacg', () {
    expect(normalizeLegacyImportedSourceKey('htmanga'), 'wnacg');
    expect(normalizeLegacyImportedSourceKey('HtManga'), 'wnacg');
    expect(normalizeLegacyImportedSourceKey('copymanga'), 'copymanga');
  });

  test('global source type normalization uses resolver canonical keys', () {
    expect(sourceTypeValueFromKey('pica'), sourceTypeValueFromKey('picacg'));
    expect(sourceTypeValueFromKey('nh'), sourceTypeValueFromKey('nhentai'));
    expect(sourceTypeValueFromKey('htmanga'), stableSourceKeyId('htmanga'));
  });

  test('compatibility matcher accepts stable id and legacy hash code', () {
    final stable = ComicType.fromKey('copymanga').value;

    expect(
      matchesSourceTypeValue(sourceKey: 'copymanga', typeValue: stable),
      isTrue,
    );
    expect(
      matchesSourceTypeValue(
        sourceKey: 'copymanga',
        typeValue: 'copymanga'.hashCode,
      ),
      isTrue,
    );
  });

  test('comic source int lookup resolves stable and legacy hash values', () {
    final source = _fakeSource('source-identity-test');
    final manager = ComicSourceManager();
    manager.add(source);
    addTearDown(() => manager.remove(source.key));

    expect(ComicSource.fromIntKey(source.intKey)?.key, source.key);
    expect(ComicSource.fromIntKey(source.key.hashCode)?.key, source.key);
  });

  test('source identity schema round-trips with aliases version and audit', () {
    final identity = SourceIdentity.legacy(
      key: 'copymanga_v2',
      id: 'copymanga',
      kind: webdavSourceKind,
      aliases: const ['copymanga', 'copy_manga'],
      names: const ['CopyManga', '拷贝漫画'],
      version: '2.0.0',
      audit: const SourceIdentityAudit(
        source: 'test',
        loadedFrom: '/tmp/source.js',
        declaredVersion: '2.0.0',
      ),
    );

    final decoded = SourceIdentity.fromJson(identity.toJson());
    expect(decoded.schema, sourceIdentitySchemaVersion);
    expect(decoded.id, 'copymanga');
    expect(decoded.kind, webdavSourceKind);
    expect(decoded.matchesKey('copy_manga'), isTrue);
    expect(decoded.version, '2.0.0');
    expect(decoded.audit?.loadedFrom, '/tmp/source.js');
  });

  test(
    'source identity adopts resolver canonical id for known legacy keys',
    () {
      final identity = sourceIdentityFromKey('pica');

      expect(identity.id, 'picacg');
      expect(identity.kind, remoteSourceKind);
      expect(identity.knownKeys, contains('picacg'));
    },
  );

  test(
    'source identity type value remains stable when runtime key is renamed',
    () {
      final source = _fakeSource(
        'copymanga_v2',
        identity: SourceIdentity.legacy(
          key: 'copymanga_v2',
          id: 'copymanga',
          aliases: const ['copymanga_old'],
          version: '2.0.0',
        ),
      );
      final manager = ComicSourceManager();
      manager.add(source);
      addTearDown(() => manager.remove(source.key));

      expect(source.intKey, ComicType.fromKey('copymanga').value);
      expect(
        ComicSource.fromIntKey(ComicType.fromKey('copymanga').value)?.key,
        'copymanga_v2',
      );
      expect(ComicSource.find('copymanga_old')?.key, 'copymanga_v2');
    },
  );

  test('favorite item legacy json type uses stable source identity value', () {
    final favorite = FavoriteItem.fromJson({
      'type': 6,
      'id': 'comic-1',
      'name': 'Test',
      'author': 'Author',
      'coverPath': 'https://example.com/cover.jpg',
      'tags': <String>[],
    });

    expect(favorite.type, ComicType.fromKey('nhentai'));
  });

  test('download task comic type uses stable source identity value', () {
    final source = _fakeSource('download-test');
    final task = ImagesDownloadTask(
      source: source,
      comicId: 'comic-1',
      comic: null,
      chapters: null,
    );

    expect(task.comicType, ComicType.fromKey(source.key));
  });
}
