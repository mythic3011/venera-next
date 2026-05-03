import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart'
    as djs;
import 'package:venera/features/sources/comic_source/source_management_controller.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/pages/webview.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

class ComicSourcePage extends StatelessWidget {
  const ComicSourcePage({
    super.key,
    this.controller,
    this.validateDirectSourceUrl,
  });

  final SourceManagementController? controller;
  final Future<djs.SourceCommandResult> Function(String url)?
  validateDirectSourceUrl;

  static Future<void> update(
    ComicSource source, {
    BuildContext? context,
    bool showLoading = true,
  }) async {
    final uiContext = context;
    if (!source.url.isURL) {
      if (showLoading) {
        if (uiContext == null || !uiContext.mounted) {
          throw Exception("UI context is unavailable");
        }
        uiContext.showMessage(message: "Invalid url config");
        return;
      } else {
        throw Exception("Invalid url config");
      }
    }
    ComicSourceManager().remove(source.key);
    bool cancel = false;
    LoadingDialogController? controller;
    if (showLoading) {
      if (uiContext == null || !uiContext.mounted) {
        throw Exception("UI context is unavailable");
      }
      controller = showLoadingDialog(
        uiContext,
        onCancel: () => cancel = true,
        barrierDismissible: false,
      );
    }
    try {
      var res = await AppDio().get<String>(
        source.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {"cache-time": "no"},
        ),
      );
      if (cancel) return;
      controller?.close();
      await ComicSourceParser().parse(res.data!, source.filePath);
      await io.File(source.filePath).writeAsString(res.data!);
      if (ComicSourceManager().availableUpdates.containsKey(source.key)) {
        ComicSourceManager().availableUpdates.remove(source.key);
      }
    } catch (e) {
      if (cancel) return;
      if (showLoading) {
        if (uiContext == null || !uiContext.mounted) {
          throw Exception("UI context is unavailable");
        }
        uiContext.showMessage(message: e.toString());
      } else {
        rethrow;
      }
    }
    await ComicSourceManager().reload();
    if (showLoading) {
      App.forceRebuild();
    }
  }

  static Future<int> checkComicSourceUpdate() async {
    try {
      return await SourceManagementController().checkUpdates();
    } catch (_) {
      return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _Body(
        controller: controller ?? SourceManagementController(),
        validateDirectSourceUrl: validateDirectSourceUrl ?? _defaultValidateDirectSourceUrl,
      ),
    );
  }

  static Future<djs.SourceCommandResult> _defaultValidateDirectSourceUrl(
    String url,
  ) {
    final validator = djs.DirectJsSourceValidator(
      fetcher: (targetUrl) async {
        final res = await AppDio().get<String>(
          targetUrl,
          options: Options(responseType: ResponseType.plain),
        );
        return djs.DirectJsFetchResponse(
          statusCode: res.statusCode ?? 0,
          body: res.data ?? '',
          contentType: res.headers.value('content-type'),
        );
      },
      isolatedValidationPort: (script) async {
        return Future<djs.DirectJsValidationMetadata>(
          () => djs.extractDirectJsValidationMetadataFromScript(script),
        );
      },
    );
    return validator.validate(url);
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.controller, required this.validateDirectSourceUrl});

  final SourceManagementController controller;
  final Future<djs.SourceCommandResult> Function(String url)
  validateDirectSourceUrl;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  SourceManagementController get _sourceManagementController => widget.controller;
  List<SourceRepositoryView> _repositories = const <SourceRepositoryView>[];
  List<SourcePackageView> _availablePackages = const <SourcePackageView>[];
  bool _loadingRepositories = false;
  String? _repositoryCommandError;
  String? _repositoryRefreshSummary;
  String? _directSourceValidationMessage;
  bool _validatingDirectSource = false;
  _ValidatedDirectSource? _validatedDirectSource;
  var url = "";

  void updateUI() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ComicSourceManager().addListener(updateUI);
    _reloadRepositoryData();
  }

  @override
  void dispose() {
    super.dispose();
    ComicSourceManager().removeListener(updateUI);
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text('Comic Source'.tl), style: AppbarStyle.shadow),
        _buildDirectSourceSection(context),
        _buildRepositorySection(context),
        _buildAvailableSourcesSection(context),
        _buildInstalledSourcesSection(context),
        for (var source in ComicSource.all())
          _SliverComicSource(
            key: ValueKey(source.key),
            source: source,
            edit: edit,
            update: update,
            delete: delete,
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.padding.bottom)),
      ],
    );
  }

  Future<void> _reloadRepositoryData() async {
    if (!mounted) return;
    setState(() {
      _loadingRepositories = true;
      _repositoryCommandError = null;
    });
    try {
      final repos = await _sourceManagementController.listRepositories();
      final packages = await _sourceManagementController.listAvailablePackages();
      if (!mounted) return;
      setState(() {
        _repositories = repos;
        _availablePackages = packages;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRepositories = false;
        });
      }
    }
  }

  Future<void> _refreshRepositories() async {
    setState(() {
      _loadingRepositories = true;
      _repositoryCommandError = null;
    });
    try {
      final summary = await _sourceManagementController.refreshRepositoriesSummary();
      if (!mounted) return;
      final repos = await _sourceManagementController.listRepositories();
      final packages = await _sourceManagementController.listAvailablePackages();
      if (!mounted) return;
      setState(() {
        _repositories = repos;
        _availablePackages = packages;
        _repositoryRefreshSummary =
            'Refreshed ${summary.refreshedRepositoryCount} repos. '
            'Packages: ${summary.packageCount}, Skipped: ${summary.skippedCount}.';
      });
    } catch (error) {
      _showRepositoryCommandError(error);
      if (!mounted) return;
      try {
        final repos = await _sourceManagementController.listRepositories();
        final packages = await _sourceManagementController.listAvailablePackages();
        if (!mounted) return;
        setState(() {
          _repositories = repos;
          _availablePackages = packages;
        });
      } catch (_) {
        // Keep the last visible state if reload after a failed refresh also fails.
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingRepositories = false;
        });
      }
    }
  }

  void _showRepositoryCommandError(Object error) {
    if (!mounted) {
      return;
    }
    final message = _repositoryErrorMessage(error);
    setState(() {
      _repositoryCommandError = message;
    });
    if (!mounted) {
      return;
    }
    context.showMessage(message: message);
  }

  String _directValidationErrorMessage(Object error) {
    if (error is SourceCommandFailed) {
      return '${error.code}: ${error.message}';
    }
    return 'SOURCE_VALIDATION_FAILED: Unable to validate source URL'.tl;
  }

  String _repositoryErrorMessage(Object error) {
    if (error is SourceCommandFailed) {
      switch (error.code) {
        case repositoryUrlInvalidCode:
          return 'Invalid repository URL'.tl;
        default:
          return 'Repository command failed'.tl;
      }
    }
    if (error is SourceRepositoryIndexException) {
      switch (error.code) {
        case 'REPOSITORY_SCHEMA_UNSUPPORTED':
          return 'Repository schema unsupported'.tl;
        case 'REPOSITORY_PACKAGE_URL_INVALID':
          return 'Repository contains invalid package URL'.tl;
        default:
          return 'Repository refresh failed'.tl;
      }
    }
    return 'Repository command failed'.tl;
  }
  Widget _buildRepositorySection(BuildContext context) {
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Repositories', style: ts.s16),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _promptAddRepository,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Repository'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _loadingRepositories ? null : _refreshRepositories,
                    icon: const Icon(Icons.refresh),
                    label: Text('Refresh'.tl),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_repositoryCommandError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _repositoryCommandError!,
                    style: TextStyle(color: context.colorScheme.error),
                  ),
                ),
              if (_repositoryRefreshSummary != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_repositoryRefreshSummary!),
                ),
              if (_repositories.isEmpty && !_loadingRepositories)
                const Text('No repositories')
              else
                ..._repositories.map(
                  (repo) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(repo.name),
                    subtitle: Text(
                      [
                        repo.indexUrl,
                        'status=${repo.lastRefreshStatus ?? 'never'}',
                        if (repo.lastErrorCode != null)
                          'error=${repo.lastErrorCode}',
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: Switch(
                      value: repo.enabled,
                      onChanged: (value) async {
                        try {
                          await _sourceManagementController.setRepositoryEnabled(
                            repo.id,
                            value,
                          );
                          await _reloadRepositoryData();
                        } catch (error) {
                          _showRepositoryCommandError(error);
                        }
                      },
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          key: ValueKey('refresh-repo-${repo.id}'),
                          tooltip: 'Refresh repository',
                          onPressed: () async {
                            try {
                              await _sourceManagementController.refreshRepository(
                                repo.id,
                              );
                              await _reloadRepositoryData();
                            } catch (error) {
                              _showRepositoryCommandError(error);
                              await _reloadRepositoryData();
                            }
                          },
                          icon: const Icon(Icons.sync),
                        ),
                        IconButton(
                          tooltip: 'Remove repository',
                          onPressed: () async {
                            try {
                              await _sourceManagementController.removeRepository(
                                repo.id,
                              );
                              await _reloadRepositoryData();
                            } catch (error) {
                              _showRepositoryCommandError(error);
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptAddRepository() async {
    var repositoryUrl = '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Repository'),
        content: TextField(
          onChanged: (value) {
            repositoryUrl = value;
          },
          decoration: const InputDecoration(hintText: 'https://.../index.json'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () async {
              final url = repositoryUrl.trim();
              if (url.isEmpty) return;
              try {
                await _sourceManagementController.addRepository(url);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (!mounted) return;
                await _reloadRepositoryData();
              } catch (error) {
                _showRepositoryCommandError(error);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledSourcesSection(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('Installed Sources', style: ts.s16),
      ),
    );
  }

  Widget _buildAvailableSourcesSection(BuildContext context) {
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available Sources', style: ts.s16),
              const SizedBox(height: 8),
              const Text(
                'Repository packages are listed for review only. Install support is not enabled yet.',
              ),
              const SizedBox(height: 8),
              if (_availablePackages.isEmpty)
                const Text('No available sources')
              else
                ..._availablePackages.map(
                  (pkg) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(pkg.name),
                    subtitle: Text(
                      [
                        if (pkg.availableVersion?.isNotEmpty == true)
                          'Version: ${pkg.availableVersion}',
                        'Status: ${_reviewOnlyPackageStatus(pkg)}',
                      ].join('\n'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _reviewOnlyPackageStatus(SourcePackageView package) {
    if (ComicSource.find(package.sourceKey) != null) {
      return 'alreadyInstalled';
    }
    return 'reviewOnly/installDisabled';
  }

  void delete(ComicSource source) {
    showConfirmDialog(
      context: context,
      title: "Delete".tl,
      content: "Delete comic source '@n' ?".tlParams({"n": source.name}),
      btnColor: context.colorScheme.error,
      onConfirm: () {
        var file = File(source.filePath);
        file.delete();
        ComicSourceManager().remove(source.key);
        _validatePages();
        App.forceRebuild();
      },
    );
  }

  void edit(ComicSource source) async {
    if (App.isDesktop) {
      try {
        await Process.run("code", [source.filePath], runInShell: true);
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Reload Configs"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("cancel"),
              ),
              TextButton(
                onPressed: () async {
                  await ComicSourceManager().reload();
                  App.forceRebuild();
                },
                child: const Text("continue"),
              ),
            ],
          ),
        );
        return;
      } catch (e) {
        //
      }
    }
    context.to(
      () => _EditFilePage(source.filePath, () async {
        await ComicSourceManager().reload();
        setState(() {});
      }),
    );
  }

  void update(ComicSource source, [bool showLoading = true]) {
    ComicSourcePage.update(source, showLoading: showLoading, context: context);
  }

  Widget _buildDirectSourceSection(BuildContext context) {
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.download_for_offline_outlined),
                  const SizedBox(width: 12),
                  Text("Direct JS Validation / Install".tl, style: ts.s16),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: "URL",
                  border: const UnderlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  suffix: IconButton(
                    onPressed: _validatingDirectSource
                        ? null
                        : () => _validateDirectSourceUrl(url),
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
                ),
                onChanged: (value) {
                  url = value;
                },
                onSubmitted: _validateDirectSourceUrl,
              ).paddingBottom(8),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Text(
                  'Use repositories for source catalogs. Use direct URL or local file only when you trust the source.'
                      .tl,
                ),
              ),
              if (_directSourceValidationMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Text(_directSourceValidationMessage!),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: Icon(Icons.file_open_outlined),
                    label: Text("Use a config file".tl),
                    onPressed: _selectFile,
                  ),
                  FilledButton.tonalIcon(
                    icon: Icon(Icons.help_outline),
                    label: Text("Help".tl),
                    onPressed: help,
                  ),
                  _CheckUpdatesButton(),
                  FilledButton.tonalIcon(
                    icon: _validatingDirectSource
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: const Text("Validate Direct URL"),
                    onPressed: _validatingDirectSource
                        ? null
                        : () => _validateDirectSourceUrl(url),
                  ),
                  if (_sourceManagementController.supportsDirectJsInstall &&
                      _validatedDirectSource != null)
                    FilledButton.icon(
                      key: const ValueKey('install-validated-direct-source'),
                      icon: const Icon(Icons.download_done_outlined),
                      label: const Text('Install Source'),
                      onPressed: _confirmInstallValidatedDirectSource,
                    ),
                ],
              ).paddingVertical(8),
            ],
          ),
        ),
      ),
    );
  }

  void _selectFile() async {
    try {
      await _sourceManagementController.addSourceFromConfigFile();
      _validatePages();
    } catch (e, s) {
      context.showMessage(message: e.toString());
      AppDiagnostics.error('ui.comic_source', e, stackTrace: s, message: 'add_source_failed');
    }
  }

  void help() {
    launchUrlString(comicSourceDocUrl);
  }

  Future<void> _validateDirectSourceUrl(String rawUrl) async {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) {
      setState(() {
        _directSourceValidationMessage = 'Please enter a source URL'.tl;
        _validatedDirectSource = null;
      });
      return;
    }
    setState(() {
      _validatingDirectSource = true;
      _directSourceValidationMessage = null;
      _validatedDirectSource = null;
    });
    djs.SourceCommandResult result;
    try {
      result = await widget.validateDirectSourceUrl(normalized);
    } catch (error) {
      if (!mounted) return;
      final uiMessage = _directValidationErrorMessage(error);
      setState(() {
        _validatedDirectSource = null;
        _directSourceValidationMessage = uiMessage;
        _validatingDirectSource = false;
      });
      context.showMessage(message: uiMessage);
      return;
    }
    if (!mounted) return;
    switch (result) {
      case djs.SourceCommandSuccess(:final metadata):
        setState(() {
          _validatedDirectSource = _ValidatedDirectSource(
            sourceUrl: normalized,
            metadata: metadata,
          );
          _directSourceValidationMessage = _sourceManagementController
                  .supportsDirectJsInstall
              ? 'Validation passed. Ready to install.'.tl
              : 'Validation passed. Install unavailable.'.tl;
        });
      case djs.SourceCommandFailed(:final code, :final message):
        setState(() {
          _validatedDirectSource = null;
          _directSourceValidationMessage = '$code: $message';
        });
        context.showMessage(message: '$code: $message');
    }
    if (mounted) {
      setState(() {
        _validatingDirectSource = false;
      });
    }
  }

  Future<void> _confirmInstallValidatedDirectSource() async {
    final validated = _validatedDirectSource;
    if (validated == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Source'),
        content: Text(
          'Source Key: ${validated.metadata.sourceKey}\n'
          'Name: ${validated.metadata.name ?? '-'}\n'
          'Version: ${validated.metadata.version ?? '-'}\n\n'
          'Overwrite is disabled. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final result = await _sourceManagementController.installValidatedDirectSource(
      sourceUrl: validated.sourceUrl,
      validatedMetadata: validated.metadata,
      confirmInstall: true,
      allowOverwrite: false,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case djs.SourceCommandSuccess(:final metadata):
        try {
          await ComicSourceManager().reload();
        } catch (error, stackTrace) {
          if (_isExpectedTestFixtureReloadError(error, stackTrace)) {
            AppDiagnostics.warn(
              'source.management',
              'source.install.reload.expected_test_fixture_error',
              data: {
                'errorType': error.runtimeType.toString(),
                'error': error.toString(),
              },
            );
          } else {
            AppDiagnostics.error('ui.comic_source', error, stackTrace: stackTrace, message: 'install_reload_failed');
          }
        }
        if (mounted) {
          await _reloadRepositoryData();
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _validatedDirectSource = null;
          _directSourceValidationMessage =
              'Installed source: ${metadata.sourceKey}';
        });
        return;
      case djs.SourceCommandFailed(:final code, :final message):
        final uiMessage = _directInstallErrorMessage(code, message);
        setState(() {
          _directSourceValidationMessage = uiMessage;
        });
        return;
    }
  }

  String _directInstallErrorMessage(String code, String message) {
    switch (code) {
      case 'SOURCE_KEY_COLLISION':
        return 'SOURCE_KEY_COLLISION: Source already installed';
      default:
        return '$code: $message';
    }
  }

  bool _isExpectedTestFixtureReloadError(Object error, StackTrace stackTrace) {
    final message = error.toString();
    final stack = stackTrace.toString();
    return message.contains('Null check operator used on a null value') &&
        stack.contains('JsEngine.runCode');
  }
}

class _ValidatedDirectSource {
  const _ValidatedDirectSource({
    required this.sourceUrl,
    required this.metadata,
  });

  final String sourceUrl;
  final djs.DirectJsValidationMetadata metadata;
}

@visibleForTesting
Future<String> loadComicSourcePrimaryRepositoryUrlForTesting(
  SourceManagementController controller,
) {
  return controller.loadPrimaryRepositoryUrl();
}

@visibleForTesting
Future<void> persistComicSourcePrimaryRepositoryUrlForTesting(
  SourceManagementController controller,
  String url,
) {
  return controller.setPrimaryRepositoryUrl(url);
}

void _validatePages() {
  List explorePages = appdata.settings['explore_pages'];
  List categoryPages = appdata.settings['categories'];
  List networkFavorites = appdata.settings['favorites'];

  var totalExplorePages = ComicSource.all()
      .map((e) => e.explorePages.map((e) => e.title))
      .expand((element) => element)
      .toList();
  var totalCategoryPages = ComicSource.all()
      .map((e) => e.categoryData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();
  var totalNetworkFavorites = ComicSource.all()
      .map((e) => e.favoriteData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();

  for (var page in List.from(explorePages)) {
    if (!totalExplorePages.contains(page)) {
      explorePages.remove(page);
    }
  }
  for (var page in List.from(categoryPages)) {
    if (!totalCategoryPages.contains(page)) {
      categoryPages.remove(page);
    }
  }
  for (var page in List.from(networkFavorites)) {
    if (!totalNetworkFavorites.contains(page)) {
      networkFavorites.remove(page);
    }
  }

  appdata.settings['explore_pages'] = explorePages.toSet().toList();
  appdata.settings['categories'] = categoryPages.toSet().toList();
  appdata.settings['favorites'] = networkFavorites.toSet().toList();

  appdata.saveData();
}

class _EditFilePage extends StatefulWidget {
  const _EditFilePage(this.path, this.onExit);

  final String path;

  final void Function() onExit;

  @override
  State<_EditFilePage> createState() => __EditFilePageState();
}

class __EditFilePageState extends State<_EditFilePage> {
  var current = '';

  @override
  void initState() {
    super.initState();
    current = File(widget.path).readAsStringSync();
  }

  @override
  void dispose() {
    File(widget.path).writeAsStringSync(current);
    widget.onExit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("Edit".tl)),
      body: Column(
        children: [
          Container(height: 0.6, color: context.colorScheme.outlineVariant),
          Expanded(
            child: CodeEditor(
              initialValue: current,
              onChanged: (value) => current = value,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckUpdatesButton extends StatefulWidget {
  const _CheckUpdatesButton();

  @override
  State<_CheckUpdatesButton> createState() => _CheckUpdatesButtonState();
}

class _CheckUpdatesButtonState extends State<_CheckUpdatesButton> {
  bool isLoading = false;

  void check() async {
    setState(() {
      isLoading = true;
    });
    var count = await ComicSourcePage.checkComicSourceUpdate();
    if (!mounted) {
      return;
    }
    if (count == -1) {
      context.showMessage(message: "Network error".tl);
    } else if (count == 0) {
      context.showMessage(message: "No updates".tl);
    } else {
      showUpdateDialog();
    }
    setState(() {
      isLoading = false;
    });
  }

  void showUpdateDialog() async {
    var text = ComicSourceManager().availableUpdates.entries
        .map((e) {
          return "${ComicSource.find(e.key)!.name}: ${e.value}";
        })
        .join("\n");
    bool doUpdate = false;
    await showDialog(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: "Updates".tl,
          content: Text(text).paddingHorizontal(16),
          actions: [
            FilledButton(
              onPressed: () {
                doUpdate = true;
                context.pop();
              },
              child: Text("Update".tl),
            ),
          ],
        );
      },
    );
    if (!mounted) {
      return;
    }
    if (doUpdate) {
      var loadingController = showLoadingDialog(
        context,
        message: "Updating".tl,
        withProgress: true,
      );
      int current = 0;
      int total = ComicSourceManager().availableUpdates.length;
      try {
        var shouldUpdate = ComicSourceManager().availableUpdates.keys.toList();
        for (var key in shouldUpdate) {
          var source = ComicSource.find(key)!;
          await ComicSourcePage.update(
            source,
            context: context,
            showLoading: false,
          );
          if (!mounted) {
            loadingController.close();
            return;
          }
          current++;
          loadingController.setProgress(current / total);
        }
      } catch (e) {
        if (!mounted) {
          loadingController.close();
          return;
        }
        context.showMessage(message: e.toString());
      }
      loadingController.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.update),
      label: Text("Check updates".tl),
      onPressed: check,
    );
  }
}

class _CallbackSetting extends StatefulWidget {
  const _CallbackSetting({required this.setting, required this.sourceKey});

  final MapEntry<String, Map<String, dynamic>> setting;

  final String sourceKey;

  @override
  State<_CallbackSetting> createState() => _CallbackSettingState();
}

class _CallbackSettingState extends State<_CallbackSetting> {
  String get key => widget.setting.key;

  String get buttonText => widget.setting.value['buttonText'] ?? "Click";

  String get title => widget.setting.value['title'] ?? key;

  bool isLoading = false;

  Future<void> onClick() async {
    var func = widget.setting.value['callback'];
    var result = func([]);
    if (result is Future) {
      setState(() {
        isLoading = true;
      });
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title.ts(widget.sourceKey)),
      trailing: Button.normal(
        onPressed: onClick,
        isLoading: isLoading,
        child: Text(buttonText.ts(widget.sourceKey)),
      ).fixHeight(32),
    );
  }
}

class _SliverComicSource extends StatefulWidget {
  const _SliverComicSource({
    super.key,
    required this.source,
    required this.edit,
    required this.update,
    required this.delete,
  });

  final ComicSource source;

  final void Function(ComicSource source) edit;
  final void Function(ComicSource source) update;
  final void Function(ComicSource source) delete;

  @override
  State<_SliverComicSource> createState() => _SliverComicSourceState();
}

class _SliverComicSourceState extends State<_SliverComicSource> {
  ComicSource get source => widget.source;

  @override
  Widget build(BuildContext context) {
    var newVersion = ComicSourceManager().availableUpdates[source.key];
    bool hasUpdate =
        newVersion != null && compareSemVer(newVersion, source.version);

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(padding: const EdgeInsets.only(top: 16)),
        SliverToBoxAdapter(
          child: ListTile(
            title: Row(
              children: [
                Text(source.name, style: ts.s18),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    source.version,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (hasUpdate)
                  Tooltip(
                    message: newVersion,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "New Version".tl,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ).paddingLeft(4),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: "Edit".tl,
                  child: IconButton(
                    onPressed: () => widget.edit(source),
                    icon: const Icon(Icons.edit_note),
                  ),
                ),
                Tooltip(
                  message: "Update".tl,
                  child: IconButton(
                    onPressed: () => widget.update(source),
                    icon: const Icon(Icons.update),
                  ),
                ),
                Tooltip(
                  message: "Delete".tl,
                  child: IconButton(
                    onPressed: () => widget.delete(source),
                    icon: const Icon(Icons.delete),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(children: buildSourceSettings().toList()),
        ),
        SliverToBoxAdapter(child: Column(children: _buildAccount().toList())),
      ],
    );
  }

  Iterable<Widget> buildSourceSettings() sync* {
    // S-source-settings-runtime-boundary-1:
    // dynamic settings can run runtime JS path during widget build.
    var settingsMap = source.getSettingsDynamic() ?? source.settings;

    if (settingsMap == null) {
      return;
    } else if (source.data['settings'] == null) {
      source.data['settings'] = {};
    }
    for (var item in settingsMap.entries) {
      var key = item.key;
      String type = item.value['type'];
      try {
        if (type == "select") {
          var current = source.data['settings'][key];
          if (current == null) {
            var d = item.value['default'];
            for (var option in item.value['options']) {
              if (option['value'] == d) {
                current = option['text'] ?? option['value'];
                break;
              }
            }
          } else {
            current =
                item.value['options'].firstWhere(
                  (e) => e['value'] == current,
                )['text'] ??
                current;
          }
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            trailing: Select(
              current: (current as String).ts(source.key),
              values: (item.value['options'] as List)
                  .map<String>(
                    (e) => ((e['text'] ?? e['value']) as String).ts(source.key),
                  )
                  .toList(),
              onTap: (i) {
                source.data['settings'][key] =
                    item.value['options'][i]['value'];
                source.saveData();
                setState(() {});
              },
            ),
          );
        } else if (type == "switch") {
          var current = source.data['settings'][key] ?? item.value['default'];
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            trailing: Switch(
              value: current,
              onChanged: (v) {
                source.data['settings'][key] = v;
                source.saveData();
                setState(() {});
              },
            ),
          );
        } else if (type == "input") {
          var current =
              source.data['settings'][key] ?? item.value['default'] ?? '';
          yield ListTile(
            title: Text((item.value['title'] as String).ts(source.key)),
            subtitle: Text(
              current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                showInputDialog(
                  context: context,
                  title: (item.value['title'] as String).ts(source.key),
                  initialValue: current,
                  inputValidator: item.value['validator'] == null
                      ? null
                      : RegExp(item.value['validator']),
                  onConfirm: (value) {
                    source.data['settings'][key] = value;
                    source.saveData();
                    setState(() {});
                    return null;
                  },
                );
              },
            ),
          );
        } else if (type == "callback") {
          yield _CallbackSetting(setting: item, sourceKey: source.key);
        }
      } catch (e, s) {
        AppDiagnostics.error('ui.comic_source', e, stackTrace: s, message: 'build_setting_failed');
      }
    }
  }

  final _reLogin = <String, bool>{};

  Iterable<Widget> _buildAccount() sync* {
    if (source.account == null) return;
    final bool logged = source.isLogged;
    if (!logged) {
      yield ListTile(
        title: Text("Log in".tl),
        trailing: const Icon(Icons.arrow_right),
        onTap: () async {
          await context.to(
            () => _LoginPage(config: source.account!, source: source),
          );
          if (!mounted) return;
          source.saveData();
          setState(() {});
        },
      );
    }
    if (logged) {
      for (var item in source.account!.infoItems) {
        if (item.builder != null) {
          yield item.builder!(context);
        } else {
          yield ListTile(
            title: Text(item.title.tl),
            subtitle: item.data == null ? null : Text(item.data!()),
            onTap: item.onTap,
          );
        }
      }
      if (source.data["account"] is List) {
        bool loading = _reLogin[source.key] == true;
        yield ListTile(
          title: Text("Re-login".tl),
          subtitle: Text("Click if login expired".tl),
          onTap: () async {
            if (source.data["account"] == null) {
              context.showMessage(message: "No data".tl);
              return;
            }
            setState(() {
              _reLogin[source.key] = true;
            });
            try {
              final List account = source.data["account"];
              var res = await source.account!.login!(account[0], account[1]);
              if (!mounted) return;
              if (res.error) {
                context.showMessage(message: res.errorMessage!);
              } else {
                context.showMessage(message: "Success".tl);
              }
            } finally {
              if (mounted) {
                setState(() {
                  _reLogin[source.key] = false;
                });
              }
            }
          },
          trailing: loading
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        );
      }
      yield ListTile(
        title: Text("Log out".tl),
        onTap: () {
          source.data["account"] = null;
          source.account?.logout();
          source.saveData();
          ComicSourceManager().notifyStateChange();
          setState(() {});
        },
        trailing: const Icon(Icons.logout),
      );
    }
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.config, required this.source});

  final AccountConfig config;

  final ComicSource source;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  String username = "";
  String password = "";
  bool loading = false;

  final Map<String, String> _cookies = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const Appbar(title: Text('')),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 400),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Login".tl, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 32),
                if (widget.config.cookieFields == null)
                  TextField(
                    decoration: InputDecoration(
                      labelText: "Username".tl,
                      border: const OutlineInputBorder(),
                    ),
                    enabled: widget.config.login != null,
                    onChanged: (s) {
                      username = s;
                    },
                    autofillHints: const [AutofillHints.username],
                  ).paddingBottom(16),
                if (widget.config.cookieFields == null)
                  TextField(
                    decoration: InputDecoration(
                      labelText: "Password".tl,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: widget.config.login != null,
                    onChanged: (s) {
                      password = s;
                    },
                    onSubmitted: (s) => login(),
                    autofillHints: const [AutofillHints.password],
                  ).paddingBottom(16),
                for (var field in widget.config.cookieFields ?? <String>[])
                  TextField(
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: widget.config.validateCookies != null,
                    onChanged: (s) {
                      _cookies[field] = s;
                    },
                  ).paddingBottom(16),
                if (widget.config.login == null &&
                    widget.config.cookieFields == null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 8),
                      Text("Login with password is disabled".tl),
                    ],
                  )
                else
                  Button.filled(
                    isLoading: loading,
                    onPressed: login,
                    child: Text("Continue".tl),
                  ),
                const SizedBox(height: 24),
                if (widget.config.loginWebsite != null)
                  TextButton(
                    onPressed: () {
                      if (App.isLinux) {
                        loginWithWebview2();
                      } else {
                        loginWithWebview();
                      }
                    },
                    child: Text("Login with webview".tl),
                  ),
                const SizedBox(height: 8),
                if (widget.config.registerWebsite != null)
                  TextButton(
                    onPressed: () =>
                        launchUrlString(widget.config.registerWebsite!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link),
                        const SizedBox(width: 8),
                        Text("Create Account".tl),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> login() async {
    if (widget.config.login != null) {
      if (username.isEmpty || password.isEmpty) {
        showToast(
          message: "Cannot be empty".tl,
          icon: const Icon(Icons.error_outline),
          context: context,
        );
        return;
      }
      setState(() {
        loading = true;
      });
      final value = await widget.config.login!(username, password);
      if (!mounted) return;
      if (value.error) {
        context.showMessage(message: value.errorMessage!);
        setState(() {
          loading = false;
        });
      } else {
        context.pop();
      }
    } else if (widget.config.validateCookies != null) {
      setState(() {
        loading = true;
      });
      var cookies = widget.config.cookieFields!
          .map((e) => _cookies[e] ?? '')
          .toList();
      final value = await widget.config.validateCookies!(cookies);
      if (!mounted) return;
      if (value) {
        widget.source.data['account'] = 'ok';
        widget.source.saveData();
        context.pop();
      } else {
        context.showMessage(message: "Invalid cookies".tl);
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> loginWithWebview() async {
    var url = widget.config.loginWebsite!;
    var title = '';
    bool success = false;
    bool closingWebview = false;

    Future<void> validate(InAppWebViewController c) async {
      if (success || closingWebview) return;
      if (widget.config.checkLoginStatus != null &&
          widget.config.checkLoginStatus!(url, title)) {
        success = true;
        closingWebview = true;
        var cookies = await c.getCookies(url);
        var localStorageItems = await c.webStorage.localStorage.getItems();
        var mappedLocalStorage = <String, dynamic>{};
        for (var item in localStorageItems) {
          if (item.key != null) {
            mappedLocalStorage[item.key!] = item.value;
          }
        }
        widget.source.data['_localStorage'] = mappedLocalStorage;
        await widget.source.saveData();
        SingleInstanceCookieJar.instance?.saveFromResponse(
          Uri.parse(url),
          cookies,
        );
        widget.config.onLoginWithWebviewSuccess?.call();
        if (mounted) {
          context.pop();
        }
      }
    }

    await context.to(
      () => AppWebview(
        initialUrl: widget.config.loginWebsite!,
        onNavigation: (u, c) {
          url = u;
          unawaited(validate(c));
          return false;
        },
        onTitleChange: (t, c) {
          title = t;
          unawaited(validate(c));
        },
      ),
    );
    if (!mounted) return;
    if (success) {
      widget.source.data['account'] = 'ok';
      widget.source.saveData();
      context.pop();
    }
  }

  // for linux
  void loginWithWebview2() async {
    if (!await DesktopWebview.isAvailable()) {
      context.showMessage(message: "Webview is not available".tl);
    }

    var url = widget.config.loginWebsite!;
    var title = '';
    bool success = false;

    void onClose() {
      if (success) {
        widget.source.data['account'] = 'ok';
        widget.source.saveData();
        context.pop();
      }
    }

    void validate(DesktopWebview webview) async {
      if (widget.config.checkLoginStatus != null &&
          widget.config.checkLoginStatus!(url, title)) {
        var cookiesMap = await webview.getCookies(url);
        var cookies = <io.Cookie>[];
        cookiesMap.forEach((key, value) {
          cookies.add(io.Cookie(key, value));
        });
        SingleInstanceCookieJar.instance?.saveFromResponse(
          Uri.parse(url),
          cookies,
        );
        var localStorageJson = await webview.evaluateJavascript(
          "JSON.stringify(window.localStorage);",
        );
        var localStorage = <String, dynamic>{};
        try {
          var decoded = jsonDecode(localStorageJson ?? '');
          if (decoded is Map<String, dynamic>) {
            localStorage = decoded;
          }
        } catch (e) {
          AppDiagnostics.error('ui.comic_source', e, message: 'parse_local_storage_failed');
        }
        widget.source.data['_localStorage'] = localStorage;
        await widget.source.saveData();
        success = true;
        widget.config.onLoginWithWebviewSuccess?.call();
        webview.close();
        onClose();
      }
    }

    var webview = DesktopWebview(
      initialUrl: widget.config.loginWebsite!,
      onTitleChange: (t, webview) {
        title = t;
        validate(webview);
      },
      onNavigation: (u, webview) {
        url = u;
        validate(webview);
      },
      onClose: onClose,
    );

    webview.open();
  }
}
