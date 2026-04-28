import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('direct_local_read_produces_sourceref_local_local_key', () {
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: null,
    );

    expect(ref.type, SourceRefType.local);
    expect(ref.sourceKey, 'local');
  });

  test('readerwithloading_legacy_sourcekey_maps_to_transient_sourceref', () {
    final localRef = SourceRef.fromLegacy(comicId: 'c1', sourceKey: 'local');
    final remoteRef = SourceRef.fromLegacy(
      comicId: 'c2',
      sourceKey: 'copymanga',
      chapterId: 'ch1',
    );

    expect(localRef.type, SourceRefType.local);
    expect(remoteRef.type, SourceRefType.remote);
    expect(remoteRef.sourceKey, 'copymanga');
  });

  test('unknown_remote_sourcekey_is_not_reinterpreted_as_local', () {
    final remoteRef = SourceRef.fromLegacy(
      comicId: 'c2',
      sourceKey: 'unknown-source',
    );

    expect(remoteRef.type, SourceRefType.remote);
    expect(remoteRef.sourceKey, 'unknown-source');
  });
}
