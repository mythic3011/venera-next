import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';
import 'package:venera/foundation/source_ref.dart';

class SourceRefResolver {
  const SourceRefResolver({
    required this.localProvider,
    required this.remoteProviderFactory,
    required this.sourceExists,
  });

  final ReadablePageProvider localProvider;
  final ReadablePageProvider Function(String sourceKey) remoteProviderFactory;
  final bool Function(String sourceKey) sourceExists;

  ReadablePageProvider resolve(SourceRef ref) {
    switch (ref.type) {
      case SourceRefType.local:
        return localProvider;
      case SourceRefType.remote:
        if (!sourceExists(ref.sourceKey)) {
          throw SourceRefDiagnostic(
            SourceRefDiagnosticCode.sourceNotAvailable,
            'SOURCE_NOT_AVAILABLE',
            context: {'sourceKey': ref.sourceKey},
          );
        }
        return remoteProviderFactory(ref.sourceKey);
    }
  }
}
