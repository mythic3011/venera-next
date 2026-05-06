import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/network/proxy.dart';
import 'package:venera/utils/translations.dart';
import 'dart:io' as io;

export 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show WebUri, URLRequest;

abstract interface class AppWebviewController {
  Future<String?> currentUrl();

  Future<String?> userAgent();

  Future<String?> evaluateJavascript(String source);

  Future<Map<String, String>> cookiesFor(String url);

  Future<void> close();
}

extension WebviewExtension on InAppWebViewController {
  Future<List<io.Cookie>> getCookies(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return <io.Cookie>[];
    }
    final uri = WebUri(normalized);
    final cookieManager = CookieManager.instance(
      webViewEnvironment: AppWebview.webViewEnvironment,
    );
    final cookies = await cookieManager.getCookies(
      url: uri,
      webViewController: this,
    );
    return cookies.map((cookie) {
      final c = io.Cookie(cookie.name, cookie.value);
      if (cookie.domain != null) {
        c.domain = cookie.domain;
      }
      if (cookie.path != null) {
        c.path = cookie.path!;
      }
      c.secure = cookie.isSecure ?? false;
      c.httpOnly = cookie.isHttpOnly ?? false;
      return c;
    }).toList();
  }

  Future<String?> getUA() async {
    final res = await evaluateJavascript(source: "navigator.userAgent");
    if (res == null) {
      return null;
    }
    var text = res.toString();
    if (text.length >= 2 &&
        ((text.startsWith("'") && text.endsWith("'")) ||
            (text.startsWith('"') && text.endsWith('"')))) {
      text = text.substring(1, text.length - 1);
    }
    return text;
  }
}

class InAppWebviewControllerAdapter implements AppWebviewController {
  final InAppWebViewController controller;

  InAppWebviewControllerAdapter(this.controller);

  @override
  Future<String?> currentUrl() async {
    final url = await controller.getUrl();
    return url?.toString();
  }

  @override
  Future<String?> userAgent() => controller.getUA();

  @override
  Future<String?> evaluateJavascript(String source) async {
    final result = await controller.evaluateJavascript(source: source);
    return result?.toString();
  }

  @override
  Future<Map<String, String>> cookiesFor(String url) async {
    final cookies = await controller.getCookies(url);
    final res = <String, String>{};
    for (final cookie in cookies) {
      res[cookie.name] = cookie.value;
    }
    return res;
  }

  @override
  Future<void> close() => controller.stopLoading();
}

class AppWebview extends StatefulWidget {
  const AppWebview({
    required this.initialUrl,
    this.onTitleChange,
    this.onNavigation,
    this.singlePage = false,
    this.onStarted,
    this.onLoadStop,
    super.key,
  });

  final String initialUrl;

  final void Function(String title, InAppWebViewController controller)?
  onTitleChange;

  final bool Function(String url, InAppWebViewController controller)?
  onNavigation;

  final void Function(InAppWebViewController controller)? onStarted;

  final void Function(InAppWebViewController controller)? onLoadStop;

  final bool singlePage;

  static WebViewEnvironment? webViewEnvironment;

  @override
  State<AppWebview> createState() => _AppWebviewState();
}

class _AppWebviewState extends State<AppWebview> {
  InAppWebViewController? controller;

  static Future<bool>? _environmentFuture;

  String title = "Webview";

  double _progress = 0;

  late final Future<bool> future =
      _environmentFuture ??= _createWebviewEnvironment();

  Future<bool> _createWebviewEnvironment() async {
    var proxy = appdata.settings['proxy'].toString();
    if (proxy != "system" && proxy != "direct") {
      var proxyAvailable = await WebViewFeature.isFeatureSupported(
        WebViewFeature.PROXY_OVERRIDE,
      );
      if (proxyAvailable) {
        ProxyController proxyController = ProxyController.instance();
        await proxyController.clearProxyOverride();
        if (!proxy.contains("://")) {
          proxy = "http://$proxy";
        }
        await proxyController.setProxyOverride(
          settings: ProxySettings(proxyRules: [ProxyRule(url: proxy)]),
        );
      }
    }
    if (!App.isWindows) {
      return true;
    }
    AppWebview.webViewEnvironment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: "${App.dataPath}\\webview",
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      Tooltip(
        message: "More",
        child: IconButton(
          icon: const Icon(Icons.more_horiz),
          onPressed: () {
            showMenuX(context, Offset(context.width, context.padding.top), [
              MenuEntry(
                icon: Icons.open_in_browser,
                text: "Open in browser".tl,
                onClick: () async {
                  final url = await _currentUrl();
                  if (url == null || url.isEmpty) {
                    return;
                  }
                  await launchUrlString(url);
                },
              ),
              MenuEntry(
                icon: Icons.copy,
                text: "Copy link".tl,
                onClick: () async {
                  final url = await _currentUrl();
                  if (url == null || url.isEmpty) {
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: url));
                },
              ),
              MenuEntry(
                icon: Icons.refresh,
                text: "Reload".tl,
                onClick: () => controller?.reload(),
              ),
            ]);
          },
        ),
      ),
    ];

    Widget body = FutureBuilder(
      future: future,
      builder: (context, e) {
        if (e.error != null) {
          return Center(child: Text("Error: ${e.error}"));
        }
        if (!e.hasData) {
          return const SizedBox();
        }
        return createWebviewWithEnvironment(AppWebview.webViewEnvironment);
      },
    );

    body = Stack(
      children: [
        Positioned.fill(child: body),
        if (_progress < 1.0)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );

    return Scaffold(
      appBar: Appbar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: body,
    );
  }

  Future<String?> _currentUrl() async {
    final c = controller;
    if (c == null) {
      return null;
    }
    final url = await c.getUrl();
    return url?.toString();
  }

  Widget createWebviewWithEnvironment(WebViewEnvironment? e) {
    return InAppWebView(
      webViewEnvironment: e,
      initialSettings: InAppWebViewSettings(isInspectable: true),
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      onTitleChanged: (c, t) {
        final nextTitle = t ?? "Webview";
        if (mounted) {
          setState(() {
            title = nextTitle;
          });
        }
        widget.onTitleChange?.call(nextTitle, c);
      },
      shouldOverrideUrlLoading: (c, r) async {
        var res =
            widget.onNavigation?.call(r.request.url?.toString() ?? "", c) ??
            false;
        if (res) {
          return NavigationActionPolicy.CANCEL;
        } else {
          return NavigationActionPolicy.ALLOW;
        }
      },
      onWebViewCreated: (c) {
        controller = c;
        widget.onStarted?.call(c);
      },
      onLoadStop: (c, r) {
        widget.onLoadStop?.call(c);
      },
      onProgressChanged: (c, p) {
        if (mounted) {
          setState(() {
            _progress = p / 100;
          });
        }
      },
    );
  }
}

class DesktopWebview implements AppWebviewController {
  static Future<bool> isAvailable() => WebviewWindow.isWebviewAvailable();

  final String initialUrl;

  final void Function(String title, DesktopWebview controller)? onTitleChange;

  final void Function(String url, DesktopWebview webview)? onNavigation;

  final void Function(DesktopWebview controller)? onStarted;

  final void Function()? onClose;

  DesktopWebview({
    required this.initialUrl,
    this.onTitleChange,
    this.onNavigation,
    this.onStarted,
    this.onClose,
  });

  Webview? _webview;

  String? _ua;

  String? title;

  String? _lastNavigationUrl;

  bool _hasDocumentCreated = false;

  void _cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  void _restartTimer() {
    _cancelTimer();
    _runTimer();
  }

  void _handleMessage(dynamic message) {
    final payload = switch (message) {
      String text => text.trim(),
      _ => '',
    };
    if (payload.isEmpty) {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }

    if (decoded is! Map) {
      return;
    }

    final id = decoded["id"];
    if (id != "document_created") {
      return;
    }
    final data = decoded["data"];
    if (data is! Map) {
      return;
    }

    final nextTitle = data["title"];
    final nextUa = data["ua"];
    if (nextTitle is! String || nextUa is! String) {
      return;
    }

    title = nextTitle;
    _ua = nextUa;
    _hasDocumentCreated = true;
    _cancelTimer();
    onTitleChange?.call(nextTitle, this);
  }

  void onMessage(String message) {
    _handleMessage(message);
  }

  String? get cachedUserAgent => _ua;

  Timer? timer;

  bool _isClosed = false;

  void _runTimer() {
    _cancelTimer();
    timer = Timer.periodic(const Duration(seconds: 2), (t) async {
      final webview = _webview;
      if (_isClosed || webview == null || _hasDocumentCreated) {
        _cancelTimer();
        return;
      }
      const js = '''
        function collect() {
          if(document.readyState === 'loading') {
            return '';
          }
          let data = {
            id: "document_created",
            data: {
              title: document.title,
              url: location.href,
              ua: navigator.userAgent
            }
          };
          return JSON.stringify(data);
        }
        collect();
      ''';
      _handleMessage(await webview.evaluateJavaScript(js) ?? '');
    });
  }

  Future<void> open() async {
    if (_webview != null && !_isClosed) {
      return;
    }
    _isClosed = false;
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        useWindowPositionAndSize: true,
        userDataFolderWindows: "${App.dataPath}\\webview",
        title: "webview",
        proxy: await getProxy(),
      ),
    );
    _webview = webview;
    webview.addOnWebMessageReceivedCallback(onMessage);
    webview.setOnNavigation((raw) {
      final s = _normalizeNavigationUrl(raw);
      if (_lastNavigationUrl != s) {
        _lastNavigationUrl = s;
        _hasDocumentCreated = false;
        _restartTimer();
      }
      if (!_isClosed) {
        onNavigation?.call(s, this);
      }
    });
    webview.launch(initialUrl, triggerOnUrlRequestEvent: false);
    _runTimer();
    unawaited(webview.onClose.then((value) {
      _isClosed = true;
      _webview = null;
      _cancelTimer();
      onClose?.call();
    }));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!_isClosed) {
      onStarted?.call(this);
    }
  }

  String _normalizeNavigationUrl(String raw) {
    final s = raw.trim();
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  @override
  Future<String?> evaluateJavascript(String source) {
    final webview = _webview;
    if (_isClosed || webview == null) {
      return Future.value(null);
    }
    return webview.evaluateJavaScript(source);
  }

  @override
  Future<String?> currentUrl() async {
    return _lastNavigationUrl ?? initialUrl;
  }

  @override
  Future<String?> userAgent() async {
    return _ua;
  }

  Future<Map<String, String>> getCookies(String url) async {
    final webview = _webview;
    if (_isClosed || webview == null) {
      return <String, String>{};
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return <String, String>{};
    }
    final allCookies = await webview.getAllCookies();
    final res = <String, String>{};
    for (final c in allCookies) {
      if (_cookieMatchHost(uri.host, c.domain)) {
        res[_removeCode0(c.name)] = _removeCode0(c.value);
      }
    }
    return res;
  }

  @override
  Future<Map<String, String>> cookiesFor(String url) => getCookies(url);

  String _removeCode0(String s) {
    var codeUints = List<int>.from(s.codeUnits);
    codeUints.removeWhere((e) => e == 0);
    return String.fromCharCodes(codeUints);
  }

  bool _cookieMatchHost(String host, String domain) {
    final cleanHost = host.trim().toLowerCase();
    final cleanDomain = _removeCode0(domain)
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.+'), '');
    if (cleanHost.isEmpty || cleanDomain.isEmpty) {
      return false;
    }
    return cleanHost == cleanDomain || cleanHost.endsWith('.$cleanDomain');
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _webview?.close();
    _webview = null;
    _cancelTimer();
  }
}
