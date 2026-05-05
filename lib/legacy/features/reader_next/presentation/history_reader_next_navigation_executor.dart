import 'package:venera/features/reader_next/presentation/approved_reader_next_navigation_executor.dart';

typedef ReaderNextHistoryOpenExecutor = ApprovedReaderNextOpenExecutor;

class HistoryReaderNextNavigationExecutor extends ApprovedReaderNextNavigationExecutor {
  const HistoryReaderNextNavigationExecutor({
    super.openExecutor,
    super.productionLog,
  });
}
