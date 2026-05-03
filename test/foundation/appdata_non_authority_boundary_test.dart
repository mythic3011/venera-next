import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';

void main() {
  test(
    'appdata/implicitData cataloged keys are not canonical domain authority',
    () {
      for (final entry in appdataAuditEntries) {
        expect(
          entry.classification,
          isNot(AppdataAuditClassification.migratedCanonicalAuthority),
          reason:
              'appdata key ${entry.key} must not be canonical domain authority',
        );
      }
    },
  );

  test('implicitData cataloged keys stay in non-authority classes', () {
    const allowed = <AppdataAuditClassification>{
      AppdataAuditClassification.legacyBridge,
      AppdataAuditClassification.runtimeCache,
      AppdataAuditClassification.featureFlag,
      AppdataAuditClassification.deviceIntegration,
      AppdataAuditClassification.uiPreference,
      AppdataAuditClassification.uiWorkflowState,
      AppdataAuditClassification.unknownNeedsOwner,
    };
    for (final entry in appdataAuditEntries) {
      if (entry.storage != AppdataAuditStorage.implicitData) {
        continue;
      }
      expect(
        allowed.contains(entry.classification),
        isTrue,
        reason:
            'implicitData key ${entry.key} must remain non-domain-authority',
      );
    }
  });
}
