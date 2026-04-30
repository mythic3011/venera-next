import 'package:venera/foundation/local.dart';
import 'package:venera/network/download.dart';

class DownloadQueueRepository {
  const DownloadQueueRepository();

  Future<void> ensureInitialized() => LocalManager().ensureInitialized();

  void addListener(void Function() listener) {
    LocalManager().addListener(listener);
  }

  void removeListener(void Function() listener) {
    LocalManager().removeListener(listener);
  }

  List<DownloadTask> get tasks =>
      List.unmodifiable(LocalManager().downloadingTasks);

  DownloadTask? get firstTask {
    final queue = LocalManager().downloadingTasks;
    return queue.isEmpty ? null : queue.first;
  }

  void moveToFirst(DownloadTask task) {
    LocalManager().moveToFirst(task);
  }
}
