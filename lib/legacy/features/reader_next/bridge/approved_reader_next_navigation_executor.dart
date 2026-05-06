import 'package:venera/features/reader_next/presentation/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

typedef ReaderNextApprovedExecutor = ApprovedReaderNextOpenExecutor;
typedef ReaderNextApprovedExecutorFactory = ReaderNextApprovedExecutor Function();

ReaderNextApprovedExecutor createApprovedReaderNextNavigationExecutor() {
  return const ApprovedReaderNextNavigationExecutor().build();
}

ReaderNextApprovedExecutor resolveApprovedReaderNextExecutor({
  ReaderNextApprovedExecutor? injectedExecutor,
  ReaderNextApprovedExecutorFactory? injectedFactory,
  ReaderNextApprovedExecutorFactory approvedFactory =
      createApprovedReaderNextNavigationExecutor,
}) {
  if (injectedExecutor != null) {
    return injectedExecutor;
  }
  if (injectedFactory != null) {
    return injectedFactory();
  }
  return approvedFactory();
}

Future<void> dispatchApprovedReaderNextExecutor({
  required ReaderNextOpenRequest request,
  required ReaderNextApprovedExecutor executor,
}) {
  return executor(request);
}
