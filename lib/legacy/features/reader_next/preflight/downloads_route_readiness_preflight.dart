import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

enum DownloadsSourceRefValidationCode {
  valid,
  missingSourceRef,
  malformedSourceRef,
  canonicalLeakAsUpstream,
  staleIdentity,
  missingRequiredIdentity,
}

enum DownloadsRemediationAction {
  none,
  eligibleForFutureDownloadsRoute,
  requiresUserReopenFromDetail,
  requiresLegacyImporterData,
  blockedMalformedIdentity,
  blockedStaleIdentity,
}

enum DownloadsPreflightDecision { blocked, eligibleForFutureDownloadsRoute }

class DownloadsSourceRefSnapshot {
  const DownloadsSourceRefSnapshot({
    required this.sourceKey,
    required this.upstreamComicRefId,
    required this.chapterRefId,
  });

  final String sourceKey;
  final String upstreamComicRefId;
  final String chapterRefId;
}

class DownloadsPreflightInput {
  const DownloadsPreflightInput({
    required this.recordId,
    required this.sourceKey,
    required this.canonicalComicId,
    required this.sourceRef,
    this.downloadSessionId,
    this.hasImporterOwnedExplicitSnapshot = false,
    this.explicitSnapshotAlreadyPersisted = false,
    this.localPath,
    this.cachePath,
    this.archivePath,
    this.filename,
    this.sourceUrl,
  });

  final String recordId;
  final String sourceKey;
  final String? canonicalComicId;
  final DownloadsSourceRefSnapshot? sourceRef;
  final String? downloadSessionId;
  final bool hasImporterOwnedExplicitSnapshot;
  final bool explicitSnapshotAlreadyPersisted;

  // Storage-only fields; must never be used to derive upstream identity.
  final String? localPath;
  final String? cachePath;
  final String? archivePath;
  final String? filename;
  final String? sourceUrl;
}

class DownloadsRouteCandidate {
  const DownloadsRouteCandidate({
    required this.recordId,
    required this.sourceKey,
    required this.canonicalComicId,
    required this.upstreamComicRefId,
    required this.chapterRefId,
    this.downloadSessionId,
    required this.candidateId,
    required this.observedIdentityFingerprint,
  });

  final String recordId;
  final String sourceKey;
  final String canonicalComicId;
  final String upstreamComicRefId;
  final String chapterRefId;
  final String? downloadSessionId;
  final String candidateId;
  final String observedIdentityFingerprint;
}

class DownloadsPreflightDiagnosticPacket {
  const DownloadsPreflightDiagnosticPacket({
    required this.recordKind,
    required this.recordIdRedacted,
    required this.sourceKey,
    this.downloadSessionIdRedacted,
    this.candidateId,
    this.observedIdentityFingerprint,
    required this.currentSourceRefValidationCode,
    required this.readinessArtifactSchemaVersion,
    required this.preflightDecision,
    required this.blockedReason,
  });

  final String recordKind;
  final String recordIdRedacted;
  final String sourceKey;
  final String? downloadSessionIdRedacted;
  final String? candidateId;
  final String? observedIdentityFingerprint;
  final DownloadsSourceRefValidationCode currentSourceRefValidationCode;
  final int readinessArtifactSchemaVersion;
  final DownloadsPreflightDecision preflightDecision;
  final String blockedReason;
}

class DownloadsRoutePreflightResult {
  const DownloadsRoutePreflightResult({
    required this.decision,
    required this.validationCode,
    required this.remediationAction,
    required this.diagnostic,
    this.candidate,
  });

  final DownloadsPreflightDecision decision;
  final DownloadsSourceRefValidationCode validationCode;
  final DownloadsRemediationAction remediationAction;
  final DownloadsPreflightDiagnosticPacket diagnostic;
  final DownloadsRouteCandidate? candidate;
}

class DownloadsRouteReadinessPreflightPolicy {
  const DownloadsRouteReadinessPreflightPolicy({
    ReaderNextRouteReadinessGate? readinessGate,
  }) : _readinessGate = readinessGate ?? const ReaderNextRouteReadinessGate();

  final ReaderNextRouteReadinessGate _readinessGate;

  DownloadsRouteCandidate buildCandidate({
    required DownloadsPreflightInput input,
  }) {
    final sourceRef = input.sourceRef;
    if (sourceRef == null ||
        input.canonicalComicId == null ||
        input.canonicalComicId!.trim().isEmpty ||
        sourceRef.sourceKey.trim().isEmpty ||
        sourceRef.upstreamComicRefId.trim().isEmpty ||
        sourceRef.chapterRefId.trim().isEmpty) {
      throw const FormatException(
        'downloads candidate requires explicit sourceRef, canonicalComicId, upstreamComicRefId, and chapterRefId',
      );
    }

    final canonicalComicId = input.canonicalComicId!.trim();
    final upstreamComicRefId = sourceRef.upstreamComicRefId.trim();
    final chapterRefId = sourceRef.chapterRefId.trim();
    final candidateFields = <String>[
      'downloads',
      input.recordId,
      sourceRef.sourceKey.trim(),
      canonicalComicId,
      upstreamComicRefId,
      chapterRefId,
      input.downloadSessionId?.trim() ?? '',
    ];
    final candidateId = _hash(candidateFields);
    final observedIdentityFingerprint = _hash(<String>[
      ...candidateFields,
      'fingerprint-v1',
    ]);
    return DownloadsRouteCandidate(
      recordId: input.recordId,
      sourceKey: sourceRef.sourceKey.trim(),
      canonicalComicId: canonicalComicId,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
      downloadSessionId: input.downloadSessionId?.trim().isEmpty ?? true
          ? null
          : input.downloadSessionId!.trim(),
      candidateId: candidateId,
      observedIdentityFingerprint: observedIdentityFingerprint,
    );
  }

  DownloadsRoutePreflightResult evaluate({
    required DownloadsPreflightInput input,
    required ReadinessArtifact artifact,
    required bool isRowStale,
  }) {
    final readiness = _readinessGate.evaluateArtifact(artifact);
    if (artifact.readinessArtifactSchemaVersion !=
        m14ReadinessArtifactSchemaVersion) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.missingRequiredIdentity,
        remediationAction: DownloadsRemediationAction.blockedMalformedIdentity,
        blockedReason: ReadinessBlockedReason.schemaVersionMismatch.name,
      );
    }
    if (!_readinessGate.isEntrypointAllowed(
      entrypoint: ReaderNextEntrypoint.downloads,
      decision: readiness,
    )) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.missingRequiredIdentity,
        remediationAction: DownloadsRemediationAction.blockedMalformedIdentity,
        blockedReason: ReadinessBlockedReason.gateDeniedEntrypoint.name,
      );
    }

    final sourceRef = input.sourceRef;
    if (sourceRef == null) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.missingSourceRef,
        remediationAction: input.hasImporterOwnedExplicitSnapshot
            ? DownloadsRemediationAction.requiresLegacyImporterData
            : DownloadsRemediationAction.requiresUserReopenFromDetail,
        blockedReason: DownloadsSourceRefValidationCode.missingSourceRef.name,
      );
    }

    if (sourceRef.sourceKey.trim().isEmpty ||
        sourceRef.upstreamComicRefId.trim().isEmpty ||
        sourceRef.chapterRefId.trim().isEmpty ||
        input.canonicalComicId == null ||
        input.canonicalComicId!.trim().isEmpty) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.missingRequiredIdentity,
        remediationAction: DownloadsRemediationAction.blockedMalformedIdentity,
        blockedReason:
            DownloadsSourceRefValidationCode.missingRequiredIdentity.name,
      );
    }

    if (sourceRef.upstreamComicRefId.contains(':') ||
        sourceRef.upstreamComicRefId.startsWith('remote:')) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.canonicalLeakAsUpstream,
        remediationAction: DownloadsRemediationAction.blockedMalformedIdentity,
        blockedReason:
            DownloadsSourceRefValidationCode.canonicalLeakAsUpstream.name,
      );
    }

    final candidate = buildCandidate(input: input);
    if (isRowStale) {
      return _blocked(
        input: input,
        artifact: artifact,
        validationCode: DownloadsSourceRefValidationCode.staleIdentity,
        remediationAction: DownloadsRemediationAction.blockedStaleIdentity,
        blockedReason: DownloadsSourceRefValidationCode.staleIdentity.name,
        candidate: candidate,
      );
    }

    final remediationAction = input.explicitSnapshotAlreadyPersisted
        ? DownloadsRemediationAction.none
        : DownloadsRemediationAction.eligibleForFutureDownloadsRoute;
    return DownloadsRoutePreflightResult(
      decision: DownloadsPreflightDecision.eligibleForFutureDownloadsRoute,
      validationCode: DownloadsSourceRefValidationCode.valid,
      remediationAction: remediationAction,
      candidate: candidate,
      diagnostic: DownloadsPreflightDiagnosticPacket(
        recordKind: 'downloads',
        recordIdRedacted: _redact(input.recordId),
        sourceKey: input.sourceKey,
        downloadSessionIdRedacted: _redact(input.downloadSessionId ?? ''),
        candidateId: candidate.candidateId,
        observedIdentityFingerprint: candidate.observedIdentityFingerprint,
        currentSourceRefValidationCode: DownloadsSourceRefValidationCode.valid,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        preflightDecision: DownloadsPreflightDecision
            .eligibleForFutureDownloadsRoute,
        blockedReason: 'none',
      ),
    );
  }

  DownloadsRoutePreflightResult _blocked({
    required DownloadsPreflightInput input,
    required ReadinessArtifact artifact,
    required DownloadsSourceRefValidationCode validationCode,
    required DownloadsRemediationAction remediationAction,
    required String blockedReason,
    DownloadsRouteCandidate? candidate,
  }) {
    return DownloadsRoutePreflightResult(
      decision: DownloadsPreflightDecision.blocked,
      validationCode: validationCode,
      remediationAction: remediationAction,
      candidate: candidate,
      diagnostic: DownloadsPreflightDiagnosticPacket(
        recordKind: 'downloads',
        recordIdRedacted: _redact(input.recordId),
        sourceKey: input.sourceKey,
        downloadSessionIdRedacted: _redact(input.downloadSessionId ?? ''),
        candidateId: candidate?.candidateId,
        observedIdentityFingerprint: candidate?.observedIdentityFingerprint,
        currentSourceRefValidationCode: validationCode,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        preflightDecision: DownloadsPreflightDecision.blocked,
        blockedReason: blockedReason,
      ),
    );
  }

  static String _redact(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '<empty>';
    }
    if (value.length <= 4) {
      return '<redacted>';
    }
    return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
  }

  static String _hash(List<String> fields) {
    return sha256.convert(utf8.encode(fields.join('\u0000'))).toString();
  }
}
