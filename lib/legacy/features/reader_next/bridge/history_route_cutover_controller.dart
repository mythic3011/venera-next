import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/features/reader_next/runtime/models.dart'
    hide SourceRefType;
import 'package:venera/foundation/sources/source_ref.dart';

enum HistoryRouteDecision { legacyExplicit, readerNextEligible, blocked }

class HistoryRouteDecisionDiagnosticPacket {
  const HistoryRouteDecisionDiagnosticPacket({
    required this.entrypoint,
    required this.routeDecision,
    required this.featureFlagEnabled,
    required this.readinessArtifactSchemaVersion,
    required this.recordKind,
    required this.recordIdRedacted,
    required this.sourceKey,
    this.candidateId,
    this.observedIdentityFingerprint,
    required this.currentSourceRefValidationCode,
    required this.bridgeResultCode,
    this.blockedReason,
  });

  final String entrypoint;
  final HistoryRouteDecision routeDecision;
  final bool featureFlagEnabled;
  final int readinessArtifactSchemaVersion;
  final String recordKind;
  final String recordIdRedacted;
  final String sourceKey;
  final String? candidateId;
  final String? observedIdentityFingerprint;
  final String currentSourceRefValidationCode;
  final String bridgeResultCode;
  final String? blockedReason;
}

class HistoryRouteCutoverResult {
  const HistoryRouteCutoverResult({
    required this.decision,
    required this.diagnostic,
    this.bridgeResult,
    this.blockedReason,
  });

  final HistoryRouteDecision decision;
  final HistoryRouteDecisionDiagnosticPacket diagnostic;
  final ReaderNextBridgeResult? bridgeResult;
  final ReadinessBlockedReason? blockedReason;
}

typedef HistoryLegacyOpen = Future<void> Function();
typedef HistoryReaderNextOpen =
    Future<void> Function(ReaderNextOpenRequest request);
typedef HistoryBlockedHandler = Future<void> Function(HistoryRouteCutoverResult);
typedef HistoryDiagnosticSink =
    void Function(HistoryRouteDecisionDiagnosticPacket packet);
typedef ReaderNextHistoryOpenExecutor =
    Future<void> Function(ReaderNextOpenRequest request);

typedef HistoryReadinessArtifactProvider = ReadinessArtifact Function();
typedef HistoryRowStaleEvaluator = bool Function(ReaderActivityItem row);

class HistoryRouteCutoverController {
  const HistoryRouteCutoverController({
    this.readinessArtifactProvider = _defaultReadinessArtifactProvider,
    this.rowStaleEvaluator = _defaultRowStaleEvaluator,
    HistoryFavoritesIdentityCoverageScanner? scanner,
    ReaderNextRouteReadinessGate? readinessGate,
  }) : _scanner = scanner ?? const HistoryFavoritesIdentityCoverageScanner(),
       _readinessGate = readinessGate ?? const ReaderNextRouteReadinessGate();

  final HistoryReadinessArtifactProvider readinessArtifactProvider;
  final HistoryRowStaleEvaluator rowStaleEvaluator;
  final HistoryFavoritesIdentityCoverageScanner _scanner;
  final ReaderNextRouteReadinessGate _readinessGate;

  HistoryRouteCutoverResult evaluate({
    required ReaderActivityItem row,
    required bool readerNextEnabled,
    required bool readerNextHistoryEnabled,
  }) {
    final featureFlagEnabled = readerNextEnabled && readerNextHistoryEnabled;
    final scanInput = _buildScanInput(row);
    final scan = _scanner.scan(scanInput);
    final artifact = readinessArtifactProvider();
    final readiness = _readinessGate.evaluateArtifact(artifact);

    if (!featureFlagEnabled) {
      return HistoryRouteCutoverResult(
        decision: HistoryRouteDecision.legacyExplicit,
        diagnostic: _buildDiagnosticPacket(
          routeDecision: HistoryRouteDecision.legacyExplicit,
          featureFlagEnabled: false,
          readinessArtifactSchemaVersion:
              artifact.readinessArtifactSchemaVersion,
          recordKind: scan.kind.name,
          recordId: scan.recordId,
          sourceKey: scan.sourceKey,
          candidateId: null,
          observedIdentityFingerprint: scan.observedIdentityFingerprint,
          currentSourceRefValidationCode: scan.sourceRefValidationCode.name,
          bridgeResultCode: 'legacyExplicit',
          blockedReason: null,
        ),
      );
    }

    final packet = _readinessGate.evaluateOpenAttempt(
      entrypoint: ReaderNextEntrypoint.history,
      artifact: artifact,
      readiness: readiness,
      featureFlagEnabled: true,
      row: scan,
      isRowStale: rowStaleEvaluator(row),
    );
    if (packet.routeDecision == RouteDecision.blocked) {
      return HistoryRouteCutoverResult(
        decision: HistoryRouteDecision.blocked,
        blockedReason: packet.blockedReason,
        diagnostic: _buildDiagnosticPacket(
          routeDecision: HistoryRouteDecision.blocked,
          featureFlagEnabled: true,
          readinessArtifactSchemaVersion:
              packet.readinessArtifactSchemaVersion,
          recordKind: packet.recordKind.name,
          recordId: packet.recordId,
          sourceKey: packet.sourceKey,
          candidateId: packet.candidateId,
          observedIdentityFingerprint: packet.observedIdentityFingerprint,
          currentSourceRefValidationCode:
              packet.currentSourceRefValidationCode.name,
          bridgeResultCode: packet.blockedReason?.name ?? 'blocked',
          blockedReason: packet.blockedReason?.name,
        ),
      );
    }

    final chapterId = row.chapterId.trim().isEmpty ? null : row.chapterId.trim();
    final bridgeResult = ReaderNextOpenBridge.fromLegacy(
      sourceKey: row.sourceRef.sourceKey,
      comicId: row.sourceRef.refId,
      chapterId: chapterId,
    );
    if (bridgeResult.isBlocked) {
      final diagnostic = bridgeResult.diagnostic!;
      return HistoryRouteCutoverResult(
        decision: HistoryRouteDecision.blocked,
        blockedReason: ReadinessBlockedReason.malformedSourceRef,
        diagnostic: _buildDiagnosticPacket(
          routeDecision: HistoryRouteDecision.blocked,
          featureFlagEnabled: true,
          readinessArtifactSchemaVersion:
              artifact.readinessArtifactSchemaVersion,
          recordKind: scan.kind.name,
          recordId: scan.recordId,
          sourceKey: scan.sourceKey,
          candidateId: null,
          observedIdentityFingerprint: scan.observedIdentityFingerprint,
          currentSourceRefValidationCode: scan.sourceRefValidationCode.name,
          bridgeResultCode: diagnostic.code.name,
          blockedReason: ReadinessBlockedReason.malformedSourceRef.name,
        ),
      );
    }

    return HistoryRouteCutoverResult(
      decision: HistoryRouteDecision.readerNextEligible,
      bridgeResult: bridgeResult,
      diagnostic: _buildDiagnosticPacket(
        routeDecision: HistoryRouteDecision.readerNextEligible,
        featureFlagEnabled: true,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        recordKind: scan.kind.name,
        recordId: scan.recordId,
        sourceKey: scan.sourceKey,
        candidateId: null,
        observedIdentityFingerprint: scan.observedIdentityFingerprint,
        currentSourceRefValidationCode: scan.sourceRefValidationCode.name,
        bridgeResultCode: 'readerNextEligible',
        blockedReason: null,
      ),
    );
  }

  static ReadinessArtifact _defaultReadinessArtifactProvider() {
    return const ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: false,
      allowFavorites: false,
      allowDownloads: false,
    );
  }

  static bool _defaultRowStaleEvaluator(ReaderActivityItem row) => false;

  IdentityCoverageInput _buildScanInput(ReaderActivityItem row) {
    final sourceRef = row.sourceRef;
    final explicitSnapshot = sourceRef.type == SourceRefType.remote
        ? ExplicitSourceRefSnapshot(
            sourceKey: sourceRef.sourceKey,
            upstreamComicRefId: sourceRef.refId,
            chapterRefId: row.chapterId.trim().isEmpty ? null : row.chapterId,
          )
        : null;
    return IdentityCoverageInput.history(
      recordId: row.id,
      sourceKey: sourceRef.sourceKey,
      canonicalComicId: sourceRef.canonicalId,
      sourceRef: explicitSnapshot,
      explicitSnapshotAlreadyPersisted: true,
    );
  }

  static HistoryRouteDecisionDiagnosticPacket _buildDiagnosticPacket({
    required HistoryRouteDecision routeDecision,
    required bool featureFlagEnabled,
    required int readinessArtifactSchemaVersion,
    required String recordKind,
    required String recordId,
    required String sourceKey,
    required String? candidateId,
    required String? observedIdentityFingerprint,
    required String currentSourceRefValidationCode,
    required String bridgeResultCode,
    required String? blockedReason,
  }) {
    return HistoryRouteDecisionDiagnosticPacket(
      entrypoint: 'history',
      routeDecision: routeDecision,
      featureFlagEnabled: featureFlagEnabled,
      readinessArtifactSchemaVersion: readinessArtifactSchemaVersion,
      recordKind: recordKind,
      recordIdRedacted: _redact(recordId),
      sourceKey: sourceKey,
      candidateId: candidateId,
      observedIdentityFingerprint: observedIdentityFingerprint,
      currentSourceRefValidationCode: currentSourceRefValidationCode,
      bridgeResultCode: bridgeResultCode,
      blockedReason: blockedReason,
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
}

ReaderNextHistoryOpenExecutor createApprovedHistoryReaderNextExecutor() {
  return createApprovedReaderNextNavigationExecutor();
}

Future<HistoryRouteDecision> routeHistoryReadOpen({
  required HistoryRouteCutoverController controller,
  required ReaderActivityItem row,
  required bool readerNextEnabled,
  required bool readerNextHistoryEnabled,
  required HistoryLegacyOpen openLegacy,
  required HistoryReaderNextOpen openReaderNext,
  required HistoryBlockedHandler onBlocked,
  HistoryDiagnosticSink? onDiagnostic,
}) async {
  final result = controller.evaluate(
    row: row,
    readerNextEnabled: readerNextEnabled,
    readerNextHistoryEnabled: readerNextHistoryEnabled,
  );
  onDiagnostic?.call(result.diagnostic);
  switch (result.decision) {
    case HistoryRouteDecision.legacyExplicit:
      await openLegacy();
      return HistoryRouteDecision.legacyExplicit;
    case HistoryRouteDecision.blocked:
      await onBlocked(result);
      return HistoryRouteDecision.blocked;
    case HistoryRouteDecision.readerNextEligible:
      await openReaderNext(result.bridgeResult!.request!);
      return HistoryRouteDecision.readerNextEligible;
  }
}
