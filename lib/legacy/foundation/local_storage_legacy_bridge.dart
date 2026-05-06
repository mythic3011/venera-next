import 'package:venera/foundation/local.dart';

String legacyReadLocalComicsStoragePath() {
  return LocalManager().path;
}

String? tryReadLocalComicsStoragePath({String Function()? reader}) {
  try {
    final path = (reader ?? legacyReadLocalComicsStoragePath).call();
    final trimmedPath = path.trim();
    return trimmedPath.isEmpty ? null : trimmedPath;
  } catch (error) {
    final asText = error.toString();
    if (asText.contains('LateInitializationError') ||
        asText.contains('late initialization')) {
      return null;
    }
    rethrow;
  }
}

Future<String?> legacySetLocalComicsStoragePath(String path) {
  return LocalManager().setNewPath(path);
}
