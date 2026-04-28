import 'package:venera/foundation/comic_source/comic_source.dart';

class ComicType {
  final int value;

  const ComicType(this.value);

  @override
  bool operator ==(Object other) => other is ComicType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  String get sourceKey {
    if (this == local) {
      return "local";
    } else {
      final source = comicSource;
      return source?.key ?? "Unknown:$value";
    }
  }

  ComicSource? get comicSource {
    if (this == local) {
      return null;
    } else {
      return ComicSource.fromIntKey(value);
    }
  }

  static const local = ComicType(0);

  factory ComicType.fromKey(String key) {
    if (key == "local") {
      return local;
    } else if (key.startsWith("Unknown:")) {
      final intKey = int.tryParse(key.substring("Unknown:".length));
      if (intKey != null) {
        return ComicType(intKey);
      }
      return ComicType(key.hashCode);
    } else {
      return ComicType(key.hashCode);
    }
  }
}
