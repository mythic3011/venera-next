import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_install_command.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart'
    as djs;
import 'package:venera/network/app_dio.dart';
import 'package:venera/utils/io.dart';

typedef SourceInstallFromJs =
    Future<void> Function(String sourceJs, String fileName);
typedef DirectJsInstallExecutor =
    Future<djs.SourceCommandResult> Function(DirectJsInstallRequest request);
typedef SourceFetchText = Future<String> Function(String url);
typedef SourceFilePicker = Future<FileSelectResult?> Function();
typedef SourceRepositoryStoreProvider = UnifiedComicsStore? Function();

const _defaultSourceRepositories = <({String name, String url})>[
  (
    name: 'Official Venera Configs',
    url:
        'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json',
  ),
  (
    name: 'Mythic Venera Configs',
    url:
        'https://cdn.jsdelivr.net/gh/mythic3011/venera-configs@main/index.json',
  ),
];
const _repositoryRefreshFailedCode = 'repository_refresh_failed';
const _repositorySchemaUnsupportedCode = 'REPOSITORY_SCHEMA_UNSUPPORTED';
const _repositoryPackageUrlInvalidCode = 'REPOSITORY_PACKAGE_URL_INVALID';
const repositoryUrlInvalidCode = 'REPOSITORY_URL_INVALID';

class SourceCommandFailed implements Exception {
  const SourceCommandFailed({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'SourceCommandFailed($code): $message';
}

class SourceRepositoryIndexException implements Exception {
  const SourceRepositoryIndexException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SourceRepositoryIndexException($code): $message';
}

class SourceRepositoryView {
  const SourceRepositoryView({
    required this.id,
    required this.name,
    required this.indexUrl,
    required this.enabled,
    required this.userAdded,
    required this.trustLevel,
    this.lastRefreshAtMs,
    this.lastRefreshStatus,
    this.lastErrorCode,
  });

  factory SourceRepositoryView.fromRecord(SourceRepositoryRecord record) {
    return SourceRepositoryView(
      id: record.id,
      name: record.name,
      indexUrl: record.indexUrl,
      enabled: record.enabled,
      userAdded: record.userAdded,
      trustLevel: record.trustLevel,
      lastRefreshAtMs: record.lastRefreshAtMs,
      lastRefreshStatus: record.lastRefreshStatus,
      lastErrorCode: record.lastErrorCode,
    );
  }

  final String id;
  final String name;
  final String indexUrl;
  final bool enabled;
  final bool userAdded;
  final String trustLevel;
  final int? lastRefreshAtMs;
  final String? lastRefreshStatus;
  final String? lastErrorCode;
}

class SourcePackageView {
  const SourcePackageView({
    required this.sourceKey,
    required this.repositoryId,
    required this.name,
    this.fileName,
    this.scriptUrl,
    this.availableVersion,
    this.description,
    this.contentHash,
    required this.lastSeenAtMs,
  });

  factory SourcePackageView.fromRecord(SourcePackageRecord record) {
    return SourcePackageView(
      sourceKey: record.sourceKey,
      repositoryId: record.repositoryId,
      name: record.name,
      fileName: record.fileName,
      scriptUrl: record.scriptUrl,
      availableVersion: record.availableVersion,
      description: record.description,
      contentHash: record.contentHash,
      lastSeenAtMs: record.lastSeenAtMs,
    );
  }

  final String sourceKey;
  final String repositoryId;
  final String name;
  final String? fileName;
  final String? scriptUrl;
  final String? availableVersion;
  final String? description;
  final String? contentHash;
  final int lastSeenAtMs;
}

class RepositoryRefreshSummary {
  const RepositoryRefreshSummary({
    required this.refreshedRepositoryCount,
    required this.packageCount,
    required this.skippedCount,
  });

  final int refreshedRepositoryCount;
  final int packageCount;
  final int skippedCount;
}

class _RepositoryRefreshResult {
  const _RepositoryRefreshResult({
    required this.packageCount,
    required this.skippedCount,
  });

  final int packageCount;
  final int skippedCount;
}

class _ExtractedPackages {
  const _ExtractedPackages({required this.records, required this.skippedCount});

  final List<SourcePackageRecord> records;
  final int skippedCount;
}

Future<String> _defaultSourceFetchText(String url) async {
  final res = await AppDio().get<String>(
    url,
    options: Options(
      responseType: ResponseType.plain,
      headers: {'cache-time': 'no'},
    ),
  );
  final data = res.data;
  if (res.statusCode != 200 || data == null) {
    throw Exception('Failed to fetch source config');
  }
  return data;
}

Future<void> _defaultInstallSourceFromJs(
  String sourceJs,
  String fileName,
) async {
  // Legacy installer convergence remains deferred to a dedicated follow-up lane.
  final source = await ComicSourceParser().createAndParse(sourceJs, fileName);
  ComicSourceManager().add(source);
  _addAllPagesWithComicSource(source);
  appdata.saveData();
  App.forceRebuild();
}

Future<FileSelectResult?> _defaultPickJsConfigFile() {
  return selectFile(ext: const ['js']);
}

class SourceManagementController {
  SourceManagementController({
    SourceInstallFromJs? installSourceFromJs,
    DirectJsInstallExecutor? directJsInstallExecutor,
    SourceFetchText? fetchText,
    SourceFilePicker? pickJsConfigFile,
    SourceRepositoryStoreProvider? repositoryStoreProvider,
  }) : _installSourceFromJs =
           installSourceFromJs ?? _defaultInstallSourceFromJs,
       _directJsInstallExecutor =
           directJsInstallExecutor ??
           ((request) => DirectJsInstallCommand(
             adapter: ProductionDirectJsSourceWriteAdapter(),
           ).execute(request)),
       _fetchText = fetchText ?? _defaultSourceFetchText,
       _pickJsConfigFile = pickJsConfigFile ?? _defaultPickJsConfigFile,
       _repositoryStoreProvider =
           repositoryStoreProvider ?? (() => App.unifiedComicsStoreOrNull);

  final SourceInstallFromJs _installSourceFromJs;
  final DirectJsInstallExecutor _directJsInstallExecutor;
  final SourceFetchText _fetchText;
  final SourceFilePicker _pickJsConfigFile;
  final SourceRepositoryStoreProvider _repositoryStoreProvider;
  static final Map<String, Future<void>> _repositoryRefreshLocks =
      <String, Future<void>>{};
  @visibleForTesting
  static bool debugHasRepositoryRefreshLock(String repositoryId) =>
      _repositoryRefreshLocks.containsKey(repositoryId);

  Future<void> addSourceFromUrl(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return;
    }
    final parts = normalized.split('/')..removeWhere((e) => e.isEmpty);
    final fileName = parts.isNotEmpty ? parts.last : 'source.js';
    final sourceJs = await _fetchText(normalized);
    await _installSourceFromJs(sourceJs, fileName);
  }

  Future<void> addSourceFromConfigFile() async {
    final file = await _pickJsConfigFile();
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    final sourceJs = utf8.decode(bytes);
    await _installSourceFromJs(sourceJs, file.name);
  }

  bool get supportsDirectJsInstall => true;

  Future<djs.SourceCommandResult> installValidatedDirectSource({
    required String sourceUrl,
    required djs.DirectJsValidationMetadata validatedMetadata,
    required bool confirmInstall,
    bool allowOverwrite = false,
  }) async {
    final normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.isEmpty) {
      return const djs.SourceCommandFailed(
        code: djs.sourceScriptUrlInvalidCode,
        message: 'Source script URL is invalid',
      );
    }
    final String sourceJs;
    try {
      sourceJs = await _fetchText(normalizedUrl);
    } catch (_) {
      return const djs.SourceCommandFailed(
        code: djs.sourceScriptFetchFailedCode,
        message: 'Failed to fetch direct JavaScript source',
      );
    }
    final parsedMetadata = djs.extractDirectJsValidationMetadataFromScript(
      sourceJs,
    );
    final djs.SourceCommandResult result;
    try {
      result = await _directJsInstallExecutor(
        DirectJsInstallRequest(
          sourceUrl: normalizedUrl,
          sourceScript: sourceJs,
          validatedMetadata: validatedMetadata,
          parsedSourceKey: parsedMetadata.sourceKey,
          confirmInstall: confirmInstall,
          allowOverwrite: allowOverwrite,
        ),
      );
    } catch (_) {
      return const djs.SourceCommandFailed(
        code: sourceInstallBlockedCode,
        message: 'Direct JS install failed',
      );
    }
    if (result is djs.SourceCommandSuccess) {
      final source = ComicSource.find(result.metadata.sourceKey);
      if (source != null) {
        _addAllPagesWithComicSource(source);
      }
      appdata.saveData();
      App.forceRebuild();
    }
    return result;
  }

  Future<int> checkUpdates() async {
    final installed = ComicSource.all();
    if (installed.isEmpty) {
      return 0;
    }
    final listUrl = await _resolvePrimarySourceIndexUrl();
    final payload = await _fetchText(listUrl);
    final versions = _extractSourceVersions(payload);
    final shouldUpdate = <String, String>{};
    for (final source in installed) {
      final next = versions[source.key];
      if (next != null && compareSemVer(next, source.version)) {
        shouldUpdate[source.key] = next;
      }
    }
    if (shouldUpdate.isNotEmpty) {
      ComicSourceManager().updateAvailableUpdates(shouldUpdate);
    }
    return shouldUpdate.length;
  }

  Future<List<SourceRepositoryView>> listRepositories() async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      return const <SourceRepositoryView>[];
    }
    await _ensureRepositoryRegistrySeeded(store);
    final rows = await store.loadSourceRepositories();
    return rows.map(SourceRepositoryView.fromRecord).toList(growable: false);
  }

  Future<SourceRepositoryView> addRepository(
    String indexUrl, {
    String? name,
    bool userAdded = true,
    String trustLevel = 'user',
    bool enabled = true,
  }) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      throw StateError('Unified store unavailable');
    }
    await _ensureRepositoryRegistrySeeded(store);
    final normalizedUrl = indexUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw const SourceCommandFailed(
        code: repositoryUrlInvalidCode,
        message: 'Repository URL must not be empty',
      );
    }
    final parsed = Uri.tryParse(normalizedUrl);
    if (parsed == null || parsed.scheme.toLowerCase() != 'https') {
      throw const SourceCommandFailed(
        code: repositoryUrlInvalidCode,
        message: 'Repository URL must use HTTPS',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _repositoryIdFromUrl(normalizedUrl);
    final existing = await store.loadSourceRepositoryById(id);
    final record = SourceRepositoryRecord(
      id: id,
      name: (name ?? _nameFromRepositoryUrl(normalizedUrl)).trim(),
      indexUrl: normalizedUrl,
      enabled: enabled,
      userAdded: userAdded,
      trustLevel: trustLevel,
      lastRefreshAtMs: existing?.lastRefreshAtMs,
      lastRefreshStatus: existing?.lastRefreshStatus ?? 'never',
      lastErrorCode: existing?.lastErrorCode,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    await store.upsertSourceRepository(record);
    return SourceRepositoryView.fromRecord(record);
  }

  Future<int> refreshRepository(String repositoryId) async {
    final result = await _runSerializedRepositoryRefresh(
      repositoryId,
      () => _refreshRepositoryUnsafe(repositoryId),
    );
    return result.packageCount;
  }

  Future<List<SourcePackageView>> listAvailablePackages({
    String? repositoryId,
  }) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      return const <SourcePackageView>[];
    }
    final rows = await store.loadSourcePackages(repositoryId: repositoryId);
    return rows.map(SourcePackageView.fromRecord).toList(growable: false);
  }

  Future<void> refreshRepositories({bool enabledOnly = true}) async {
    await refreshRepositoriesSummary(enabledOnly: enabledOnly);
  }

  Future<RepositoryRefreshSummary> refreshRepositoriesSummary({
    bool enabledOnly = true,
  }) async {
    final repositories = await listRepositories();
    final targets = enabledOnly
        ? repositories.where((repo) => repo.enabled).toList(growable: false)
        : repositories;
    AppDiagnostics.info(
      'source.management',
      'repository.refresh.start',
      data: {
        'enabledOnly': enabledOnly,
      },
    );
    AppDiagnostics.info(
      'source.management',
      'repository.refresh.repositoryCount',
      data: {
        'enabledOnly': enabledOnly,
        'repositoryCount': repositories.length,
        'selectedRepositoryCount': targets.length,
      },
    );
    var totalPackages = 0;
    var totalSkipped = 0;
    for (final repo in targets) {
      final result = await _runSerializedRepositoryRefresh(
        repo.id,
        () => _refreshRepositoryUnsafe(repo.id),
      );
      totalPackages += result.packageCount;
      totalSkipped += result.skippedCount;
    }
    return RepositoryRefreshSummary(
      refreshedRepositoryCount: targets.length,
      packageCount: totalPackages,
      skippedCount: totalSkipped,
    );
  }

  Future<_RepositoryRefreshResult> _refreshRepositoryUnsafe(
    String repositoryId,
  ) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      throw StateError('Unified store unavailable');
    }
    await _ensureRepositoryRegistrySeeded(store);
    final repo = await store.loadSourceRepositoryById(repositoryId);
    if (repo == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final payload = await _fetchText(repo.indexUrl);
      final extracted = _extractSourcePackages(
        repositoryId: repo.id,
        repositoryIndexUrl: repo.indexUrl,
        payload: payload,
        nowMs: now,
      );
      await store.replaceSourcePackagesForRepository(
        repositoryId: repo.id,
        records: extracted.records,
      );
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: repo.id,
          name: repo.name,
          indexUrl: repo.indexUrl,
          enabled: repo.enabled,
          userAdded: repo.userAdded,
          trustLevel: repo.trustLevel,
          lastRefreshAtMs: now,
          lastRefreshStatus: 'success',
          lastErrorCode: null,
          createdAtMs: repo.createdAtMs,
          updatedAtMs: now,
        ),
      );
      AppDiagnostics.info(
        'source.management',
        'repository.refresh.package.count',
        data: {
          'repositoryId': repo.id,
          'repositoryUrl': repo.indexUrl,
          'packageCount': extracted.records.length,
          'skippedCount': extracted.skippedCount,
        },
      );
      return _RepositoryRefreshResult(
        packageCount: extracted.records.length,
        skippedCount: extracted.skippedCount,
      );
    } catch (error) {
      final schemaError = switch (error) {
        SourceRepositoryIndexException(:final code) => code,
        _ => null,
      };
      AppDiagnostics.warn(
        'source.management',
        'repository.refresh.package.schemaError',
        data: {
          'repositoryId': repo.id,
          'repositoryUrl': repo.indexUrl,
          'schemaError': schemaError,
          'error': error.toString(),
        },
      );
      final errorCode = switch (error) {
        SourceRepositoryIndexException(:final code) => code,
        _ => _repositoryRefreshFailedCode,
      };
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: repo.id,
          name: repo.name,
          indexUrl: repo.indexUrl,
          enabled: repo.enabled,
          userAdded: repo.userAdded,
          trustLevel: repo.trustLevel,
          lastRefreshAtMs: now,
          lastRefreshStatus: 'failed',
          lastErrorCode: errorCode,
          createdAtMs: repo.createdAtMs,
          updatedAtMs: now,
        ),
      );
      rethrow;
    }
  }

  Future<T> _runSerializedRepositoryRefresh<T>(
    String repositoryId,
    Future<T> Function() action,
  ) async {
    final previous = _repositoryRefreshLocks[repositoryId] ?? Future.value();
    final gate = Completer<void>();
    final lockFuture = previous.then((_) => gate.future);
    _repositoryRefreshLocks[repositoryId] = lockFuture;
    try {
      await previous;
      return await action();
    } finally {
      gate.complete();
      if (identical(_repositoryRefreshLocks[repositoryId], lockFuture)) {
        _repositoryRefreshLocks.remove(repositoryId);
      }
    }
  }

  Future<void> removeRepository(String repositoryId) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      throw StateError('Unified store unavailable');
    }
    await store.deleteSourceRepository(repositoryId);
  }

  Future<SourceRepositoryView> setRepositoryEnabled(
    String repositoryId,
    bool enabled,
  ) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      throw StateError('Unified store unavailable');
    }
    final repo = await store.loadSourceRepositoryById(repositoryId);
    if (repo == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    final updated = SourceRepositoryRecord(
      id: repo.id,
      name: repo.name,
      indexUrl: repo.indexUrl,
      enabled: enabled,
      userAdded: repo.userAdded,
      trustLevel: repo.trustLevel,
      lastRefreshAtMs: repo.lastRefreshAtMs,
      lastRefreshStatus: repo.lastRefreshStatus,
      lastErrorCode: repo.lastErrorCode,
      createdAtMs: repo.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await store.upsertSourceRepository(updated);
    return SourceRepositoryView.fromRecord(updated);
  }

  Future<String> loadPrimaryRepositoryUrl() async {
    final primary = await _loadPrimaryRepository();
    return primary?.indexUrl ?? _defaultSourceRepositories.first.url;
  }

  Future<void> setPrimaryRepositoryUrl(String indexUrl) async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      return;
    }
    await _ensureRepositoryRegistrySeeded(store);
    final normalizedUrl = indexUrl.trim();
    if (normalizedUrl.isEmpty) {
      return;
    }
    final repositories = await store.loadSourceRepositories();
    final current = repositories.cast<SourceRepositoryRecord?>().firstWhere(
      (repo) => repo?.enabled == true,
      orElse: () => repositories.isEmpty ? null : repositories.first,
    );
    final replacement = await addRepository(
      normalizedUrl,
      name: current?.name,
      userAdded: current?.userAdded ?? true,
      trustLevel: current?.trustLevel ?? 'user',
      enabled: true,
    );
    if (current != null && current.id != replacement.id) {
      await store.deleteSourceRepository(current.id);
    }
  }

  Future<String> _resolvePrimarySourceIndexUrl() async {
    return loadPrimaryRepositoryUrl();
  }

  Future<void> _ensureRepositoryRegistrySeeded(UnifiedComicsStore store) async {
    final current = await store.loadSourceRepositories();
    if (current.isNotEmpty) {
      return;
    }
    final fromSettings = _readLegacySourceListUrl();
    final now = DateTime.now().millisecondsSinceEpoch;
    final legacyUri = Uri.tryParse(fromSettings);
    final isValidLegacySeed =
        legacyUri != null &&
        legacyUri.hasScheme &&
        legacyUri.scheme.toLowerCase() == 'https' &&
        legacyUri.host.isNotEmpty;
    if (fromSettings.isNotEmpty && isValidLegacySeed) {
      AppDiagnostics.info(
        'source.management',
        'source.repository.registry.legacy_seed_hit',
        data: {
          'seedUrl': fromSettings,
          'seedSource': 'comicSourceListUrl',
        },
      );
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: _repositoryIdFromUrl(fromSettings),
          name: 'Legacy Source Repository',
          indexUrl: fromSettings,
          enabled: true,
          userAdded: false,
          trustLevel: 'official',
          lastRefreshStatus: 'never',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      return;
    }
    if (fromSettings.isEmpty) {
      AppDiagnostics.info(
        'source.management',
        'source.repository.registry.legacy_seed_miss',
        data: {'seedSource': 'comicSourceListUrl'},
      );
    } else {
      AppDiagnostics.info(
        'source.management',
        'source.repository.registry.legacy_seed_invalid',
        data: {
          'seedUrl': fromSettings,
          'seedSource': 'comicSourceListUrl',
        },
      );
    }
    for (final repo in _defaultSourceRepositories) {
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: _repositoryIdFromUrl(repo.url),
          name: repo.name,
          indexUrl: repo.url,
          enabled: true,
          userAdded: false,
          trustLevel: 'official',
          lastRefreshStatus: 'never',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
    }
  }

  Future<SourceRepositoryView?> _loadPrimaryRepository() async {
    final store = _repositoryStoreProvider();
    if (store == null) {
      return null;
    }
    await _ensureRepositoryRegistrySeeded(store);
    final repositories = await store.loadSourceRepositories();
    final enabled = repositories.where((repo) => repo.enabled);
    final primary = enabled.isNotEmpty
        ? enabled.first
        : (repositories.isEmpty ? null : repositories.first);
    if (primary != null) {
      AppDiagnostics.info(
        'source.management',
        'source.repository.registry.canonical_hit',
        data: {
          'repositoryId': primary.id,
          'repositoryUrl': primary.indexUrl,
        },
      );
      return SourceRepositoryView.fromRecord(primary);
    }
    return null;
  }

  String _readLegacySourceListUrl() {
    recordAppdataAuthorityDiagnostic(
      channel: 'appdata.audit',
      event: 'appdata.authority.access',
      key: 'comicSourceListUrl',
      storage: AppdataAuditStorage.settings,
      access: 'read',
      data: const <String, Object?>{'owner': 'SourceManagementController'},
    );
    final raw = appdata.settings['comicSourceListUrl'];
    final value = raw is String ? raw.trim() : '';
    if (value.contains('git.nyne.dev')) {
      return _defaultSourceRepositories.first.url;
    }
    return value;
  }

  String _repositoryIdFromUrl(String url) {
    final digest = sha256.convert(utf8.encode(url.trim())).toString();
    return 'repo_$digest';
  }

  String _nameFromRepositoryUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final host = uri?.host.trim();
    if (host != null && host.isNotEmpty) {
      return host;
    }
    return 'Custom Repository';
  }

  Map<String, String> _extractSourceVersions(String payload) {
    final entries = _sourceEntriesFromPayload(payload);
    final versions = <String, String>{};
    for (final item in entries) {
      if (item is! Map) {
        continue;
      }
      final key = item['key']?.toString();
      final version = item['version']?.toString();
      if (key != null &&
          key.isNotEmpty &&
          version != null &&
          version.isNotEmpty) {
        versions[key] = version;
      }
    }
    return versions;
  }

  _ExtractedPackages _extractSourcePackages({
    required String repositoryId,
    required String repositoryIndexUrl,
    required String payload,
    required int nowMs,
  }) {
    final entries = _sourceEntriesFromPayload(payload);
    final baseUri = Uri.parse(repositoryIndexUrl);
    final repositoryBaseUrl = baseUri.resolve('./').toString();
    final records = <SourcePackageRecord>[];
    var skippedCount = 0;
    for (final item in entries) {
      if (item is! Map) {
        skippedCount++;
        AppDiagnostics.warn(
          'source.management',
          'repository.refresh.package.skipped',
          data: {
            'repositoryId': repositoryId,
            'repositoryUrl': repositoryIndexUrl,
            'reason': 'entry_not_map',
          },
        );
        continue;
      }
      final key = item['key']?.toString().trim();
      final rawName = item['name']?.toString().trim();
      if (key == null || key.isEmpty) {
        skippedCount++;
        AppDiagnostics.warn(
          'source.management',
          'repository.refresh.package.skipped',
          data: {
            'repositoryId': repositoryId,
            'repositoryUrl': repositoryIndexUrl,
            'reason': 'missing_key',
          },
        );
        continue;
      }
      final name = (rawName == null || rawName.isEmpty) ? key : rawName;
      final fileName = item['fileName']?.toString().trim();
      final inlineUrl = item['url']?.toString().trim();
      String? scriptUrl;
      if (inlineUrl != null && inlineUrl.isNotEmpty) {
        scriptUrl = _validatedHttpsUrl(inlineUrl);
      } else if (fileName != null && fileName.isNotEmpty) {
        final resolved = baseUri.resolve(fileName).toString();
        if (!resolved.startsWith(repositoryBaseUrl)) {
          throw const SourceRepositoryIndexException(
            _repositoryPackageUrlInvalidCode,
            'fileName resolved outside repository base path',
          );
        }
        scriptUrl = _validatedHttpsUrl(resolved);
      }
      AppDiagnostics.trace(
        'source.management',
        'repository.refresh.package.sourceUrl',
        data: {
          'repositoryId': repositoryId,
          'repositoryUrl': repositoryIndexUrl,
          'sourceKey': key,
          'sourceUrl': scriptUrl,
        },
      );
      records.add(
        SourcePackageRecord(
          sourceKey: key,
          repositoryId: repositoryId,
          name: name,
          fileName: fileName == null || fileName.isEmpty ? null : fileName,
          scriptUrl: scriptUrl,
          availableVersion: item['version']?.toString(),
          description: item['description']?.toString(),
          contentHash: item['contentHash']?.toString(),
          lastSeenAtMs: nowMs,
        ),
      );
    }
    return _ExtractedPackages(records: records, skippedCount: skippedCount);
  }

  List<dynamic> _sourceEntriesFromPayload(String payload) {
    final decoded = jsonDecode(payload);
    return _sourceEntriesFromDecodedIndex(decoded);
  }

  List<dynamic> _sourceEntriesFromDecodedIndex(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion != null && schemaVersion != 1) {
        throw SourceRepositoryIndexException(
          _repositorySchemaUnsupportedCode,
          'Unsupported schemaVersion: $schemaVersion',
        );
      }
      final sources = decoded['sources'];
      if (sources is List) {
        return sources;
      }
      final packages = decoded['packages'];
      if (packages is List) {
        return packages;
      }
    }
    throw const SourceRepositoryIndexException(
      _repositorySchemaUnsupportedCode,
      'Invalid source index payload',
    );
  }

  String _validatedHttpsUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme.toLowerCase() != 'https') {
      throw const SourceRepositoryIndexException(
        _repositoryPackageUrlInvalidCode,
        'Package URL must use HTTPS',
      );
    }
    return parsed.toString();
  }
}

void _addAllPagesWithComicSource(ComicSource source) {
  final explorePages = appdata.settings['explore_pages'];
  final categoryPages = appdata.settings['categories'];
  final networkFavorites = appdata.settings['favorites'];
  final searchPages = appdata.settings['searchSources'];

  if (source.explorePages.isNotEmpty) {
    for (final page in source.explorePages) {
      if (!explorePages.contains(page.title)) {
        explorePages.add(page.title);
      }
    }
  }
  if (source.categoryData != null &&
      !categoryPages.contains(source.categoryData!.key)) {
    categoryPages.add(source.categoryData!.key);
  }
  if (source.favoriteData != null &&
      !networkFavorites.contains(source.favoriteData!.key)) {
    networkFavorites.add(source.favoriteData!.key);
  }
  if (source.searchPageData != null && !searchPages.contains(source.key)) {
    searchPages.add(source.key);
  }

  appdata.settings['explore_pages'] = explorePages.toSet().toList();
  appdata.settings['categories'] = categoryPages.toSet().toList();
  appdata.settings['favorites'] = networkFavorites.toSet().toList();
  appdata.settings['searchSources'] = searchPages.toSet().toList();
}
