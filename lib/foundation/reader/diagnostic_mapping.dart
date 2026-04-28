import 'package:venera/foundation/reader/source_ref_diagnostics.dart';

String mapSourceRefDiagnosticToMessage(SourceRefDiagnostic diagnostic) {
  switch (diagnostic.code) {
    case SourceRefDiagnosticCode.sourceNotAvailable:
      return 'SOURCE_NOT_AVAILABLE';
    case SourceRefDiagnosticCode.localAssetMissing:
      return 'LOCAL_ASSET_MISSING';
    case SourceRefDiagnosticCode.sourceRefTypeMismatch:
      return 'SOURCE_REF_TYPE_MISMATCH';
    case SourceRefDiagnosticCode.sourceRefHandlerMismatch:
      return 'SOURCE_REF_HANDLER_MISMATCH';
    case SourceRefDiagnosticCode.sourceRefNotFound:
      return 'SOURCE_REF_NOT_FOUND';
  }
}

