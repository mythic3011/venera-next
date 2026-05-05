import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';
import 'package:venera/features/reader_next/preflight/downloads_route_readiness_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

enum DownloadsRouteDecision { legacyExplicit, blocked, readerNextEligible }

class DownloadsRouteDecisionDiagnosticPacket {
  const DownloadsRouteDecisionDiagnosticPacket({
    required this.entrypoint,
    required this.routeDecision,
    required this.featureFlagEnabled,
    required this.readinessArtifactSchemaVersion,
    required this.recordKind,
    required this.recordIdRedacted,
    required this.sourceKey,
    this.downloadSessionIdRedacted,
    this.candidateId,
    this.observedIdentityFingerprint,
    required this.currentSourceRefValidationCode,
    required this.blockedReason,
  });

  final String entrypoint;
  final DownloadsRouteDecision routeDecision;
  final bool featureFlagEnabled;
  final int readinessArtifactSchemaVersion;
  final String recordKind;
  final String recordIdRedacted;
  final String sourceKey;
  final String? downloadSessionIdRedacted;
  final String? candidateId;
  final String? observedIdentityFingerprint;
  final DownloadsSourceRefValidationCode currentSourceRefValidationCode;
  final String blockedReason;
}

class DownloadsRouteCutoverResult {
  const DownloadsRouteCutoverResult({
    required this.decision,
    required this.diagnostic,
    this.preflightResult,
    this.bridgeResult,
  });

  final DownloadsRouteDecision decision;
  final DownloadsRouteDecisionDiagnosticPacket diagnostic;
  final DownloadsRoutePreflightResult? preflightResult;
  final ReaderNextBridgeResult? bridgeResult;
}

typedef DownloadsLegacyOpen = Future<void> Function();
typedef DownloadsBlockedHandler =
    Future<void> Function(DownloadsRouteCutoverResult result);
typedef DownloadsEligibleHandler =
    Future<void> Function(DownloadsRouteCutoverResult result);
typedef DownloadsDiagnosticSink =
    void Function(DownloadsRouteDecisionDiagnosticPacket packet);
typedef ReaderNextDownloadsOpenExecutor = ReaderNextApprovedExecutor;
typedef ReaderNextDownloadsOpenExecutorFactory =
    ReaderNextApprovedExecutorFactory;

ReaderNextDownloadsOpenExecutor? resolveDownloadsReaderNextExecutor({
  ReaderNextDownloadsOpenExecutor? injectedExecutor,
  ReaderNextDownloadsOpenExecutorFactory? injectedFactory,
  ReaderNextDownloadsOpenExecutorFactory approvedFactory =
      createApprovedReaderNextNavigationExecutor,
}) {
  return resolveApprovedReaderNextExecutor(
    injectedExecutor: injectedExecutor,
    injectedFactory: injectedFactory,
    approvedFactory: approvedFactory,
  );
}

class DownloadsRouteCutoverController {
  const DownloadsRouteCutoverController({
    DownloadsRouteReadinessPreflightPolicy? preflightPolicy,
  }) : _preflightPolicy =
           preflightPolicy ?? const DownloadsRouteReadinessPreflightPolicy();

  final DownloadsRouteReadinessPreflightPolicy _preflightPolicy;

  DownloadsRouteCutoverResult evaluate({
    required DownloadsPreflightInput input,
    required ReadinessArtifact artifact,
    required bool isRowStale,
    required bool featureFlagEnabled,
  }) {
    if (!featureFlagEnabled) {
      return DownloadsRouteCutoverResult(
        decision: DownloadsRouteDecision.legacyExplicit,
        diagnostic: DownloadsRouteDecisionDiagnosticPacket(
          entrypoint: 'downloads',
          routeDecision: DownloadsRouteDecision.legacyExplicit,
          featureFlagEnabled: false,
          readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
          recordKind: 'downloads',
          recordIdRedacted: _redact(input.recordId),
          sourceKey: input.sourceKey,
          downloadSessionIdRedacted: _redact(input.downloadSessionId ?? ''),
          currentSourceRefValidationCode:
              DownloadsSourceRefValidationCode.missingRequiredIdentity,
          blockedReason: 'legacyExplicit',
        ),
      );
    }

    final preflight = _preflightPolicy.evaluate(
      input: input,
      artifact: artifact,
      isRowStale: isRowStale,
    );
    final decision = preflight.decision ==
            DownloadsPreflightDecision.eligibleForFutureDownloadsRoute
        ? DownloadsRouteDecision.readerNextEligible
        : DownloadsRouteDecision.blocked;
    final bridgeResult = decision == DownloadsRouteDecision.readerNextEligible
        ? ReaderNextOpenBridge.fromLegacy(
            sourceKey: preflight.candidate!.sourceKey,
            comicId: preflight.candidate!.upstreamComicRefId,
            chapterId: preflight.candidate!.chapterRefId,
          )
        : null;
    return DownloadsRouteCutoverResult(
      decision: decision,
      preflightResult: preflight,
      bridgeResult: bridgeResult,
      diagnostic: DownloadsRouteDecisionDiagnosticPacket(
        entrypoint: 'downloads',
        routeDecision: decision,
        featureFlagEnabled: true,
        readinessArtifactSchemaVersion:
            preflight.diagnostic.readinessArtifactSchemaVersion,
        recordKind: preflight.diagnostic.recordKind,
        recordIdRedacted: preflight.diagnostic.recordIdRedacted,
        sourceKey: preflight.diagnostic.sourceKey,
        downloadSessionIdRedacted: preflight.diagnostic.downloadSessionIdRedacted,
        candidateId: preflight.diagnostic.candidateId,
        observedIdentityFingerprint:
            preflight.diagnostic.observedIdentityFingerprint,
        currentSourceRefValidationCode:
            preflight.diagnostic.currentSourceRefValidationCode,
        blockedReason: preflight.diagnostic.blockedReason,
      ),
    );
  }
}

Future<DownloadsRouteDecision> routeDownloadsReadOpen({
  required DownloadsRouteCutoverController controller,
  required DownloadsPreflightInput input,
  required ReadinessArtifact artifact,
  required bool isRowStale,
  required bool readerNextEnabled,
  required bool readerNextDownloadsEnabled,
  required DownloadsLegacyOpen openLegacy,
  required DownloadsBlockedHandler onBlocked,
  required DownloadsEligibleHandler onEligible,
  DownloadsDiagnosticSink? onDiagnostic,
}) async {
  final featureFlagEnabled = readerNextEnabled && readerNextDownloadsEnabled;
  final result = controller.evaluate(
    input: input,
    artifact: artifact,
    isRowStale: isRowStale,
    featureFlagEnabled: featureFlagEnabled,
  );
  onDiagnostic?.call(result.diagnostic);

  switch (result.decision) {
    case DownloadsRouteDecision.legacyExplicit:
      await openLegacy();
      return DownloadsRouteDecision.legacyExplicit;
    case DownloadsRouteDecision.blocked:
      await onBlocked(result);
      return DownloadsRouteDecision.blocked;
    case DownloadsRouteDecision.readerNextEligible:
      await onEligible(result);
      return DownloadsRouteDecision.readerNextEligible;
  }
}

Future<void> dispatchDownloadsEligibleToExecutor({
  required DownloadsRouteCutoverResult result,
  required ReaderNextDownloadsOpenExecutor executor,
}) async {
  final request = result.bridgeResult?.request;
  if (result.decision != DownloadsRouteDecision.readerNextEligible ||
      request == null) {
    throw ReaderNextBoundaryException(
      'DOWNLOADS_EXECUTOR_INPUT_INVALID',
      'downloads eligible executor dispatch requires a validated bridge request',
    );
  }
  await dispatchApprovedReaderNextExecutor(request: request, executor: executor);
}

String _redact(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '<empty>';
  }
  if (value.length <= 4) {
    return '<redacted>';
  }
  return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
}
