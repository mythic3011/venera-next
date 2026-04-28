import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

class _FakeProvider implements ReadablePageProvider {
  final String name;
  _FakeProvider(this.name);

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async => Res([name]);
}

void main() {
  test('resolver_routes_local_ref_to_local_provider', () {
    final local = _FakeProvider('local');
    final remote = _FakeProvider('remote');
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
    final resolved = resolver.resolve(ref);
    expect(identical(resolved, local), isTrue);
  });

  test('resolver_routes_remote_ref_via_remote_provider_factory', () {
    final local = _FakeProvider('local');
    final remote = _FakeProvider('remote');
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
    final resolved = resolver.resolve(ref);
    expect(identical(resolved, remote), isTrue);
  });

  test('resolver_fails_closed_with_source_not_available_for_unknown_remote_key', () {
    final resolver = SourceRefResolver(
      localProvider: _FakeProvider('local'),
      remoteProviderFactory: (_) => _FakeProvider('remote'),
      sourceExists: (_) => false,
    );

    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'unknown-source',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    expect(
      () => resolver.resolve(ref),
      throwsA(
        isA<SourceRefDiagnostic>().having(
          (e) => e.code,
          'code',
          SourceRefDiagnosticCode.sourceNotAvailable,
        ),
      ),
    );
  });

  test('resolver_never_falls_back_to_local_for_unknown_remote_key', () {
    final local = _FakeProvider('local');
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => _FakeProvider('remote'),
      sourceExists: (_) => false,
    );

    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'unknown-source',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    expect(
      () => resolver.resolve(ref),
      throwsA(isA<SourceRefDiagnostic>()),
    );
  });
}
