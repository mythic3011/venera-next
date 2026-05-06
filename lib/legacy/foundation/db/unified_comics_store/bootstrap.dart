part of '../unified_comics_store.dart';

Iterable<SourcePlatformAliasRecord> _aliasesForDefinition(
  SourcePlatformDefinition platform,
) sync* {
  yield SourcePlatformAliasRecord(
    platformId: platform.platformId,
    aliasKey: platform.canonicalKey,
    aliasType: SourceAliasType.canonical.key,
    sourceContext: sourceContextGlobal,
  );
  for (final alias in platform.aliases) {
    for (final context in alias.contexts) {
      yield SourcePlatformAliasRecord(
        platformId: platform.platformId,
        aliasKey: alias.aliasKey,
        aliasType: alias.aliasType.key,
        legacyIntType: alias.legacyIntType,
        sourceContext: context.key,
      );
    }
  }
}
