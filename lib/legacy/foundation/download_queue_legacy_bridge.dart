import 'package:venera/foundation/local.dart';
import 'package:venera/network/download.dart';

Future<void> legacyEnsureDownloadQueueInitialized() {
  return LocalManager().ensureInitialized();
}

void legacyAddDownloadQueueListener(void Function() listener) {
  LocalManager().addListener(listener);
}

void legacyRemoveDownloadQueueListener(void Function() listener) {
  LocalManager().removeListener(listener);
}

List<DownloadTask> legacyDownloadQueueTasks() {
  return List.unmodifiable(LocalManager().downloadingTasks);
}

DownloadTask? legacyDownloadQueueFirstTask() {
  final queue = LocalManager().downloadingTasks;
  return queue.isEmpty ? null : queue.first;
}

void legacyMoveDownloadTaskToFirst(DownloadTask task) {
  LocalManager().moveToFirst(task);
}

void legacyAddDownloadQueueTask(DownloadTask task) {
  LocalManager().addTask(task);
}

void legacyRemoveDownloadQueueTask(DownloadTask task) {
  LocalManager().removeTask(task);
}

void legacyCompleteDownloadQueueTask(DownloadTask task) {
  LocalManager().completeTask(task);
}
