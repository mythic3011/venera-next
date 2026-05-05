import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/sources/identity/source_identity.dart';

class ComicType {
  final int value;

  const ComicType(this.value);

  @override
  bool operator ==(Object other) => other is ComicType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  String get sourceKey {
    if (this == local) {
      return localSourceKey;
    }
    final source = comicSource;
    return source?.key ?? sourceKeyFromTypeValue(value);
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
    final value = sourceTypeValueFromKey(key);
    return value == 0 ? local : ComicType(value);
  }
}
