import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/features/reader_next/runtime/local_runtime_smoke.dart';
import 'package:venera/foundation/db/unified_comics_store.dart'
    show ReaderSessionPersistResult, ReaderSessionPersistSkipReason;
import 'package:venera/foundation/sources/source_ref.dart';

class CanonicalLocalReaderSessionWriter implements LocalReaderSessionWriter {
  const CanonicalLocalReaderSessionWriter({required this.repository});

  final ReaderSessionRepository repository;

  @override
  Future<LocalReaderSessionPersistOutcome> persist({
    required String comicId,
    required String chapterId,
    required int page,
    required SourceRef sourceRef,
    String? pageOrderId,
  }) async {
    final result = await repository.upsertCurrentLocation(
      comicId: comicId,
      chapterId: chapterId,
      pageIndex: page,
      sourceRef: sourceRef,
      pageOrderId: pageOrderId,
    );
    return LocalReaderSessionPersistOutcome(
      written: result.written,
      skipReason: _skipReasonName(result),
    );
  }

  String? _skipReasonName(ReaderSessionPersistResult result) {
    return switch (result.skipReason) {
      ReaderSessionPersistSkipReason.unchanged => 'unchanged',
      ReaderSessionPersistSkipReason.unchangedMemory => 'unchanged_memory',
      ReaderSessionPersistSkipReason.duplicateInFlight => 'duplicate_in_flight',
      null => null,
    };
  }
}
