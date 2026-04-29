import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';

void main() {
  test('resolver canonicalizes legacy keys within allowed contexts', () {
    final favoriteAlias = resolveSourcePlatformKey(
      'pica',
      context: SourceLookupContext.favorite,
    );
    final importedAlias = resolveSourcePlatformKey(
      'htmanga',
      context: SourceLookupContext.imported,
    );
    final globalAlias = resolveSourcePlatformKey('htmanga');

    expect(favoriteAlias.canonicalKey, 'picacg');
    expect(favoriteAlias.matchedAliasType, SourceAliasType.legacyKey);
    expect(importedAlias.canonicalKey, 'wnacg');
    expect(importedAlias.matchedAliasType, SourceAliasType.migration);
    expect(globalAlias.isKnown, isFalse);
    expect(globalAlias.canonicalKey, 'htmanga');
  });

  test(
    'resolver legacy integer mapping is context aware from one authority',
    () {
      final favoriteZero = sourcePlatformResolver.resolveLegacyType(
        0,
        context: SourceLookupContext.favorite,
      );
      final historyZero = sourcePlatformResolver.resolveLegacyType(
        0,
        context: SourceLookupContext.history,
      );
      final historySix = sourcePlatformResolver.resolveLegacyType(
        6,
        context: SourceLookupContext.history,
      );
      final favoriteSix = sourcePlatformResolver.resolveLegacyType(
        6,
        context: SourceLookupContext.favorite,
      );

      expect(favoriteZero?.canonicalKey, 'picacg');
      expect(historyZero?.canonicalKey, 'picacg');
      expect(historySix, isNull);
      expect(favoriteSix?.canonicalKey, 'nhentai');
    },
  );

  test(
    'resolver can expose shared source type compatibility across favorite and history',
    () {
      expect(
        sourcePlatformResolver
            .resolveLegacyTypeAcrossContexts(
              5,
              contexts: sourceTypeCompatibilityContexts,
            )
            ?.canonicalKey,
        'nhentai',
      );
      expect(
        sourcePlatformResolver
            .resolveLegacyTypeAcrossContexts(
              6,
              contexts: sourceTypeCompatibilityContexts,
            )
            ?.canonicalKey,
        'nhentai',
      );
      expect(
        sourcePlatformResolver.resolveLegacyTypeAcrossContexts(
          999,
          contexts: sourceTypeCompatibilityContexts,
        ),
        isNull,
      );
    },
  );

  test('favorite legacy mapping export is derived from resolver authority', () {
    expect(
      legacySourceTypeSourceKeys,
      sourcePlatformResolver.legacyTypeMappingsForContexts(
        sourceTypeCompatibilityContexts,
      ),
    );
    expect(legacySourceTypeSourceKeys[6], 'nhentai');
    expect(legacySourceTypeSourceKeys[5], 'nhentai');
  });

  test('resolver preserves local platform semantics', () {
    final local = resolveSourcePlatformKey(localSourceKey);

    expect(local.platformId, localSourceKey);
    expect(local.kind, localSourceKind);
    expect(isLocalSourceKey(local.canonicalKey), isTrue);
  });
}
