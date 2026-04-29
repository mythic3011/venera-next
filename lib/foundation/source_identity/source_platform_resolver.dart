import 'constants.dart';

enum SourceLookupContext {
  global('global'),
  favorite('favorite'),
  history('history'),
  reader('reader'),
  plugin('plugin'),
  download('download'),
  imported('import');

  const SourceLookupContext(this.key);

  final String key;
}

enum SourceAliasType {
  canonical('canonical'),
  legacyKey('legacy_key'),
  legacyType('legacy_type'),
  pluginKey('plugin_key'),
  displayName('display_name'),
  migration('migration'),
  unknown('unknown');

  const SourceAliasType(this.key);

  final String key;
}

class SourcePlatformAlias {
  const SourcePlatformAlias({
    required this.aliasKey,
    required this.aliasType,
    this.legacyIntType,
    this.contexts = const <SourceLookupContext>{SourceLookupContext.global},
  });

  final String aliasKey;
  final SourceAliasType aliasType;
  final int? legacyIntType;
  final Set<SourceLookupContext> contexts;

  bool appliesTo(SourceLookupContext context) {
    return contexts.contains(SourceLookupContext.global) ||
        contexts.contains(context);
  }
}

class SourcePlatformDefinition {
  const SourcePlatformDefinition({
    required this.platformId,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    this.aliases = const <SourcePlatformAlias>[],
  });

  final String platformId;
  final String canonicalKey;
  final String displayName;
  final String kind;
  final List<SourcePlatformAlias> aliases;

  Iterable<SourcePlatformAlias> aliasesFor(SourceLookupContext context) sync* {
    yield SourcePlatformAlias(
      aliasKey: canonicalKey,
      aliasType: SourceAliasType.canonical,
      contexts: const <SourceLookupContext>{SourceLookupContext.global},
    );
    for (final alias in aliases) {
      if (alias.appliesTo(context)) {
        yield alias;
      }
    }
  }
}

class SourcePlatformRef {
  const SourcePlatformRef({
    required this.platformId,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    required this.matchedAlias,
    required this.matchedAliasType,
    this.legacyIntType,
    this.isKnown = true,
  });

  final String platformId;
  final String canonicalKey;
  final String displayName;
  final String kind;
  final String matchedAlias;
  final SourceAliasType matchedAliasType;
  final int? legacyIntType;
  final bool isKnown;

  factory SourcePlatformRef.unknownKey(String key, {required String kind}) {
    return SourcePlatformRef(
      platformId: key,
      canonicalKey: key,
      displayName: key,
      kind: kind,
      matchedAlias: key,
      matchedAliasType: SourceAliasType.unknown,
      isKnown: false,
    );
  }
}

class SourcePlatformResolver {
  const SourcePlatformResolver(this.platforms);

  final List<SourcePlatformDefinition> platforms;

  SourcePlatformRef resolveKey(
    String key, {
    SourceLookupContext context = SourceLookupContext.global,
  }) {
    final normalizedKey = key.trim();
    for (final platform in platforms) {
      for (final alias in platform.aliasesFor(context)) {
        if (alias.aliasKey.toLowerCase() != normalizedKey.toLowerCase()) {
          continue;
        }
        return SourcePlatformRef(
          platformId: platform.platformId,
          canonicalKey: platform.canonicalKey,
          displayName: platform.displayName,
          kind: platform.kind,
          matchedAlias: alias.aliasKey,
          matchedAliasType: alias.aliasType,
          legacyIntType: alias.legacyIntType,
        );
      }
    }
    return SourcePlatformRef.unknownKey(
      normalizedKey,
      kind: sourceKindFromResolvedKey(normalizedKey),
    );
  }

  SourcePlatformRef? resolveLegacyType(
    int legacyType, {
    required SourceLookupContext context,
  }) {
    for (final platform in platforms) {
      for (final alias in platform.aliasesFor(context)) {
        if (alias.aliasType != SourceAliasType.legacyType ||
            alias.legacyIntType != legacyType) {
          continue;
        }
        return SourcePlatformRef(
          platformId: platform.platformId,
          canonicalKey: platform.canonicalKey,
          displayName: platform.displayName,
          kind: platform.kind,
          matchedAlias: alias.aliasKey,
          matchedAliasType: alias.aliasType,
          legacyIntType: alias.legacyIntType,
        );
      }
    }
    return null;
  }

  Map<int, String> legacyTypeMappingsFor(SourceLookupContext context) {
    final mappings = <int, String>{};
    for (final platform in platforms) {
      for (final alias in platform.aliasesFor(context)) {
        final legacyType = alias.legacyIntType;
        if (alias.aliasType == SourceAliasType.legacyType &&
            legacyType != null) {
          mappings[legacyType] = platform.canonicalKey;
        }
      }
    }
    return mappings;
  }
}

String sourceKindFromResolvedKey(String key) {
  if (key == localSourceKey) {
    return localSourceKind;
  }
  if (key.startsWith(unknownSourceKeyPrefix)) {
    return unknownSourceKind;
  }
  return remoteSourceKind;
}

const SourcePlatformResolver sourcePlatformResolver = SourcePlatformResolver(
  <SourcePlatformDefinition>[
    SourcePlatformDefinition(
      platformId: localSourceKey,
      canonicalKey: localSourceKey,
      displayName: 'Local Library',
      kind: localSourceKind,
    ),
    SourcePlatformDefinition(
      platformId: 'picacg',
      canonicalKey: 'picacg',
      displayName: 'PicACG',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: 'pica',
          aliasType: SourceAliasType.legacyKey,
        ),
        SourcePlatformAlias(
          aliasKey: '0',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 0,
          contexts: <SourceLookupContext>{
            SourceLookupContext.favorite,
            SourceLookupContext.history,
          },
        ),
      ],
    ),
    SourcePlatformDefinition(
      platformId: 'ehentai',
      canonicalKey: 'ehentai',
      displayName: 'E-Hentai',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: 'e-hentai',
          aliasType: SourceAliasType.displayName,
        ),
        SourcePlatformAlias(
          aliasKey: '1',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 1,
          contexts: <SourceLookupContext>{
            SourceLookupContext.favorite,
            SourceLookupContext.history,
          },
        ),
      ],
    ),
    SourcePlatformDefinition(
      platformId: 'jm',
      canonicalKey: 'jm',
      displayName: 'JM',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: '2',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 2,
          contexts: <SourceLookupContext>{
            SourceLookupContext.favorite,
            SourceLookupContext.history,
          },
        ),
      ],
    ),
    SourcePlatformDefinition(
      platformId: 'hitomi',
      canonicalKey: 'hitomi',
      displayName: 'Hitomi',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: '3',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 3,
          contexts: <SourceLookupContext>{
            SourceLookupContext.favorite,
            SourceLookupContext.history,
          },
        ),
      ],
    ),
    SourcePlatformDefinition(
      platformId: 'wnacg',
      canonicalKey: 'wnacg',
      displayName: 'WNACG',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: 'htmanga',
          aliasType: SourceAliasType.migration,
          contexts: <SourceLookupContext>{
            SourceLookupContext.imported,
            SourceLookupContext.download,
            SourceLookupContext.reader,
          },
        ),
        SourcePlatformAlias(
          aliasKey: '4',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 4,
          contexts: <SourceLookupContext>{
            SourceLookupContext.favorite,
            SourceLookupContext.history,
          },
        ),
      ],
    ),
    SourcePlatformDefinition(
      platformId: 'nhentai',
      canonicalKey: 'nhentai',
      displayName: 'NHentai',
      kind: remoteSourceKind,
      aliases: <SourcePlatformAlias>[
        SourcePlatformAlias(
          aliasKey: 'nh',
          aliasType: SourceAliasType.legacyKey,
        ),
        SourcePlatformAlias(
          aliasKey: '5',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 5,
          contexts: <SourceLookupContext>{SourceLookupContext.history},
        ),
        SourcePlatformAlias(
          aliasKey: '6',
          aliasType: SourceAliasType.legacyType,
          legacyIntType: 6,
          contexts: <SourceLookupContext>{SourceLookupContext.favorite},
        ),
      ],
    ),
  ],
);
