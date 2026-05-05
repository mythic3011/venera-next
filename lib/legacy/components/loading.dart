part of 'components.dart';

sealed class AppLoadError {
  const AppLoadError();

  String get title;
  String get userMessage;
  String? get diagnosticCode;
  bool get retryable;
  bool get exportLogsSuggested;
  bool get emitVisibleDiagnostic => true;

  static AppLoadError fromMessage(String message) {
    final cfe = CloudflareException.fromString(message);
    if (cfe != null) {
      return CloudflareLoadError(rawMessage: message);
    }
    if (message.startsWith('SOURCE_NOT_AVAILABLE')) {
      return SourceRefLoadError(rawMessage: message);
    }
    if (message.startsWith('SOURCE_REF_') ||
        message.startsWith('SOURCE_IDENTITY_ERROR:')) {
      return AdapterBoundaryLoadError(rawMessage: message);
    }
    final lower = message.toLowerCase();
    if (lower.contains('sqlite') ||
        lower.contains('no such table') ||
        lower.contains('schema')) {
      return StorageSchemaLoadError(rawMessage: message);
    }
    if (lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('network') ||
        lower.contains('http')) {
      return NetworkLoadError(rawMessage: message);
    }
    if (message.startsWith('LOCAL_COMIC_MISSING')) {
      return LocalComicMissingLoadError(rawMessage: message);
    }
    return UnknownLoadError(rawMessage: message);
  }
}

final class NetworkLoadError extends AppLoadError {
  const NetworkLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Network Error'.tl;
  @override
  String get userMessage => 'Network request failed. Please retry.'.tl;
  @override
  String? get diagnosticCode => null;
  @override
  bool get retryable => true;
  @override
  bool get exportLogsSuggested => true;
}

final class CloudflareLoadError extends AppLoadError {
  const CloudflareLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Cloudflare Verification'.tl;
  @override
  String get userMessage => "Cloudflare verification required".tl;
  @override
  String? get diagnosticCode => 'CLOUDFLARE_CHALLENGE';
  @override
  bool get retryable => true;
  @override
  bool get exportLogsSuggested => true;
}

final class SourceRefLoadError extends AppLoadError {
  const SourceRefLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Source Unavailable'.tl;
  @override
  String get userMessage => 'Source is unavailable. Retry or export logs.'.tl;
  @override
  String? get diagnosticCode => 'SOURCE_REF_UNAVAILABLE';
  @override
  bool get retryable => true;
  @override
  bool get exportLogsSuggested => true;
}

final class AdapterBoundaryLoadError extends AppLoadError {
  const AdapterBoundaryLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Identity Boundary Error'.tl;
  @override
  String get userMessage => 'Source identity validation failed.'.tl;
  @override
  String? get diagnosticCode => 'ADAPTER_BOUNDARY';
  @override
  bool get retryable => true;
  @override
  bool get exportLogsSuggested => true;
}

final class StorageSchemaLoadError extends AppLoadError {
  const StorageSchemaLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Storage Schema Error'.tl;
  @override
  String get userMessage => 'Storage schema mismatch detected.'.tl;
  @override
  String? get diagnosticCode => 'STORAGE_SCHEMA';
  @override
  bool get retryable => false;
  @override
  bool get exportLogsSuggested => true;
}

final class UnknownLoadError extends AppLoadError {
  const UnknownLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Error'.tl;
  @override
  String get userMessage => 'Unexpected error. Retry or export logs.'.tl;
  @override
  String? get diagnosticCode => null;
  @override
  bool get retryable => true;
  @override
  bool get exportLogsSuggested => true;
}

final class LocalComicMissingLoadError extends AppLoadError {
  const LocalComicMissingLoadError({required this.rawMessage});

  final String rawMessage;

  @override
  String get title => 'Comic Not Found'.tl;
  @override
  String get userMessage => 'This local comic is no longer available.'.tl;
  @override
  String? get diagnosticCode => 'LOCAL_COMIC_MISSING';
  @override
  bool get retryable => false;
  @override
  bool get exportLogsSuggested => false;
  @override
  bool get emitVisibleDiagnostic => false;
}

String _redactLogs(String raw) {
  var sanitized = raw;
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'(token|authorization|cookie|api[_-]?key|x-api-key|set-cookie)\s*[:=]\s*([^\r\n]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(bearer)\s+([A-Za-z0-9\-._~+/]+=*)', caseSensitive: false),
    (match) => '${match.group(1)} [redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(https?://)([^/\s:@]+):([^@\s]+)@', caseSensitive: false),
    (match) => '${match.group(1)}[redacted]:[redacted]@',
  );
  return sanitized;
}

String redactLoadingDiagnosticsForExport(String raw) => _redactLogs(raw);

void _emitUiErrorVisible({
  required BuildContext context,
  required String owner,
  required Object exception,
  StackTrace? stackTrace,
  String? diagnosticCode,
  String? rawMessage,
  String? exceptionType,
}) {
  final route = ModalRoute.of(context);
  final routeIdentity = describeRouteDiagnosticIdentity(route);
  AppDiagnostics.error(
    'ui.error',
    exception,
    stackTrace: stackTrace,
    message: 'ui.error.visible',
    data: {
      'routeHash': route?.hashCode,
      'routeDiagnosticIdentity': routeIdentity,
      'pageOwner': owner,
      'tabOwner': owner,
      'exceptionType': exceptionType ?? exception.runtimeType.toString(),
      'sanitizedMessage': _redactLogs(rawMessage ?? exception.toString()),
      if (diagnosticCode != null) 'diagnosticCode': diagnosticCode,
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    },
  );
}

class NetworkError extends StatelessWidget {
  NetworkError({
    super.key,
    required Object message,
    this.retry,
    this.withAppbar = true,
    this.buttonText,
    this.action,
  }) : error = switch (message) {
         AppLoadError typed => typed,
         _ => AppLoadError.fromMessage(message.toString()),
       };

  const NetworkError.fromError({
    super.key,
    required this.error,
    this.retry,
    this.withAppbar = true,
    this.buttonText,
    this.action,
  });

  final AppLoadError error;

  final void Function()? retry;

  final bool withAppbar;

  final String? buttonText;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cfe = error is CloudflareLoadError
        ? CloudflareException.fromString(
            (error as CloudflareLoadError).rawMessage,
          )
        : null;
    Widget body = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 28,
                  color: context.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  error.title,
                  style: ts.withColor(context.colorScheme.error).s16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(error.userMessage, textAlign: TextAlign.center, maxLines: 3),
          if (error.exportLogsSuggested)
            TextButton(
              onPressed: () {
                final redacted = _redactLogs(Log().toString());
                saveFile(
                  data: utf8.encode(redacted),
                  filename: 'diagnostics-redacted.txt',
                );
              },
              child: Text("Export logs".tl),
            ),
          const SizedBox(height: 8),
          if (retry != null && error.retryable)
            if (cfe != null)
              FilledButton(
                onPressed: () => passCloudflare(cfe, retry!),
                child: Text('Verify'.tl),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (action != null) action!.paddingRight(8),
                  FilledButton(
                    onPressed: retry,
                    child: Text(buttonText ?? 'Retry'.tl),
                  ),
                ],
              )
          else if (action != null)
            action!,
        ],
      ),
    );
    if (withAppbar) {
      body = Column(
        children: [
          const Appbar(title: Text("")),
          Expanded(child: body),
        ],
      );
    }
    return Material(child: body);
  }
}

class ListLoadingIndicator extends StatelessWidget {
  const ListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 80,
      child: Center(child: FiveDotLoadingAnimation()),
    );
  }
}

class SliverListLoadingIndicator extends StatelessWidget {
  const SliverListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // SliverToBoxAdapter can not been lazy loaded.
    // Use SliverList to make sure the animation can be lazy loaded.
    return SliverList.list(
      children: const [SizedBox(), ListLoadingIndicator()],
    );
  }
}

abstract class LoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool isLoading = false;

  S? data;

  AppLoadError? error;
  int _loadGeneration = 0;

  Future<Res<S>> loadData();

  Future<Res<S>> loadDataWithRetry() async {
    int retry = 0;
    while (true) {
      var res = await loadData();
      if (res.success) {
        return res;
      } else {
        if (!mounted) return res;
        if (retry >= 3) {
          return res;
        }
        retry++;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  FutureOr<void> onDataLoaded() {}

  Widget buildContent(BuildContext context, S data);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildLoading() {
    return Center(
      child: const CircularProgressIndicator(
        strokeWidth: 2,
      ).fixWidth(32).fixHeight(32),
    );
  }

  void _startLoad() {
    final generation = ++_loadGeneration;
    setState(() {
      isLoading = true;
      error = null;
    });
    loadDataWithRetry().then((value) async {
      if (!mounted || generation != _loadGeneration) return;
      if (value.success) {
        data = value.data;
        await onDataLoaded();
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          isLoading = false;
        });
      } else {
        if (!mounted || generation != _loadGeneration) return;
        final appError = AppLoadError.fromMessage(
          value.errorMessage ?? 'Unknown error',
        );
        if (appError.emitVisibleDiagnostic) {
          _emitUiErrorVisible(
            context: context,
            owner: '$T',
            exception: appError,
            diagnosticCode: appError.diagnosticCode,
            rawMessage: value.errorMessage ?? 'Unknown error',
            exceptionType: 'LoadError',
          );
        }
        setState(() {
          isLoading = false;
          error = appError;
        });
      }
    });
  }

  void retry() {
    _startLoad();
  }

  Widget buildError() {
    return NetworkError.fromError(error: error!, retry: retry);
  }

  @override
  @mustCallSuper
  void initState() {
    isLoading = true;
    Future.microtask(() {
      if (!mounted) return;
      _startLoad();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isLoading) {
      child = buildLoading();
    } else if (error != null) {
      child = buildError();
    } else {
      child = buildContent(context, data!);
    }

    return buildFrame(context, child) ?? child;
  }
}

abstract class MultiPageLoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool _isFirstLoading = true;

  bool _isLoading = false;

  List<S>? data;

  AppLoadError? _error;

  int _page = 1;

  int? _maxPage;

  int _loadGeneration = 0;

  Future<Res<List<S>>> loadData(int page);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildContent(BuildContext context, List<S> data);

  bool get isLoading => _isLoading || _isFirstLoading;

  bool get isFirstLoading => _isFirstLoading;

  bool get haveNextPage => _maxPage == null || _page <= _maxPage!;

  Future<void> nextPage() async {
    if (_maxPage != null && _page > _maxPage!) return;
    if (_isLoading) return;
    final generation = _loadGeneration;
    final page = _page;
    setState(() => _isLoading = true);
    try {
      final value = await loadData(page);
      if (!mounted || generation != _loadGeneration) return;
      if (value.success) {
        setState(() {
          _page = page + 1;
          if (value.subData is int) {
            _maxPage = value.subData as int;
          }
          data = [...?data, ...value.data];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        var message = value.errorMessage ?? "Network Error";
        if (message.length > 20) {
          message = "${message.substring(0, 20)}...";
        }
        context.showMessage(message: message);
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _isLoading = false);
      context.showMessage(message: e.toString());
    }
  }

  void reset() {
    _loadGeneration++;
    setState(() {
      _isFirstLoading = true;
      _isLoading = false;
      data = null;
      _error = null;
      _page = 1;
      _maxPage = null;
    });
    firstLoad();
  }

  void firstLoad() {
    final generation = _loadGeneration;
    Future.microtask(() {
      loadData(_page)
          .then((value) {
            if (generation != _loadGeneration) return;
            if (!mounted) return;
            if (value.success) {
              _page++;
              if (value.subData is int) {
                _maxPage = value.subData as int;
              }
              setState(() {
                _isFirstLoading = false;
                data = value.data;
              });
            } else {
              final appError = AppLoadError.fromMessage(
                value.errorMessage ?? 'Unknown error',
              );
              if (appError.emitVisibleDiagnostic) {
                _emitUiErrorVisible(
                  context: context,
                  owner: '$T',
                  exception: appError,
                  diagnosticCode: appError.diagnosticCode,
                  rawMessage: value.errorMessage ?? 'Unknown error',
                  exceptionType: 'LoadError',
                );
              }
              setState(() {
                _isFirstLoading = false;
                _error = appError;
              });
            }
          })
          .catchError((e) {
            if (!mounted || generation != _loadGeneration) return;
            final appError = AppLoadError.fromMessage(e.toString());
            if (appError.emitVisibleDiagnostic) {
              _emitUiErrorVisible(
                context: context,
                owner: '$T',
                exception: appError,
                stackTrace: e is Error ? e.stackTrace : null,
                diagnosticCode: appError.diagnosticCode,
                rawMessage: e.toString(),
                exceptionType: e.runtimeType.toString(),
              );
            }
            setState(() {
              _isFirstLoading = false;
              _error = appError;
            });
          });
    });
  }

  @override
  void initState() {
    firstLoad();
    super.initState();
  }

  Widget buildLoading(BuildContext context) {
    return Center(
      child: const CircularProgressIndicator().fixWidth(32).fixHeight(32),
    );
  }

  Widget buildError(BuildContext context, AppLoadError error) {
    return NetworkError.fromError(
      withAppbar: false,
      error: error,
      retry: reset,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isFirstLoading) {
      child = buildLoading(context);
    } else if (_error != null) {
      child = buildError(context, _error!);
    } else {
      child = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis != Axis.vertical) {
            return false;
          }
          if (!haveNextPage) {
            return false;
          }
          final remaining =
              notification.metrics.maxScrollExtent -
              notification.metrics.pixels;
          if (remaining <= 200) {
            nextPage();
          }
          return false;
        },
        child: buildContent(context, data!),
      );
    }

    return buildFrame(context, child) ?? child;
  }
}

class FiveDotLoadingAnimation extends StatefulWidget {
  const FiveDotLoadingAnimation({super.key});

  @override
  State<FiveDotLoadingAnimation> createState() =>
      _FiveDotLoadingAnimationState();
}

class _FiveDotLoadingAnimationState extends State<FiveDotLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      upperBound: 6,
    )..repeat(min: 0, max: 5.2, period: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
  ];

  static const _padding = 12.0;

  static const _dotSize = 12.0;

  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: _dotSize * 5 + _padding * 6,
          height: _height,
          child: Stack(children: List.generate(5, (index) => buildDot(index))),
        );
      },
    );
  }

  Widget buildDot(int index) {
    var value = _controller.value;
    var startValue = index * 0.8;
    return Positioned(
      left: index * _dotSize + (index + 1) * _padding,
      bottom:
          (math.sin(math.pi / 2 * (value - startValue).clamp(0, 2))) *
          (_height - _dotSize),
      child: Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          color: _colors[index],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
