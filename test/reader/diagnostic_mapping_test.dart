import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/diagnostic_mapping.dart';
import 'package:venera/foundation/reader/source_ref_diagnostics.dart';

void main() {
  test('maps_source_not_available', () {
    const diagnostic = SourceRefDiagnostic(
      SourceRefDiagnosticCode.sourceNotAvailable,
      'any',
    );
    expect(mapSourceRefDiagnosticToMessage(diagnostic), 'SOURCE_NOT_AVAILABLE');
  });

  test('maps_local_asset_missing', () {
    const diagnostic = SourceRefDiagnostic(
      SourceRefDiagnosticCode.localAssetMissing,
      'any',
    );
    expect(mapSourceRefDiagnosticToMessage(diagnostic), 'LOCAL_ASSET_MISSING');
  });

  test('maps_handler_mismatch', () {
    const diagnostic = SourceRefDiagnostic(
      SourceRefDiagnosticCode.sourceRefHandlerMismatch,
      'any',
    );
    expect(
      mapSourceRefDiagnosticToMessage(diagnostic),
      'SOURCE_REF_HANDLER_MISMATCH',
    );
  });
}
