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

Future<Res<List<String>>> _dispatch({
  required bool flag,
  required SourceRef ref,
  required Future<Res<List<String>>> Function() legacy,
  required SourceRefResolver resolver,
}) async {
  if (!flag) {
    return legacy();
  }
  return resolver.resolve(ref).loadPages(ref);
}

void main() {
  test('flag_off_uses_legacy_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      flag: false,
      ref: ref,
      legacy: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      resolver: resolver,
    );

    expect(legacyCalls, 1);
    expect(local.calls, 0);
    expect(remote.calls, 0);
  });

  test('flag_on_uses_resolver_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      flag: true,
      ref: ref,
      legacy: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      resolver: resolver,
    );

    expect(legacyCalls, 0);
    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_local_ref_never_calls_remote_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      flag: true,
      ref: ref,
      legacy: () async => const Res(['legacy']),
      resolver: resolver,
    );

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_remote_ref_never_calls_local_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    await _dispatch(
      flag: true,
      ref: ref,
      legacy: () async => const Res(['legacy']),
      resolver: resolver,
    );

    expect(local.calls, 0);
    expect(remote.calls, 1);
  });
}
