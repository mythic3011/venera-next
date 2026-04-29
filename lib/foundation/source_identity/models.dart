import 'constants.dart';
import 'source_platform_resolver.dart';

const List<SourceLookupContext> sourceTypeCompatibilityContexts =
    <SourceLookupContext>[
      SourceLookupContext.favorite,
      SourceLookupContext.history,
    ];

final Map<int, String> legacySourceTypeSourceKeys = sourcePlatformResolver
    .legacyTypeMappingsForContexts(sourceTypeCompatibilityContexts);

class SourceIdentityAudit {
  final String? source;
  final String? loadedFrom;
  final String? declaredVersion;
  final Map<String, Object?> metadata;

  const SourceIdentityAudit({
    this.source,
    this.loadedFrom,
    this.declaredVersion,
    this.metadata = const <String, Object?>{},
  });

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'loadedFrom': loadedFrom,
      'declaredVersion': declaredVersion,
      'metadata': metadata,
    };
  }

  factory SourceIdentityAudit.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    return SourceIdentityAudit(
      source: json['source'] as String?,
      loadedFrom: json['loadedFrom'] as String?,
      declaredVersion: json['declaredVersion'] as String?,
      metadata: metadata is Map<String, dynamic>
          ? Map<String, Object?>.from(metadata)
          : const <String, Object?>{},
    );
  }
}

class SourceIdentity {
  final String schema;
  final String id;
  final String kind;
  final String key;
  final List<String> aliases;
  final List<String> names;
  final String? version;
  final SourceIdentityAudit? audit;

  const SourceIdentity({
    required this.schema,
    required this.id,
    required this.kind,
    required this.key,
    required this.aliases,
    required this.names,
    required this.version,
    required this.audit,
  });

  factory SourceIdentity.legacy({
    required String key,
    String? id,
    String? kind,
    Iterable<String> aliases = const <String>[],
    Iterable<String> names = const <String>[],
    String? version,
    SourceIdentityAudit? audit,
  }) {
    final resolved = resolveSourcePlatformKey(key);
    final resolvedKind = kind ?? resolved.kind;
    final resolvedId = id ?? resolved.canonicalKey;
    return SourceIdentity(
      schema: sourceIdentitySchemaVersion,
      id: resolvedId,
      kind: resolvedKind,
      key: key,
      aliases: _dedupeStrings(<String>[
        ...aliases,
        if (resolved.canonicalKey != key) resolved.canonicalKey,
      ]),
      names: _dedupeStrings(<String>[
        ...names,
        if (resolved.isKnown) resolved.displayName,
      ]),
      version: version,
      audit: audit,
    );
  }

  factory SourceIdentity.fromJson(Map<String, dynamic> json) {
    final aliases = json['aliases'];
    final names = json['names'];
    final audit = json['audit'];
    final key = json['key'] as String;
    final resolved = resolveSourcePlatformKey(key);
    return SourceIdentity(
      schema: (json['schema'] as String?) ?? sourceIdentitySchemaVersion,
      id: (json['id'] as String?) ?? resolved.canonicalKey,
      kind: (json['kind'] as String?) ?? resolved.kind,
      key: key,
      aliases: aliases is List
          ? _dedupeStrings(aliases.whereType<String>())
          : const <String>[],
      names: names is List
          ? _dedupeStrings(names.whereType<String>())
          : const <String>[],
      version: json['version'] as String?,
      audit: audit is Map<String, dynamic>
          ? SourceIdentityAudit.fromJson(audit)
          : null,
    );
  }

  int get typeValue => sourceTypeValueFromStableId(id, kind: kind);

  List<String> get knownKeys => _dedupeStrings(
    <String>[key, id, ...aliases].map(
      (value) => normalizeLegacyImportedSourceKey(
        value,
        context: SourceLookupContext.global,
      ),
    ),
  );

  bool matchesKey(String candidate) {
    final normalized = normalizeLegacyImportedSourceKey(
      candidate,
      context: SourceLookupContext.global,
    );
    return knownKeys.contains(normalized);
  }

  Map<String, dynamic> toJson() {
    return {
      'schema': schema,
      'id': id,
      'kind': kind,
      'key': key,
      'aliases': aliases,
      'names': names,
      'version': version,
      'audit': audit?.toJson(),
    };
  }
}

List<String> _dedupeStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    result.add(value);
  }
  return result;
}

String sourceKindFromKey(String key) {
  return resolveSourcePlatformKey(key).kind;
}

int stableSourceKeyId(String key) {
  if (isLocalSourceKey(key)) {
    return 0;
  }
  var hash = 0x811c9dc5;
  for (final byte in key.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int sourceTypeValueFromStableId(
  String stableId, {
  String kind = remoteSourceKind,
}) {
  if (kind == localSourceKind || isLocalSourceKey(stableId)) {
    return 0;
  }
  final unknownTypeValue = parseUnknownSourceTypeValue(stableId);
  if (unknownTypeValue != null) {
    return unknownTypeValue;
  }
  return stableSourceKeyId(stableId);
}

int sourceTypeValueFromKey(String key) {
  final resolved = resolveSourcePlatformKey(key);
  return sourceTypeValueFromStableId(
    resolved.canonicalKey,
    kind: resolved.kind,
  );
}

String sourceKeyFromTypeValue(int typeValue) {
  if (typeValue == 0) {
    return localSourceKey;
  }
  return '$unknownSourceKeyPrefix$typeValue';
}

SourceIdentity sourceIdentityFromKey(
  String key, {
  Iterable<String> aliases = const <String>[],
  Iterable<String> names = const <String>[],
  String? version,
  SourceIdentityAudit? audit,
}) {
  return SourceIdentity.legacy(
    key: key,
    aliases: aliases,
    names: names,
    version: version,
    audit: audit,
  );
}

SourcePlatformRef resolveSourcePlatformKey(
  String key, {
  SourceLookupContext context = SourceLookupContext.global,
}) {
  return sourcePlatformResolver.resolveKey(key, context: context);
}

bool isLocalSourceKey(String key) =>
    resolveSourcePlatformKey(key).canonicalKey == localSourceKey;

bool isUnknownSourceKey(String key) => key.startsWith(unknownSourceKeyPrefix);

int? parseUnknownSourceTypeValue(String key) {
  if (!isUnknownSourceKey(key)) {
    return null;
  }
  return int.tryParse(key.substring(unknownSourceKeyPrefix.length));
}

int normalizeFavoriteJsonTypeValue({
  required int typeValue,
  required String coverPath,
}) {
  if (typeValue == 0 && !coverPath.startsWith('http')) {
    return 0;
  }
  return normalizeLegacySourceTypeValue(
    typeValue,
    context: SourceLookupContext.favorite,
  );
}

int normalizeLegacyHistoryTypeValue(int typeValue) {
  return normalizeLegacySourceTypeValue(
    typeValue,
    context: SourceLookupContext.history,
  );
}

int normalizeLegacySourceTypeValue(
  int typeValue, {
  required SourceLookupContext context,
}) {
  final resolved = sourcePlatformResolver.resolveLegacyType(
    typeValue,
    context: context,
  );
  if (resolved == null) {
    return typeValue;
  }
  return sourceTypeValueFromKey(resolved.canonicalKey);
}

SourcePlatformRef? resolveCompatibleSourceTypeValue(int typeValue) {
  return sourcePlatformResolver.resolveLegacyTypeAcrossContexts(
    typeValue,
    contexts: sourceTypeCompatibilityContexts,
  );
}

String normalizeLegacyImportedSourceKey(
  String sourceKey, {
  SourceLookupContext context = SourceLookupContext.imported,
}) {
  return resolveSourcePlatformKey(sourceKey, context: context).canonicalKey;
}

bool matchesSourceTypeValue({
  required String sourceKey,
  required int typeValue,
}) {
  final resolved = resolveSourcePlatformKey(sourceKey);
  final candidates = <String>{
    sourceKey,
    resolved.canonicalKey,
    if (resolved.matchedAlias.isNotEmpty) resolved.matchedAlias,
  };
  for (final candidate in candidates) {
    if (sourceTypeValueFromKey(candidate) == typeValue ||
        candidate.hashCode == typeValue) {
      return true;
    }
  }
  return false;
}

bool matchesSourceIdentityTypeValue({
  required SourceIdentity identity,
  required int typeValue,
}) {
  if (identity.typeValue == typeValue) {
    return true;
  }
  for (final key in identity.knownKeys) {
    if (matchesSourceTypeValue(sourceKey: key, typeValue: typeValue)) {
      return true;
    }
  }
  return false;
}
