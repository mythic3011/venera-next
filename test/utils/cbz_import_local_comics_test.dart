import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/utils/cbz.dart';

void main() {
  test('CBZ import fails closed when local comics database is unavailable', () {
    expect(
      () => CBZ.assertLegacyLookupAvailableForImport(
        'comic-a',
        lookup: (_) => const LegacyLocalComicLookupUnavailable(),
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('fail closed'),
        ),
      ),
    );
  });

  test('import path does not treat unavailable legacy lookup as not found', () {
    final unavailable = const LegacyLocalComicLookupUnavailable();
    expect(unavailable, isNot(isA<LegacyLocalComicLookupNotFound>()));
  });
}

