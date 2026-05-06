part of 'settings_page.dart';

abstract final class LogsPageStrings {
  static const sourceStructured = "Structured diagnostics";
  static const sourceLegacy = "Legacy logs (session)";

  static const all = "all";
  static const trace = "trace";
  static const info = "info";
  static const warn = "warn";
  static const warning = "warning";
  static const error = "error";
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  _LogsViewSource sourceToShow = _LogsViewSource.structured;
  String logLevelToShow = LogsPageStrings.all;
  String channelToShow = LogsPageStrings.all;

  List<diag.DiagnosticEvent> get _structuredLogs {
    final minLevel = _structuredLevelFromFilter(logLevelToShow);
    return diag.DevDiagnosticsApi.recent(
      minLevel: minLevel,
      channel: channelToShow == LogsPageStrings.all ? null : channelToShow,
    );
  }

  List<LogItem> get _legacyLogs {
    if (logLevelToShow == LogsPageStrings.all) {
      return Log.logs;
    }
    return Log.logs.where((log) => log.level.name == logLevelToShow).toList();
  }

  List<String> get _structuredChannels {
    final channels = diag.DevDiagnosticsApi.recent()
        .map((event) => event.channel)
        .toSet()
        .toList(growable: false);
    channels.sort();
    return channels;
  }

  @override
  Widget build(BuildContext context) {
    final structuredLogs = _structuredLogs;
    final legacyLogs = _legacyLogs;
    return Scaffold(
      appBar: Appbar(
        title: Text("Logs".tl),
        actions: [
          IconButton(
            onPressed: () {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text(LogsPageStrings.sourceStructured.tl),
                    onTap: () => setState(() {
                      sourceToShow = _LogsViewSource.structured;
                      logLevelToShow = LogsPageStrings.all;
                      channelToShow = LogsPageStrings.all;
                    }),
                  ),
                  PopupMenuItem(
                    child: Text(LogsPageStrings.sourceLegacy.tl),
                    onTap: () => setState(() {
                      sourceToShow = _LogsViewSource.legacy;
                      logLevelToShow = LogsPageStrings.all;
                    }),
                  ),
                ],
              );
            },
            icon: const Icon(Icons.layers_outlined),
          ),
          IconButton(
            onPressed: () {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: sourceToShow == _LogsViewSource.structured
                    ? [
                        PopupMenuItem(
                          child: Text(LogsPageStrings.all.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.all,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.trace.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.trace,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.info.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.info,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.warn.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.warn,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.error.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.error,
                          ),
                        ),
                      ]
                    : [
                        PopupMenuItem(
                          child: Text(LogsPageStrings.all.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.all,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.info.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.info,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.warning.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.warning,
                          ),
                        ),
                        PopupMenuItem(
                          child: Text(LogsPageStrings.error.tl),
                          onTap: () => setState(
                            () => logLevelToShow = LogsPageStrings.error,
                          ),
                        ),
                      ],
              );
            },
            icon: const Icon(Icons.filter_list_outlined),
          ),
          if (sourceToShow == _LogsViewSource.structured)
            IconButton(
              onPressed: () {
                final RelativeRect position = RelativeRect.fromLTRB(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).padding.top + kToolbarHeight,
                  0.0,
                  0.0,
                );
                showMenu(
                  context: context,
                  position: position,
                  items: [
                    PopupMenuItem(
                      child: Text(LogsPageStrings.all.tl),
                      onTap: () =>
                          setState(() => channelToShow = LogsPageStrings.all),
                    ),
                    ..._structuredChannels.map(
                      (channel) => PopupMenuItem(
                        child: Text(channel),
                        onTap: () => setState(() => channelToShow = channel),
                      ),
                    ),
                  ],
                );
              },
              icon: const Icon(Icons.tune_outlined),
            ),
          IconButton(
            onPressed: () {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("Clear".tl),
                    onTap: () => setState(() {
                      if (sourceToShow == _LogsViewSource.structured) {
                        diag.DevDiagnosticsApi.clear();
                      } else {
                        Log.clear();
                      }
                    }),
                  ),
                  if (sourceToShow == _LogsViewSource.legacy)
                    PopupMenuItem(
                      child: Text("Disable Length Limitation".tl),
                      onTap: () {
                        Log.ignoreLimitation = true;
                        context.showMessage(
                          message: "Only valid for this run".tl,
                        );
                      },
                    ),
                  PopupMenuItem(onTap: saveLog, child: Text("Export".tl)),
                ],
              );
            },
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: sourceToShow == _LogsViewSource.structured
          ? _buildStructuredLogsList(structuredLogs)
          : _buildLegacyLogsList(legacyLogs),
    );
  }

  Future<void> saveLog() async {
    final text = await buildDiagnosticsExportText();
    if (!mounted || !context.mounted) {
      return;
    }
    await saveFile(
      data: utf8.encode(text),
      filename: Log.buildExportFileName(prefix: 'venera_diagnostics_export'),
    );
  }

  Widget _buildStructuredLogsList(List<diag.DiagnosticEvent> logs) {
    return ListView.builder(
      reverse: true,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        index = logs.length - index - 1;
        final event = logs[index];
        final data = event.data.isEmpty
            ? null
            : const JsonEncoder.withIndent("  ").convert(event.data);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                        child: Text(event.channel),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      decoration: BoxDecoration(
                        color: _logLevelColor(context, event.level.name),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                        child: Text(
                          event.level.name,
                          style: TextStyle(
                            color: event.level == diag.DiagnosticLevel.error
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(event.message),
                if (data != null) Text(data),
                if (event.errorType != null)
                  Text("errorType: ${event.errorType}"),
                if (event.stackTrace != null) Text(event.stackTrace!),
                Text(
                  event.timestamp.toString().replaceAll(RegExp(r"\.\w+"), ""),
                ),
                TextButton(
                  onPressed: () {
                    final payload = StringBuffer(event.message);
                    if (data != null) {
                      payload.writeln();
                      payload.write(data);
                    }
                    Clipboard.setData(ClipboardData(text: payload.toString()));
                  },
                  child: Text("Copy".tl),
                ),
                const Divider(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegacyLogsList(List<LogItem> logs) {
    return ListView.builder(
      reverse: true,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        index = logs.length - index - 1;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                        child: Text(logs[index].title),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      decoration: BoxDecoration(
                        color: _logLevelColor(context, logs[index].level.name),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                        child: Text(
                          logs[index].level.name,
                          style: TextStyle(
                            color: logs[index].level == LogLevel.error
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(logs[index].content),
                Text(
                  logs[index].time.toString().replaceAll(RegExp(r"\.\w+"), ""),
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: logs[index].content));
                  },
                  child: Text("Copy".tl),
                ),
                const Divider(),
              ],
            ),
          ),
        );
      },
    );
  }

  diag.DiagnosticLevel? _structuredLevelFromFilter(String value) {
    return switch (value) {
      LogsPageStrings.trace => diag.DiagnosticLevel.trace,
      LogsPageStrings.info => diag.DiagnosticLevel.info,
      LogsPageStrings.warn => diag.DiagnosticLevel.warn,
      LogsPageStrings.error => diag.DiagnosticLevel.error,
      _ => null,
    };
  }

  Color _logLevelColor(BuildContext context, String levelName) {
    final scheme = Theme.of(context).colorScheme;
    return switch (levelName) {
      LogsPageStrings.error => scheme.error,
      LogsPageStrings.warning || LogsPageStrings.warn => scheme.errorContainer,
      _ => scheme.primaryContainer,
    };
  }
}

enum _LogsViewSource { structured, legacy }
