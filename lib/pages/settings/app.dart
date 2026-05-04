part of 'settings_page.dart';

String formatLocalComicsStoragePathForDisplay(String? path) {
  if (path == null || path.isEmpty) {
    return AppSettingsStrings.notConfigured;
  }
  return path;
}

class _AppSettingsGateway {
  CacheManager get _cacheManager => CacheManager();

  String? get localComicsPath => tryReadLocalComicsStoragePath();

  Future<String?> setLocalComicsPath(String path) =>
      legacySetLocalComicsStoragePath(path);

  int get currentCacheSizeBytes => _cacheManager.currentSize;

  Future<void> clearCache() => _cacheManager.clear();

  void setCacheLimitSize(int sizeInMb) => _cacheManager.setLimitSize(sizeInMb);

  int get cacheSizeLimitInMb => appdata.settings[AppSettingKeys.cacheSize.name];

  void updateCacheSizeLimitInMb(int sizeInMb) {
    appdata.settings[AppSettingKeys.cacheSize.name] = sizeInMb;
    appdata.saveData();
  }

  bool get authorizationRequired =>
      appdata.settings[AppSettingKeys.authorizationRequired.name];

  void setAuthorizationRequired(bool value) {
    appdata.settings[AppSettingKeys.authorizationRequired.name] = value;
    appdata.saveData();
  }

  List get webdavConfigRaw {
    final raw = appdata.settings[AppSettingKeys.webdav.name];
    if (raw is List) {
      return raw;
    }
    return [];
  }

  String get disableSyncFields =>
      appdata.settings[AppSettingKeys.disableSyncFields.name];

  void setDisableSyncFields(String value) {
    appdata.settings[AppSettingKeys.disableSyncFields.name] = value;
  }

  void setWebdavConfig({
    required String url,
    required String user,
    required String pass,
  }) {
    appdata.settings[AppSettingKeys.webdav.name] = [url, user, pass];
  }

  void setWebdavConfigRaw(List config) {
    appdata.settings[AppSettingKeys.webdav.name] = config;
  }

  void clearWebdavConfig() {
    appdata.settings[AppSettingKeys.webdav.name] = [];
  }

  bool get webdavAutoSync =>
      appdata.implicitData[ImplicitSettingKeys.webdavAutoSync.name] ?? true;

  void setWebdavAutoSync(bool value) {
    appdata.implicitData[ImplicitSettingKeys.webdavAutoSync.name] = value;
    appdata.writeImplicitData();
  }

  void saveAppData() => appdata.saveData();

  bool get readerNextEnabled =>
      appdata.settings[CommonSettingKeys.readerNextEnabled.name] == true;
}

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  final _gateway = _AppSettingsGateway();

  String? get _localComicsStoragePath => _gateway.localComicsPath;

  String get _localComicsStoragePathForDisplay {
    return formatLocalComicsStoragePathForDisplay(_localComicsStoragePath);
  }

  void _copyLocalComicsStoragePath() {
    Clipboard.setData(ClipboardData(text: _localComicsStoragePathForDisplay));
    context.showMessage(message: AppSettingsStrings.pathCopiedToClipboard.tl);
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("App".tl)),
        _SettingPartTitle(title: "Data".tl, icon: Icons.storage),
        ListTile(
          title: Text("Storage Path for local comics".tl),
          subtitle: Text(_localComicsStoragePathForDisplay, softWrap: false),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyLocalComicsStoragePath,
          ),
        ).toSliver(),
        _CallbackSetting(
          title: "Set New Storage Path".tl,
          actionTitle: "Set".tl,
          callback: () async {
            String? result;
            if (App.isAndroid) {
              var picker = DirectoryPicker();
              result = (await picker.pickDirectory())?.path;
            } else if (App.isIOS) {
              result = await selectDirectoryIOS();
            } else {
              result = await selectDirectory();
            }
            if (result == null) return;
            var loadingDialog = showLoadingDialog(
              context,
              barrierDismissible: false,
              allowCancel: false,
            );
            String? res;
            try {
              res = await _gateway.setLocalComicsPath(result);
            } finally {
              loadingDialog.close();
            }
            if (!mounted) return;
            context.showMessage(message: res ?? "Path set successfully".tl);
            if (res == null) {
              setState(() {});
            }
          },
        ).toSliver(),
        ListTile(
          title: Text("Cache Size".tl),
          subtitle: Text(bytesToReadableString(_gateway.currentCacheSizeBytes)),
        ).toSliver(),
        _CallbackSetting(
          title: "Clear Cache".tl,
          actionTitle: "Clear".tl,
          callback: () async {
            var loadingDialog = showLoadingDialog(
              context,
              barrierDismissible: false,
              allowCancel: false,
            );
            try {
              await _gateway.clearCache();
            } finally {
              loadingDialog.close();
            }
            if (!mounted) return;
            context.showMessage(message: "Cache cleared".tl);
            setState(() {});
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Cache Limit".tl,
          subtitle: "${_gateway.cacheSizeLimitInMb} MB",
          callback: () {
            showInputDialog(
              context: context,
              title: "Set Cache Limit".tl,
              hintText: "Size in MB".tl,
              inputValidator: RegExp(r"^\d+$"),
              onConfirm: (value) {
                _gateway.updateCacheSizeLimitInMb(int.parse(value));
                setState(() {});
                _gateway.setCacheLimitSize(_gateway.cacheSizeLimitInMb);
                return null;
              },
            );
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Export App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            try {
              var file = await exportAppData(false);
              await saveFile(filename: "data.venera", file: file);
            } finally {
              controller.close();
            }
          },
          actionTitle: 'Export'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import App Data".tl,
          callback: () async {
            final file = await selectFile(ext: ['venera', 'picadata']);
            if (file == null) return;
            if (!mounted) return;
            var controller = showLoadingDialog(context);
            try {
              final cacheFile = File(
                FilePath.join(App.cachePath, "import_data_temp"),
              );
              await file.saveTo(cacheFile.path);
              try {
                if (file.name.endsWith('picadata')) {
                  await importPicaData(cacheFile);
                } else {
                  await importAppData(cacheFile);
                }
              } finally {
                cacheFile.deleteIgnoreError();
              }
              if (!mounted) return;
              App.forceRebuild();
            } catch (e, s) {
              diag.AppDiagnostics.error(
                'app.import',
                e,
                message: 'app.import.failed',
                stackTrace: s,
                data: {
                  'source': file.name.endsWith('picadata')
                      ? 'picadata'
                      : 'venera',
                  'errorType': e.runtimeType.toString(),
                  'message': e.toString(),
                },
              );
              if (mounted) {
                context.showMessage(message: "Failed to import data".tl);
              }
            } finally {
              controller.close();
            }
          },
          actionTitle: 'Import'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Data Sync".tl,
          callback: () async {
            showPopUpWidget(
              context,
              Builder(
                builder: (dialogContext) => _WebdavSetting(
                  onClose: () {
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ),
            );
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _SettingPartTitle(
          title: "ReaderNext Runtime".tl,
          icon: Icons.auto_stories,
        ),
        _SwitchSetting(
          title: "Enable ReaderNext".tl,
          subtitle: "Master route selection switch.".tl,
          settingKey: CommonSettingKeys.readerNextEnabled.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Enable History ReaderNext".tl,
          subtitle: "History entrypoint route selection.".tl,
          settingKey: CommonSettingKeys.readerNextHistoryEnabled.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Enable Favorites ReaderNext".tl,
          subtitle: "Favorites entrypoint route selection.".tl,
          settingKey: CommonSettingKeys.readerNextFavoritesEnabled.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Enable Downloads ReaderNext".tl,
          subtitle: "Downloads entrypoint route selection.".tl,
          settingKey: CommonSettingKeys.readerNextDownloadsEnabled.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Use SourceRef Resolver".tl,
          subtitle: "Runtime source-ref snapshot resolver switch.".tl,
          settingKey: CommonSettingKeys.readerUseSourceRefResolver.name,
        ).toSliver(),
        ListTile(
          title: Text("Current Route Mode".tl),
          subtitle: Text(
            _gateway.readerNextEnabled
                ? "ReaderNext (master flag enabled)".tl
                : "Legacy (master flag disabled)".tl,
          ),
        ).toSliver(),
        ListTile(
          title: Text("Runtime Status".tl),
          subtitle: Text(
            "Detailed per-open decision status is currently available in diagnostics/debug logs."
                .tl,
          ),
        ).toSliver(),
        _SettingPartTitle(title: "User".tl, icon: Icons.person_outline),
        SelectSetting(
          title: "Language".tl,
          settingKey: AppSettingKeys.language.name,
          optionTranslation: const {
            "system": "System",
            "zh-CN": "简体中文",
            "zh-TW": "繁體中文",
            "en-US": "English",
          },
          onChanged: () {
            App.forceRebuild();
          },
        ).toSliver(),
        _SwitchSetting(
          title: AppSettingsStrings.convertRemoteChineseLabels.tl,
          subtitle:
              App.locale.countryCode == 'TW' || App.locale.countryCode == 'HK'
              ? AppSettingsStrings
                    .convertRemoteChineseLabelsDescriptionZhHant
                    .tl
              : AppSettingsStrings.convertRemoteChineseLabelsDescription.tl,
          settingKey: AppSettingKeys.enableRemoteChineseTextConversion.name,
          onChanged: App.forceRebuild,
        ).toSliver(),
        if (!App.isLinux)
          _SwitchSetting(
            title: "Authorization Required".tl,
            settingKey: AppSettingKeys.authorizationRequired.name,
            onChanged: () async {
              var current = _gateway.authorizationRequired;
              if (current) {
                final auth = LocalAuthentication();
                final bool canAuthenticateWithBiometrics =
                    await auth.canCheckBiometrics;
                final bool canAuthenticate =
                    canAuthenticateWithBiometrics ||
                    await auth.isDeviceSupported();
                if (!canAuthenticate) {
                  context.showMessage(message: "Biometrics not supported".tl);
                  setState(() {
                    _gateway.setAuthorizationRequired(false);
                  });
                  return;
                }
              }
            },
          ).toSliver(),
      ],
    );
  }
}

class _WebdavSetting extends StatefulWidget {
  const _WebdavSetting({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_WebdavSetting> createState() => _WebdavSettingState();
}

class _WebdavSettingState extends State<_WebdavSetting> {
  final _gateway = _AppSettingsGateway();

  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _disableSyncController;

  bool autoSync = true;

  bool isTesting = false;
  bool upload = true;

  void _closePopup() {
    if (!mounted) return;
    widget.onClose();
  }

  @override
  void initState() {
    super.initState();
    var url = "";
    var user = "";
    var pass = "";
    var disableSync = "";
    if (_gateway.disableSyncFields.trim().isNotEmpty) {
      disableSync = _gateway.disableSyncFields;
    }
    final configs = _gateway.webdavConfigRaw;
    if (configs.length >= 3 &&
        configs[0] is String &&
        configs[1] is String &&
        configs[2] is String) {
      url = configs[0] as String;
      user = configs[1] as String;
      pass = configs[2] as String;
    }
    autoSync = _gateway.webdavAutoSync;
    _urlController = TextEditingController(text: url);
    _userController = TextEditingController(text: user);
    _passController = TextEditingController(text: pass);
    _disableSyncController = TextEditingController(text: disableSync);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _disableSyncController.dispose();
    super.dispose();
  }

  void onAutoSyncChanged(bool value) {
    setState(() {
      autoSync = value;
      _gateway.setWebdavAutoSync(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Webdav",
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "URL",
                hintText: "A valid WebDav directory URL".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _urlController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _userController,
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _passController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Skip Setting Fields (Optional)".tl,
                hintText: "field0, field1, field2, ...",
                hintStyle: TextStyle(color: Theme.of(context).hintColor),
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.help_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text("Skip Setting Fields".tl),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "When sync data, skip certain setting fields, which means these won't be uploaded / override."
                                  .tl,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "See source code for available fields.".tl,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () {
                                      launchUrlString(appDataFieldsDocUrl);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              controller: _disableSyncController,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.sync),
              title: Text("Auto Sync Data".tl),
              contentPadding: EdgeInsets.zero,
              trailing: Switch(value: autoSync, onChanged: onAutoSyncChanged),
            ),
            const SizedBox(height: 12),
            RadioGroup<bool>(
              groupValue: upload,
              onChanged: (value) {
                setState(() {
                  upload = value ?? upload;
                });
              },
              child: Row(
                children: [
                  Text("Operation".tl),
                  Radio<bool>(value: true),
                  Text("Upload".tl),
                  Radio<bool>(value: false),
                  Text("Download".tl),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: autoSync
                  ? Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Once the operation is successful, app will automatically sync data with the server."
                                  .tl,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Center(
              child: Button.filled(
                isLoading: isTesting,
                onPressed: () async {
                  final nextUrl = _urlController.text.trim();
                  final nextUser = _userController.text.trim();
                  final nextPass = _passController.text;
                  final nextDisableSync = _disableSyncController.text.trim();
                  var oldConfig = List.of(_gateway.webdavConfigRaw);
                  var oldAutoSync = _gateway.webdavAutoSync;
                  var oldDisableSync = _gateway.disableSyncFields;

                  if (nextUrl.isEmpty &&
                      nextUser.isEmpty &&
                      nextPass.trim().isEmpty) {
                    _gateway.clearWebdavConfig();
                    _gateway.setDisableSyncFields(nextDisableSync);
                    _gateway.setWebdavAutoSync(false);
                    _gateway.saveAppData();
                    if (!mounted) return;
                    context.showMessage(message: "Saved".tl);
                    _closePopup();
                    return;
                  }

                  _gateway.setWebdavConfig(
                    url: nextUrl,
                    user: nextUser,
                    pass: nextPass,
                  );
                  _gateway.setDisableSyncFields(nextDisableSync);
                  _gateway.setWebdavAutoSync(autoSync);

                  if (!autoSync) {
                    _gateway.saveAppData();
                    if (!mounted) return;
                    context.showMessage(message: "Saved".tl);
                    _closePopup();
                    return;
                  }

                  setState(() {
                    isTesting = true;
                  });
                  try {
                    var testResult = upload
                        ? await DataSync().uploadData()
                        : await DataSync().downloadData();
                    if (!mounted) return;
                    if (testResult.error) {
                      _gateway.setWebdavConfigRaw(oldConfig);
                      _gateway.setDisableSyncFields(oldDisableSync);
                      _gateway.setWebdavAutoSync(oldAutoSync);
                      _gateway.saveAppData();
                      context.showMessage(message: testResult.errorMessage!);
                      context.showMessage(message: "Saved Failed".tl);
                    } else {
                      _gateway.saveAppData();
                      context.showMessage(message: "Saved".tl);
                      _closePopup();
                    }
                  } catch (e, s) {
                    diag.AppDiagnostics.error(
                      'app.webdav',
                      e,
                      message: 'app.webdav.test.failed',
                      stackTrace: s,
                      data: {
                        'action': upload ? 'upload' : 'download',
                        'errorType': e.runtimeType.toString(),
                        'message': e.toString(),
                      },
                    );
                    _gateway.setWebdavConfigRaw(oldConfig);
                    _gateway.setDisableSyncFields(oldDisableSync);
                    _gateway.setWebdavAutoSync(oldAutoSync);
                    _gateway.saveAppData();
                    if (!mounted) return;
                    context.showMessage(message: "Saved Failed".tl);
                  } finally {
                    if (mounted) {
                      setState(() {
                        isTesting = false;
                      });
                    }
                  }
                },
                child: Text("Continue".tl),
              ),
            ),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }
}
