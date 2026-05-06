import 'package:venera/features/reader_next/bridge/reader_next_open_bridge.dart';

enum ComicDetailRouteDecision { legacy, readerNext, blocked }

class ComicDetailDryRunDiagnosticPacket {
  const ComicDetailDryRunDiagnosticPacket({
    required this.routeDecision,
    required this.sourceKey,
    required this.canonicalComicIdRedacted,
    required this.upstreamComicRefIdRedacted,
    required this.chapterRefIdRedacted,
    required this.bridgeResultCode,
    required this.featureFlagEnabled,
  });

  final ComicDetailRouteDecision routeDecision;
  final String sourceKey;
  final String canonicalComicIdRedacted;
  final String upstreamComicRefIdRedacted;
  final String chapterRefIdRedacted;
  final String bridgeResultCode;
  final bool featureFlagEnabled;
}

typedef ComicDetailLegacyOpen = Future<void> Function();
typedef ComicDetailReaderNextOpen =
    Future<void> Function(ReaderNextBridgeResult bridgeResult);
typedef ComicDetailBlockedHandler =
    Future<void> Function(ReaderNextBridgeDiagnostic diagnostic);
typedef ComicDetailDiagnosticSink =
    void Function(ComicDetailDryRunDiagnosticPacket packet);

bool isReaderNextEnabledSetting(Object? rawValue) => rawValue == true;

Future<ComicDetailRouteDecision> routeComicDetailReadOpen({
  required bool readerNextEnabled,
  required String sourceKey,
  required String comicId,
  required String? chapterRefId,
  required ComicDetailLegacyOpen openLegacy,
  required ComicDetailReaderNextOpen openReaderNext,
  required ComicDetailBlockedHandler onBridgeBlocked,
  ComicDetailDiagnosticSink? onDiagnostic,
}) async {
  if (!readerNextEnabled) {
    onDiagnostic?.call(
      ComicDetailDryRunDiagnosticPacket(
        routeDecision: ComicDetailRouteDecision.legacy,
        sourceKey: sourceKey,
        canonicalComicIdRedacted: _redact('remote:$sourceKey:$comicId'),
        upstreamComicRefIdRedacted: _redact(comicId),
        chapterRefIdRedacted: _redact(chapterRefId ?? ''),
        bridgeResultCode: 'legacy_route',
        featureFlagEnabled: false,
      ),
    );
    await openLegacy();
    return ComicDetailRouteDecision.legacy;
  }

  final bridgeResult = ReaderNextOpenBridge.fromLegacyRemote(
    sourceKey: sourceKey,
    comicId: comicId,
    chapterId: chapterRefId,
  );
  if (bridgeResult.isBlocked) {
    final diagnostic = bridgeResult.diagnostic!;
    onDiagnostic?.call(
      ComicDetailDryRunDiagnosticPacket(
        routeDecision: ComicDetailRouteDecision.blocked,
        sourceKey: sourceKey,
        canonicalComicIdRedacted: _redact('remote:$sourceKey:$comicId'),
        upstreamComicRefIdRedacted: _redact(comicId),
        chapterRefIdRedacted: _redact(chapterRefId ?? ''),
        bridgeResultCode: diagnostic.code.name,
        featureFlagEnabled: true,
      ),
    );
    await onBridgeBlocked(diagnostic);
    return ComicDetailRouteDecision.blocked;
  }

  onDiagnostic?.call(
    ComicDetailDryRunDiagnosticPacket(
      routeDecision: ComicDetailRouteDecision.readerNext,
      sourceKey: sourceKey,
      canonicalComicIdRedacted: _redact('remote:$sourceKey:$comicId'),
      upstreamComicRefIdRedacted: _redact(comicId),
      chapterRefIdRedacted: _redact(chapterRefId ?? ''),
      bridgeResultCode: 'reader_next',
      featureFlagEnabled: true,
    ),
  );
  await openReaderNext(bridgeResult);
  return ComicDetailRouteDecision.readerNext;
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
