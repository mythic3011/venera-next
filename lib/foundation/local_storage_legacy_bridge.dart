import 'package:venera/foundation/local.dart';

String legacyReadLocalComicsStoragePath() {
  return LocalManager().path;
}

Future<String?> legacySetLocalComicsStoragePath(String path) {
  return LocalManager().setNewPath(path);
}
