import 'package:venera/foundation/download_queue_legacy_bridge.dart';
import 'package:venera/network/download.dart';

class DownloadQueueRepository {
  const DownloadQueueRepository();

  Future<void> ensureInitialized() => legacyEnsureDownloadQueueInitialized();

  void addListener(void Function() listener) {
    legacyAddDownloadQueueListener(listener);
  }

  void removeListener(void Function() listener) {
    legacyRemoveDownloadQueueListener(listener);
  }

  List<DownloadTask> get tasks => legacyDownloadQueueTasks();

  DownloadTask? get firstTask {
    return legacyDownloadQueueFirstTask();
  }

  void moveToFirst(DownloadTask task) {
    legacyMoveDownloadTaskToFirst(task);
  }
}
