import 'package:venera/foundation/reader/local_page_provider.dart';
import 'package:venera/foundation/reader/remote_page_provider.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

class ReaderPageLoaderResult {
  const ReaderPageLoaderResult({
    required this.res,
    required this.loadMode,
  });

  final Res<List<String>> res;
  final String loadMode;
}

class ReaderPageLoader {
  const ReaderPageLoader({
    required this.loadLocalPages,
    required this.loadRemotePages,
    required this.sourceExists,
  });

  final LocalPagesLoader loadLocalPages;
  final RemotePagesLoader loadRemotePages;
  final bool Function(String sourceKey) sourceExists;

  Future<ReaderPageLoaderResult> load(SourceRef sourceRef) async {
    final loadMode = sourceRef.type == SourceRefType.local ? 'local' : 'remote';
    final localProvider = LocalPageProvider(loadLocalPages: loadLocalPages);
    final resolver = SourceRefResolver(
      localProvider: localProvider,
      remoteProviderFactory: (_) => RemotePageProvider(
        loadRemotePages: loadRemotePages,
      ),
      sourceExists: sourceExists,
    );
    try {
      final provider = resolver.resolve(sourceRef);
      final res = await provider.loadPages(sourceRef);
      return ReaderPageLoaderResult(res: res, loadMode: loadMode);
    } on SourceRefDiagnostic catch (e) {
      if (e.code == SourceRefDiagnosticCode.sourceNotAvailable) {
        return ReaderPageLoaderResult(
          res: const Res.error('SOURCE_NOT_AVAILABLE'),
          loadMode: loadMode,
        );
      }
      return ReaderPageLoaderResult(
        res: Res.error(e.message),
        loadMode: loadMode,
      );
    }
  }
}
