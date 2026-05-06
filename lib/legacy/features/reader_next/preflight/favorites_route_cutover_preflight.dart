import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';

enum FavoritesPreflightDecision { blocked, eligible }

class FavoritesPreflightBoundaryException implements Exception {
  const FavoritesPreflightBoundaryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'FavoritesPreflightBoundaryException($code): $message';
}

class FavoritesRouteCandidate {
  const FavoritesRouteCandidate({
    required this.recordKind,
    required this.folderName,
    required this.recordId,
    required this.sourceKey,
    required this.candidateId,
    required this.observedIdentityFingerprint,
  });

  final IdentityRecordKind recordKind;
  final String folderName;
  final String recordId;
  final String sourceKey;
  final String candidateId;
  final String observedIdentityFingerprint;
}

class FavoritesRouteDecisionDiagnosticPacket {
  const FavoritesRouteDecisionDiagnosticPacket({
    required this.recordKind,
    required this.folderName,
    required this.recordIdRedacted,
    required this.sourceKey,
    required this.currentSourceRefValidationCode,
    required this.readinessArtifactSchemaVersion,
    required this.routeDecision,
    required this.blockedReason,
    this.candidateId,
    this.observedIdentityFingerprint,
  });

  final String recordKind;
  final String folderName;
  final String recordIdRedacted;
  final String sourceKey;
  final String currentSourceRefValidationCode;
  final int readinessArtifactSchemaVersion;
  final FavoritesPreflightDecision routeDecision;
  final String blockedReason;
  final String? candidateId;
  final String? observedIdentityFingerprint;
}

class FavoritesRoutePreflightResult {
  const FavoritesRoutePreflightResult({
    required this.decision,
    required this.diagnostic,
    this.candidate,
  });

  final FavoritesPreflightDecision decision;
  final FavoritesRouteDecisionDiagnosticPacket diagnostic;
  final FavoritesRouteCandidate? candidate;
}

class FavoritesRoutePreflightPolicy {
  const FavoritesRoutePreflightPolicy({
    HistoryFavoritesIdentityCoverageScanner? scanner,
    ReaderNextRouteReadinessGate? readinessGate,
  }) : _scanner = scanner ?? const HistoryFavoritesIdentityCoverageScanner(),
       _readinessGate = readinessGate ?? const ReaderNextRouteReadinessGate();

  final HistoryFavoritesIdentityCoverageScanner _scanner;
  final ReaderNextRouteReadinessGate _readinessGate;

  FavoritesRouteCandidate buildCandidate({
    required IdentityCoverageInput input,
  }) {
    final folderName = input.folderName?.trim() ?? '';
    if (input.kind != IdentityRecordKind.favorite || folderName.isEmpty) {
      throw const FavoritesPreflightBoundaryException(
        'FAVORITES_FOLDER_REQUIRED',
        'Favorites candidate build requires non-empty folderName',
      );
    }
    final candidateId = _hash(
      <String>[
        input.kind.name,
        folderName,
        input.recordId,
        input.sourceKey,
      ],
    );
    final observedIdentityFingerprint = _hash(
      <String>[
        input.kind.name,
        folderName,
        input.recordId,
        input.sourceKey,
        input.canonicalComicId ?? '',
        input.sourceRef?.upstreamComicRefId ?? '',
        input.sourceRef?.chapterRefId ?? '',
      ],
    );
    return FavoritesRouteCandidate(
      recordKind: input.kind,
      folderName: folderName,
      recordId: input.recordId,
      sourceKey: input.sourceKey,
      candidateId: candidateId,
      observedIdentityFingerprint: observedIdentityFingerprint,
    );
  }

  FavoritesRoutePreflightResult evaluate({
    required IdentityCoverageInput input,
    required ReadinessArtifact artifact,
    required bool isRowStale,
  }) {
    final scan = _scanner.scan(input);
    final readiness = _readinessGate.evaluateArtifact(artifact);
    final candidate = (input.folderName?.trim().isNotEmpty ?? false)
        ? buildCandidate(input: input)
        : null;
    final packet = _readinessGate.evaluateOpenAttempt(
      entrypoint: ReaderNextEntrypoint.favorites,
      artifact: artifact,
      readiness: readiness,
      featureFlagEnabled: true,
      row: scan,
      isRowStale: isRowStale,
      candidateId: candidate?.candidateId,
    );
    if (packet.routeDecision == RouteDecision.blocked) {
      return FavoritesRoutePreflightResult(
        decision: FavoritesPreflightDecision.blocked,
        candidate: candidate,
        diagnostic: FavoritesRouteDecisionDiagnosticPacket(
          recordKind: 'favorites',
          folderName: input.folderName ?? '',
          recordIdRedacted: _redact(input.recordId),
          sourceKey: input.sourceKey,
          currentSourceRefValidationCode:
              packet.currentSourceRefValidationCode.name,
          readinessArtifactSchemaVersion: packet.readinessArtifactSchemaVersion,
          routeDecision: FavoritesPreflightDecision.blocked,
          blockedReason: packet.blockedReason?.name ?? 'blocked',
          candidateId: candidate?.candidateId,
          observedIdentityFingerprint: candidate?.observedIdentityFingerprint,
        ),
      );
    }

    return FavoritesRoutePreflightResult(
      decision: FavoritesPreflightDecision.eligible,
      candidate: candidate,
      diagnostic: FavoritesRouteDecisionDiagnosticPacket(
        recordKind: 'favorites',
        folderName: input.folderName ?? '',
        recordIdRedacted: _redact(input.recordId),
        sourceKey: input.sourceKey,
        currentSourceRefValidationCode: packet.currentSourceRefValidationCode.name,
        readinessArtifactSchemaVersion: packet.readinessArtifactSchemaVersion,
        routeDecision: FavoritesPreflightDecision.eligible,
        blockedReason: 'none',
        candidateId: candidate?.candidateId,
        observedIdentityFingerprint: candidate?.observedIdentityFingerprint,
      ),
    );
  }

  static String _redact(String raw) {
    if (raw.isEmpty) {
      return '<empty>';
    }
    if (raw.length <= 4) {
      return '<redacted>';
    }
    return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
  }

  static String _hash(List<String> fields) {
    final digest = sha256.convert(utf8.encode(fields.join('\u0000')));
    return digest.toString();
  }
}
