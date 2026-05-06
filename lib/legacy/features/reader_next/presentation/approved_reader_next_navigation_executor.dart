import 'package:venera/features/reader_next/presentation/open_reader_controller.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

typedef ReaderNextRequestExecutor =
    Future<void> Function(ReaderNextOpenRequest request);
typedef ApprovedReaderNextOpenExecutor =
    Future<void> Function(ReaderNextOpenRequest request);

class ApprovedReaderNextNavigationExecutor {
  const ApprovedReaderNextNavigationExecutor({
    ReaderNextRequestExecutor? openExecutor,
    OpenReaderProductionLog? productionLog,
  }) : _openExecutor = openExecutor,
       _productionLog = productionLog;

  final ReaderNextRequestExecutor? _openExecutor;
  final OpenReaderProductionLog? _productionLog;

  ApprovedReaderNextOpenExecutor build() {
    return (ReaderNextOpenRequest request) async {
      final controller = OpenReaderController(
        openExecutor: _openExecutor ?? _defaultReaderNextRequestExecutor,
        productionLog: _productionLog,
      );
      await controller.open(request);
      if (controller.state.phase != OpenReaderPhase.opened) {
        throw ReaderNextBoundaryException(
          controller.state.boundaryErrorCode ?? 'READER_NEXT_OPEN_FAILED',
          controller.state.errorMessage ?? 'ReaderNext open failed',
        );
      }
    };
  }
}

Future<void> _defaultReaderNextRequestExecutor(
  ReaderNextOpenRequest request,
) async {}
