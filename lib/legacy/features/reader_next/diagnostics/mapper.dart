import 'package:venera/features/reader_next/diagnostics/errors.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

ReaderNextLoadError mapReaderNextRuntimeError(Object error) {
  if (error is ReaderRuntimeException) {
    switch (error.code) {
      case 'SOURCE_REF_REQUIRED':
        return ReaderNextSourceUnavailableError(
          userMessage: error.message,
          diagnosticCode: error.code,
        );
      case 'SOURCE_REF_INVALID':
      case 'UPSTREAM_ID_INVALID':
      case 'CHAPTER_REF_INVALID':
        return ReaderNextSourceBoundaryError(
          userMessage: error.message,
          diagnosticCode: error.code,
        );
      case 'CANONICAL_ID_INVALID':
      case 'SEARCH_INVALID':
      case 'SESSION_INVALID':
      case 'SOURCE_KEY_INVALID':
        return ReaderNextValidationError(
          userMessage: error.message,
          diagnosticCode: error.code,
        );
      case 'ADAPTER_NOT_FOUND':
      case 'LOCAL_STORAGE_UNAVAILABLE':
      case 'LOCAL_COMIC_NOT_FOUND':
        return ReaderNextSourceUnavailableError(
          userMessage: error.message,
          diagnosticCode: error.code,
        );
      case 'LOCAL_IDENTITY_MISSING':
      case 'LOCAL_CHAPTER_NOT_FOUND':
      case 'LOCAL_PAGES_EMPTY':
      case 'REMOTE_PAGES_EMPTY':
      case 'LOCAL_PAGE_FILE_MISSING':
        return ReaderNextSourceBoundaryError(
          userMessage: error.message,
          diagnosticCode: error.code,
        );
    }
  }

  return ReaderNextUnknownError(
    userMessage: error.toString(),
    diagnosticCode: 'READER_NEXT_UNKNOWN',
  );
}
