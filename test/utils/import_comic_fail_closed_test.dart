import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/utils/import_comic.dart';

void main() {
  test('import duplicate lookup keeps unavailable distinct from not found', () {
    final result = lookupLocalComicForImportDuplicateCheck(
      'comic-a',
      lookup: (_) => const LegacyLocalComicLookupUnavailable(),
    );
    expect(result, isA<LegacyLocalComicLookupUnavailable>());
    expect(result, isNot(isA<LegacyLocalComicLookupNotFound>()));
  });

  test('import root path resolver fails closed on late-init style errors', () {
    expect(
      () => requireLocalComicsRootPathForImport(
        reader: () => throw StateError(
          "LateInitializationError: Field 'path' has not been initialized.",
        ),
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('fail closed'),
        ),
      ),
    );
  });
}

