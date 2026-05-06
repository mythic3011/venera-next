import 'package:venera/features/reader_next/preflight/favorites_route_cutover_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

enum FavoritesRouteDecision { legacyExplicit, blocked, readerNextEligible }

class FavoritesRouteCutoverResult {
  const FavoritesRouteCutoverResult({
    required this.decision,
    required this.diagnostic,
    this.candidate,
    this.bridgeResult,
  });

  final FavoritesRouteDecision decision;
  final FavoritesRouteDecisionDiagnosticPacket diagnostic;
  final FavoritesRouteCandidate? candidate;
  final ReaderNextBridgeResult? bridgeResult;
}

typedef FavoritesDiagnosticSink =
    void Function(FavoritesRouteDecisionDiagnosticPacket packet);
typedef FavoritesLegacyOpen = Future<void> Function();
typedef FavoritesReaderNextOpen =
    Future<void> Function(ReaderNextOpenRequest request);
typedef FavoritesBlockedHandler = Future<void> Function(
  FavoritesRouteCutoverResult result,
);
typedef ReaderNextFavoritesOpenExecutor =
    Future<void> Function(ReaderNextOpenRequest request);

class FavoritesRouteCutoverController {
  const FavoritesRouteCutoverController({
    FavoritesRoutePreflightPolicy? preflightPolicy,
  }) : _preflightPolicy = preflightPolicy ?? const FavoritesRoutePreflightPolicy();

  final FavoritesRoutePreflightPolicy _preflightPolicy;

  FavoritesRouteCutoverResult evaluate({
    required IdentityCoverageInput input,
    required ReadinessArtifact artifact,
    required bool isRowStale,
  }) {
    final preflight = _preflightPolicy.evaluate(
      input: input,
      artifact: artifact,
      isRowStale: isRowStale,
    );
    return FavoritesRouteCutoverResult(
      decision: preflight.decision == FavoritesPreflightDecision.eligible
          ? FavoritesRouteDecision.readerNextEligible
          : FavoritesRouteDecision.blocked,
      diagnostic: preflight.diagnostic,
      candidate: preflight.candidate,
    );
  }
}

Future<FavoritesRouteDecision> routeFavoritesReadOpen({
  required FavoritesRouteCutoverController controller,
  required IdentityCoverageInput input,
  required ReadinessArtifact artifact,
  required bool isRowStale,
  required bool readerNextEnabled,
  required bool readerNextFavoritesEnabled,
  required FavoritesLegacyOpen openLegacy,
  required FavoritesReaderNextOpen openReaderNext,
  required FavoritesBlockedHandler onBlocked,
  FavoritesDiagnosticSink? onDiagnostic,
}) async {
  final featureFlagEnabled = readerNextEnabled && readerNextFavoritesEnabled;
  if (!featureFlagEnabled) {
    final legacyResult = FavoritesRouteCutoverResult(
      decision: FavoritesRouteDecision.legacyExplicit,
      diagnostic: FavoritesRouteDecisionDiagnosticPacket(
        recordKind: input.kind.name,
        folderName: input.folderName ?? '',
        recordIdRedacted: _redact(input.recordId),
        sourceKey: input.sourceKey,
        currentSourceRefValidationCode: SourceRefValidationCode.missing.name,
        readinessArtifactSchemaVersion: artifact.readinessArtifactSchemaVersion,
        routeDecision: FavoritesPreflightDecision.blocked,
        blockedReason: 'legacyExplicit',
      ),
    );
    onDiagnostic?.call(legacyResult.diagnostic);
    await openLegacy();
    return FavoritesRouteDecision.legacyExplicit;
  }

  final result = controller.evaluate(
    input: input,
    artifact: artifact,
    isRowStale: isRowStale,
  );
  if (result.decision == FavoritesRouteDecision.blocked) {
    onDiagnostic?.call(result.diagnostic);
    await onBlocked(result);
    return FavoritesRouteDecision.blocked;
  }

  final bridgeResult = ReaderNextOpenBridge.fromLegacy(
    sourceKey: input.sourceKey,
    comicId: input.recordId,
    chapterId: '0',
  );
  if (bridgeResult.isBlocked) {
    final diagnostic = bridgeResult.diagnostic!;
    final blockedResult = FavoritesRouteCutoverResult(
      decision: FavoritesRouteDecision.blocked,
      candidate: result.candidate,
      diagnostic: FavoritesRouteDecisionDiagnosticPacket(
        recordKind: input.kind.name,
        folderName: input.folderName ?? '',
        recordIdRedacted: _redact(input.recordId),
        sourceKey: input.sourceKey,
        currentSourceRefValidationCode:
            result.diagnostic.currentSourceRefValidationCode,
        readinessArtifactSchemaVersion:
            result.diagnostic.readinessArtifactSchemaVersion,
        routeDecision: FavoritesPreflightDecision.blocked,
        blockedReason: diagnostic.code.name,
        candidateId: result.candidate?.candidateId,
        observedIdentityFingerprint:
            result.candidate?.observedIdentityFingerprint,
      ),
      bridgeResult: bridgeResult,
    );
    onDiagnostic?.call(blockedResult.diagnostic);
    await onBlocked(blockedResult);
    return FavoritesRouteDecision.blocked;
  }

  final eligibleResult = FavoritesRouteCutoverResult(
    decision: FavoritesRouteDecision.readerNextEligible,
    candidate: result.candidate,
    diagnostic: result.diagnostic,
    bridgeResult: bridgeResult,
  );
  onDiagnostic?.call(eligibleResult.diagnostic);
  await openReaderNext(bridgeResult.request!);
  return FavoritesRouteDecision.readerNextEligible;
}

String _redact(String raw) {
  if (raw.isEmpty) {
    return '<empty>';
  }
  if (raw.length <= 4) {
    return '<redacted>';
  }
  return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
}
