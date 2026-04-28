import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

class _SpyProvider implements ReadablePageProvider {
  int calls = 0;

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async {
    calls++;
    return const Res(['ok']);
  }
}

void main() {
  test('local_continue_reading_remains_local_with_linked_remote_source', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );

    final localResumeRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'series-1',
      chapterId: 'chapter-1',
    );

    await resolver.resolve(localResumeRef).loadPages(localResumeRef);

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('linked_remote_source_does_not_hijack_local_resume_dispatch', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );

    final localResumeRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'series-1',
      chapterId: 'chapter-1',
    );
    final linkedRemoteRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-1',
      chapterId: 'chapter-1',
    );

    // Simulate presence of remote link; resume still uses the local snapshot ref.
    expect(linkedRemoteRef.type, SourceRefType.remote);
    await resolver.resolve(localResumeRef).loadPages(localResumeRef);

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('remote_continue_reading_remains_remote_dispatch', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );

    final remoteResumeRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-2',
      chapterId: 'chapter-3',
    );

    await resolver.resolve(remoteResumeRef).loadPages(remoteResumeRef);

    expect(local.calls, 0);
    expect(remote.calls, 1);
  });
}
