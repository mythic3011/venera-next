part of 'settings_page.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => DebugPageState();
}

class DebugPageState extends State<DebugPage> {
  final controller = TextEditingController();
  final exporter = DebugLogExporter();

  var result = "";

  Widget _readerNextFlagSection() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: context.colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "ReaderNext Cutover Flags",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              "Debug-only route-selection controls. Blocked ReaderNext decisions do not fall back to legacy. Disable an entrypoint flag to route future opens through legacy."
                  .tl,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            _SwitchSetting(
              title: "Master Switch".tl,
              settingKey: "reader_next_enabled",
            ),
            _SwitchSetting(
              title: "History".tl,
              settingKey: "reader_next_history_enabled",
            ),
            _SwitchSetting(
              title: "Favorites".tl,
              settingKey: "reader_next_favorites_enabled",
            ),
            _SwitchSetting(
              title: "Downloads".tl,
              settingKey: "reader_next_downloads_enabled",
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String get _serverStatusText {
    if (!diag.DevDiagnosticsApi.isEnabled) {
      return "Disabled".tl;
    }
    if (!App.isDesktop) {
      return "Unsupported on this platform".tl;
    }
    if (!exporter.isRunning || exporter.baseUri == null) {
      return "Stopped".tl;
    }
    return "Running on ${exporter.baseUri}";
  }

  Future<void> _toggleServer() async {
    if (!diag.DevDiagnosticsApi.isEnabled || !App.isDesktop) {
      return;
    }
    if (exporter.isRunning) {
      await exporter.stop();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    try {
      await exporter.start();
    } catch (e) {
      if (mounted) {
        context.showMessage(message: e.toString());
      }
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _copyUrl(Uri? uri) async {
    if (uri == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (mounted) {
      context.showMessage(message: "Copied".tl);
    }
  }

  Future<void> _exportLogs() async {
    final file = await exportDiagnosticsToFile();
    if (!mounted) {
      return;
    }
    if (file == null) {
      context.showMessage(message: "App is not initialized".tl);
      return;
    }
    await saveFile(file: file, filename: file.name);
    if (mounted) {
      context.showMessage(message: "Exported".tl);
    }
  }

  Future<void> _exportCrashReportBundle() async {
    final file = await exportCrashReportBundleToFile();
    if (!mounted) {
      return;
    }
    if (file == null) {
      context.showMessage(message: "App is not initialized".tl);
      return;
    }
    await saveFile(file: file, filename: file.name);
    if (mounted) {
      context.showMessage(message: "Exported".tl);
    }
  }

  Future<void> _openAppDataDirectory() async {
    if (!App.isInitialized) {
      if (mounted) {
        context.showMessage(message: "App is not initialized".tl);
      }
      return;
    }
    final folderPath = App.dataPath;
    try {
      if (App.isWindows) {
        await Process.run('explorer', [folderPath]);
      } else if (App.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (App.isLinux) {
        try {
          await Process.run('xdg-open', [folderPath]);
        } catch (_) {
          await launchUrlString('file://$folderPath');
        }
      } else {
        await launchUrlString('file://$folderPath');
      }
    } catch (e, s) {
      diag.AppDiagnostics.error(
        'ui.settings.debug',
        e,
        stackTrace: s,
        message: 'open_app_data_directory_failed',
      );
      if (mounted) {
        context.showMessage(message: "Failed to open folder: $e");
      }
    }
  }

  void _openDiagnosticsConsole() {
    if (!diag.DevDiagnosticsApi.isEnabled) {
      return;
    }
    context.to(
      () => TalkerScreen(
        talker: diag.appTalker,
        appBarTitle: "Diagnostics Console".tl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          return;
        }
        if (exporter.isRunning && exporter.healthUri() != null) {
          context.showMessage(message: "Diagnostics API is still running".tl);
        }
      },
      child: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text("Debug".tl)),
          _CallbackSetting(
            title: "Reload Configs".tl,
            actionTitle: "Reload".tl,
            callback: () {
              ComicSourceManager().reload();
            },
          ).toSliver(),
          _CallbackSetting(
            title: "Open Log".tl,
            callback: () {
              context.to(() => const LogsPage());
            },
            actionTitle: 'Open'.tl,
          ).toSliver(),
          _SwitchSetting(
            title: "Ignore Certificate Errors".tl,
            settingKey: CommonSettingKeys.ignoreBadCertificate.name,
          ).toSliver(),
          _readerNextFlagSection(),
          _SwitchSetting(
            title: "Enable Diagnostics API".tl,
            settingKey: CommonSettingKeys.enableDebugDiagnostics.name,
            subtitle: App.isDesktop
                ? "Allow the desktop app to start the local debug diagnostics API without a debug build."
                      .tl
                : "Desktop only.".tl,
            onChanged: () {
              if (mounted) {
                setState(() {});
              }
            },
          ).toSliver(),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  "Diagnostics Server",
                  style: TextStyle(fontSize: 16),
                ).paddingLeft(16),
                const SizedBox(height: 8),
                Text(_serverStatusText).paddingHorizontal(16),
                if (diag.DevDiagnosticsApi.isEnabled) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _toggleServer,
                    child: Text(exporter.isRunning ? "Stop".tl : "Start".tl),
                  ).paddingHorizontal(8),
                  TextButton(
                    onPressed: _openDiagnosticsConsole,
                    child: Text("Open Diagnostics Console".tl),
                  ).paddingHorizontal(8),
                ],
                if (exporter.isRunning) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _copyUrl(exporter.baseUri),
                        child: Text("Copy Base URL".tl),
                      ),
                      TextButton(
                        onPressed: () => _copyUrl(exporter.logsUri()),
                        child: Text("Copy Logs URL".tl),
                      ),
                      TextButton(
                        onPressed: () => _copyUrl(exporter.diagnosticsUri()),
                        child: Text("Copy Diagnostics URL".tl),
                      ),
                    ],
                  ).paddingHorizontal(8),
                ],
                const SizedBox(height: 4),
                Text(
                  "Diagnostics API `logs.groupedIssues` is the primary deduped view. Use `logs.newestErrors` and `logs.newestErrorsBySource` as raw compatibility drill-down."
                      .tl,
                ).paddingHorizontal(16),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _openAppDataDirectory,
                  child: Text("Open App Data Directory".tl),
                ).paddingHorizontal(8),
                if (Log.logFilePath != null) ...[
                  const SizedBox(height: 8),
                  Text("Log File: ${Log.logFilePath}").paddingHorizontal(16),
                ],
                if (App.isInitialized) ...[
                  const SizedBox(height: 8),
                  Text("Runtime Root: ${App.dataPath}").paddingHorizontal(16),
                  if (App.runtimeRootOverrideActive)
                    Text(
                      "Runtime Root Override: ${App.runtimeRootOverridePath}",
                    ).paddingHorizontal(16),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _exportLogs,
                  child: Text("Export Logs".tl),
                ).paddingHorizontal(8),
                TextButton(
                  onPressed: _exportCrashReportBundle,
                  child: Text("Export Crash Report Bundle".tl),
                ).paddingHorizontal(8),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text(
                  "JS Evaluator",
                  style: TextStyle(fontSize: 16),
                ).toAlign(Alignment.centerLeft).paddingLeft(16),
                Container(
                  width: double.infinity,
                  height: 200,
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    expands: true,
                    textAlign: TextAlign.start,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    try {
                      var res = JsEngine().runCode(controller.text, "<debug>");
                      setState(() {
                        result = res.toString();
                      });
                    } catch (e) {
                      setState(() {
                        result = e.toString();
                      });
                    }
                  },
                  child: const Text("Run"),
                ).toAlign(Alignment.centerRight).paddingRight(16),
                const Text(
                  "Result",
                  style: TextStyle(fontSize: 16),
                ).toAlign(Alignment.centerLeft).paddingLeft(16),
                Container(
                  width: double.infinity,
                  height: 200,
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: Text(result).paddingAll(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
