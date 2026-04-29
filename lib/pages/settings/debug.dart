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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String get _serverStatusText {
    if (!DevDiagnosticsApi.isEnabled) {
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
    if (!DevDiagnosticsApi.isEnabled || !App.isDesktop) {
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

  Future<void> _exportLogsSnapshot() async {
    final file = await Log.exportToFile();
    if (!mounted) {
      return;
    }
    if (file == null) {
      context.showMessage(message: "App is not initialized".tl);
      return;
    }
    await Clipboard.setData(ClipboardData(text: file.path));
    if (mounted) {
      context.showMessage(message: "Exported: ${file.path}");
    }
  }

  Future<void> _saveLogsFile() async {
    final data = utf8.encode(await Log.buildExportText());
    await saveFile(data: data, filename: Log.buildExportFileName());
    if (mounted) {
      context.showMessage(message: "Saved".tl);
    }
  }

  void _openDiagnosticsConsole() {
    if (!DevDiagnosticsApi.isEnabled) {
      return;
    }
    context.to(
      () => TalkerScreen(
        talker: appTalker,
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
          App.rootContext.showMessage(
            message: "Diagnostics API is still running".tl,
          );
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
          settingKey: "ignoreBadCertificate",
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
              if (DevDiagnosticsApi.isEnabled) ...[
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
              if (Log.logFilePath != null) ...[
                const SizedBox(height: 8),
                Text("Log File: ${Log.logFilePath}").paddingHorizontal(16),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _exportLogsSnapshot,
                child: Text("Export Logs Snapshot".tl),
              ).paddingHorizontal(8),
              TextButton(
                onPressed: _saveLogsFile,
                child: Text("Save Logs File".tl),
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
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colorScheme.outline),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(child: Text(result).paddingAll(4)),
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }
}
