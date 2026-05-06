import 'package:venera/features/reader_next/backfill/explicit_identity_backfill_apply.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';

const int m14ReadinessArtifactSchemaVersion = 1;

enum ReaderNextEntrypoint { history, favorites, downloads }

enum ReadinessBlockedReason {
  schemaVersionMismatch,
  entrypointDisabled,
  gateDeniedEntrypoint,
  missingSourceRef,
  malformedSourceRef,
  canonicalLeakAsUpstream,
  staleIdentity,
  missingFavoritesFolderName,
}

enum RouteDecision { blocked, readerNextEligible }

class ReadinessArtifact {
  const ReadinessArtifact({
    required this.readinessArtifactSchemaVersion,
    required this.sourceSchemaVersion,
    required this.postApplyVerified,
    required this.allowHistory,
    required this.allowFavorites,
    required this.allowDownloads,
  });

  final int readinessArtifactSchemaVersion;
  final int sourceSchemaVersion;
  final bool postApplyVerified;
  final bool allowHistory;
  final bool allowFavorites;
  final bool allowDownloads;
}

class RouteReadinessDecision {
  const RouteReadinessDecision({
    required this.enableHistory,
    required this.enableFavorites,
    required this.enableDownloads,
  });

  final bool enableHistory;
  final bool enableFavorites;
  final bool enableDownloads;
}

class RouteDecisionPacket {
  const RouteDecisionPacket({
    required this.entrypoint,
    required this.routeDecision,
    this.blockedReason,
    required this.featureFlagEnabled,
    required this.recordKind,
    required this.recordId,
    required this.sourceKey,
    this.folderName,
    this.candidateId,
    this.observedIdentityFingerprint,
    required this.currentSourceRefValidationCode,
    required this.readinessArtifactSchemaVersion,
    required this.remediationAction,
  });

  final ReaderNextEntrypoint entrypoint;
  final RouteDecision routeDecision;
  final ReadinessBlockedReason? blockedReason;
  final bool featureFlagEnabled;
  final IdentityRecordKind recordKind;
  final String recordId;
  final String sourceKey;
  final String? folderName;
  final String? candidateId;
  final String? observedIdentityFingerprint;
  final SourceRefValidationCode currentSourceRefValidationCode;
  final int readinessArtifactSchemaVersion;
  final RemediationAction remediationAction;
}

class ReaderNextRouteReadinessGate {
  const ReaderNextRouteReadinessGate();

  RouteReadinessDecision evaluateArtifact(ReadinessArtifact artifact) {
    if (artifact.readinessArtifactSchemaVersion !=
            m14ReadinessArtifactSchemaVersion ||
        artifact.sourceSchemaVersion != m13ExpectedReportSchemaVersion ||
        !artifact.postApplyVerified) {
      return const RouteReadinessDecision(
        enableHistory: false,
        enableFavorites: false,
        enableDownloads: false,
      );
    }
    return RouteReadinessDecision(
      enableHistory: artifact.allowHistory,
      enableFavorites: artifact.allowFavorites,
      enableDownloads: artifact.allowDownloads,
    );
  }

  bool isEntrypointAllowed({
    required ReaderNextEntrypoint entrypoint,
    required RouteReadinessDecision decision,
  }) {
    return switch (entrypoint) {
      ReaderNextEntrypoint.history => decision.enableHistory,
      ReaderNextEntrypoint.favorites => decision.enableFavorites,
      ReaderNextEntrypoint.downloads => decision.enableDownloads,
    };
  }

  RouteDecisionPacket evaluateOpenAttempt({
    required ReaderNextEntrypoint entrypoint,
    required ReadinessArtifact artifact,
    required RouteReadinessDecision readiness,
    required bool featureFlagEnabled,
    required IdentityCoverageResult row,
    required bool isRowStale,
    String? candidateId,
  }) {
    if (artifact.readinessArtifactSchemaVersion !=
        m14ReadinessArtifactSchemaVersion) {
      return RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.schemaVersionMismatch,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      );
    }
    if (!featureFlagEnabled) {
      return RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.entrypointDisabled,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      );
    }
    if (!isEntrypointAllowed(entrypoint: entrypoint, decision: readiness)) {
      return RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.gateDeniedEntrypoint,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      );
    }
    if (isRowStale) {
      return RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.staleIdentity,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      );
    }
    if (row.kind == IdentityRecordKind.favorite &&
        (row.folderName == null || row.folderName!.trim().isEmpty)) {
      return RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.missingFavoritesFolderName,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      );
    }
    return switch (row.sourceRefValidationCode) {
      SourceRefValidationCode.valid => RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.readerNextEligible,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      ),
      SourceRefValidationCode.missing => RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.missingSourceRef,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      ),
      SourceRefValidationCode.malformed => RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.malformedSourceRef,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      ),
      SourceRefValidationCode.canonicalLeakAsUpstream => RouteDecisionPacket(
        entrypoint: entrypoint,
        routeDecision: RouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.canonicalLeakAsUpstream,
        featureFlagEnabled: featureFlagEnabled,
        recordKind: row.kind,
        recordId: row.recordId,
        sourceKey: row.sourceKey,
        folderName: row.folderName,
        candidateId: candidateId,
        observedIdentityFingerprint: row.observedIdentityFingerprint,
        currentSourceRefValidationCode: row.sourceRefValidationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        remediationAction: row.remediationAction,
      ),
    };
  }

  ReadinessArtifact fromPostApplyResult({
    required BackfillPostApplyVerifierResult verify,
    required bool requestedHistoryEnable,
    required bool requestedFavoritesEnable,
    required bool requestedDownloadsEnable,
  }) {
    final verified = verify.invalidAppliedCount == 0;
    return ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: m13ExpectedReportSchemaVersion,
      postApplyVerified: verified,
      allowHistory: verified && requestedHistoryEnable,
      allowFavorites: verified && requestedFavoritesEnable,
      allowDownloads: verified && requestedDownloadsEnable,
    );
  }
}
