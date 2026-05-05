import 'package:flutter/foundation.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

typedef ReaderNextOpenExecutor = Future<void> Function(
  ReaderNextOpenRequest request,
);
typedef OpenReaderProductionLog = void Function(
  String title,
  Map<String, String> fields,
);

enum OpenReaderPhase { idle, opening, opened, boundaryRejected, error }

class OpenReaderState {
  const OpenReaderState({
    required this.phase,
    this.boundaryErrorCode,
    this.errorMessage,
  });

  final OpenReaderPhase phase;
  final String? boundaryErrorCode;
  final String? errorMessage;

  OpenReaderState copyWith({
    OpenReaderPhase? phase,
    String? boundaryErrorCode,
    bool clearBoundaryErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return OpenReaderState(
      phase: phase ?? this.phase,
      boundaryErrorCode: clearBoundaryErrorCode
          ? null
          : (boundaryErrorCode ?? this.boundaryErrorCode),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class OpenReaderController extends ChangeNotifier {
  OpenReaderController({
    required ReaderNextOpenExecutor openExecutor,
    OpenReaderProductionLog? productionLog,
  }) : _openExecutor = openExecutor,
       _productionLog = productionLog ?? _defaultProductionLog;

  final ReaderNextOpenExecutor _openExecutor;
  final OpenReaderProductionLog _productionLog;

  OpenReaderState _state = const OpenReaderState(phase: OpenReaderPhase.idle);
  OpenReaderState get state => _state;

  Future<void> open(ReaderNextOpenRequest request) async {
    _productionLog('ReaderNextOpen', _buildRedactedIdentityFields(request));
    _state = _state.copyWith(
      phase: OpenReaderPhase.opening,
      clearBoundaryErrorCode: true,
      clearErrorMessage: true,
    );
    notifyListeners();

    try {
      await _openExecutor(request);
      _state = _state.copyWith(phase: OpenReaderPhase.opened);
      notifyListeners();
    } on ReaderNextBoundaryException catch (e) {
      _state = _state.copyWith(
        phase: OpenReaderPhase.boundaryRejected,
        boundaryErrorCode: e.code,
        errorMessage: e.message,
      );
      notifyListeners();
    } on ReaderRuntimeException catch (e) {
      _state = _state.copyWith(
        phase: OpenReaderPhase.error,
        errorMessage: e.message,
      );
      notifyListeners();
    } catch (_) {
      _state = _state.copyWith(
        phase: OpenReaderPhase.error,
        errorMessage: 'Unexpected reader open error',
      );
      notifyListeners();
    }
  }

  static void _defaultProductionLog(String title, Map<String, String> fields) {
    AppDiagnostics.info('reader.next.open', 'open_reader_fields', data: fields);
  }

  static Map<String, String> _buildRedactedIdentityFields(
    ReaderNextOpenRequest request,
  ) {
    final sourceRef = request.sourceRef;
    return <String, String>{
      'sourceRef.sourceKey': _redact(sourceRef.sourceKey),
      'sourceRef.upstreamComicRefId': _redact(sourceRef.upstreamComicRefId),
      'sourceRef.chapterRefId': _redact(sourceRef.chapterRefId ?? ''),
      'canonicalComicId': _redact(request.canonicalComicId.value),
      'upstreamComicRefId': _redact(sourceRef.upstreamComicRefId),
    };
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
