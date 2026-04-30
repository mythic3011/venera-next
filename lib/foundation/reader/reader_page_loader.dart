import 'package:venera/foundation/reader/local_page_provider.dart';
import 'package:venera/foundation/reader/canonical_remote_page_provider.dart';
import 'package:venera/foundation/reader/diagnostic_mapping.dart';
import 'package:venera/foundation/reader/remote_page_provider.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

class ReaderPageLoaderResult {
  const ReaderPageLoaderResult({required this.res, required this.loadMode});

  final Res<List<String>> res;
  final String loadMode;
}

class ReaderPageLoader {
  const ReaderPageLoader({
    required this.loadLocalPages,
    required this.loadRemotePages,
    required this.sourceExists,
    this.canonicalRemotePageProviderFactory,
  });

  final LocalPagesLoader loadLocalPages;
  final RemotePagesLoader loadRemotePages;
  final bool Function(String sourceKey) sourceExists;
  final CanonicalRemotePageProvider Function(String sourceKey)?
  canonicalRemotePageProviderFactory;

  Future<ReaderPageLoaderResult> load(SourceRef sourceRef) async {
    final loadMode = sourceRef.type == SourceRefType.local ? 'local' : 'remote';
    final localProvider = LocalPageProvider(loadLocalPages: loadLocalPages);
    final resolver = SourceRefResolver(
      localProvider: localProvider,
      remoteProviderFactory: (sourceKey) => RemotePageProvider(
        loadRemotePages: loadRemotePages,
        canonicalRemotePageProvider: canonicalRemotePageProviderFactory?.call(
          sourceKey,
        ),
      ),
      sourceExists: sourceExists,
    );
    try {
      final provider = resolver.resolve(sourceRef);
      final res = await provider.loadPages(sourceRef);
      return ReaderPageLoaderResult(res: res, loadMode: loadMode);
    } on SourceRefDiagnostic catch (e) {
      return ReaderPageLoaderResult(
        res: Res.error(mapSourceRefDiagnosticToMessage(e)),
        loadMode: loadMode,
      );
    }
  }
}

Future<ReaderPageLoaderResult> dispatchReaderPageLoad({
  required bool useSourceRefResolver,
  required String loadMode,
  required Future<Res<List<String>>> Function() legacyLoadPages,
  required ReaderPageLoader loader,
  required SourceRef sourceRef,
}) async {
  if (!useSourceRefResolver) {
    final res = await legacyLoadPages();
    return ReaderPageLoaderResult(res: res, loadMode: loadMode);
  }
  return loader.load(sourceRef);
}
