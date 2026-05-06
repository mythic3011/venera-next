import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:uuid/uuid.dart';
import 'package:venera/components/js_ui.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/js/js_pool.dart';
import 'package:venera/features/sources/comic_source/runtime/source_capability_policy.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/network/proxy.dart';
import 'package:venera/utils/init.dart';

import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';

class JavaScriptRuntimeException implements Exception {
  final String message;

  JavaScriptRuntimeException(this.message);

  @override
  String toString() {
    return "JSException: $message";
  }
}

class JsBridgeRequest {
  JsBridgeRequest._(this.payload, this.method);

  final Map<String, dynamic> payload;
  final String method;

  static JsBridgeRequest? tryParse(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final payload = <String, dynamic>{};
    raw.forEach((key, value) {
      payload[key.toString()] = value;
    });
    final method = payload["method"];
    if (method is! String || method.isEmpty) {
      return null;
    }
    return JsBridgeRequest._(payload, method);
  }

  String requireString(String key) {
    final value = payload[key];
    if (value is String) {
      return value;
    }
    throw JavaScriptRuntimeException(
      "Malformed JS bridge request: '$key' must be a string",
    );
  }
}

class JsEngine with _JSEngineApi, JsUiApi, Init {
  factory JsEngine() => _cache ?? (_cache = JsEngine._create());

  static JsEngine? _cache;

  JsEngine._create();

  FlutterQjs? _engine;

  bool _closed = true;

  Dio? _dio;

  static Future<void> reset() async {
    final old = _cache;
    _cache = null;
    old?.dispose();
    await JsEngine().init();
  }

  void resetDio() {
    _dio = AppDio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (status) => true,
      ),
    );
  }

  static Uint8List? _jsInitCache;

  static void cacheJsInit(Uint8List jsInit) {
    _jsInitCache = jsInit;
  }

  @override
  @protected
  Future<void> doInit() async {
    if (!_closed) {
      return;
    }
    try {
      if (App.isInitialized) {
        _cookieJar ??= await SingleInstanceCookieJar.createInstance();
      }
      _dio ??= AppDio(
        BaseOptions(
          responseType: ResponseType.plain,
          validateStatus: (status) => true,
        ),
      );
      _closed = false;
      _engine = FlutterQjs();
      _engine!.dispatch();
      var setGlobalFunc = _engine!.evaluate(
        "(key, value) => { this[key] = value; }",
      );
      (setGlobalFunc as JSInvokable)(["sendMessage", _messageReceiver]);
      setGlobalFunc(["appVersion", App.version]);
      setGlobalFunc.free();
      Uint8List jsInit;
      if (_jsInitCache != null) {
        jsInit = _jsInitCache!;
      } else {
        var buffer = await rootBundle.load("assets/init.js");
        jsInit = buffer.buffer.asUint8List();
      }
      _engine!.evaluate(utf8.decode(jsInit), name: "<init>");
    } catch (e, s) {
      AppDiagnostics.error('js.engine', e, stackTrace: s, message: 'init_failed');
    }
  }

  Object? _messageReceiver(dynamic message) {
    final request = JsBridgeRequest.tryParse(message);
    if (request == null) {
      return _bridgeError(
        code: "malformed_request",
        message: "Request must be a map with non-empty string method",
      );
    }
    try {
      switch (request.method) {
        case "log":
          final level = request.payload["level"];
          final title = request.payload["title"];
          final channel = title is String && title.isNotEmpty
              ? 'js.log.${title.toLowerCase().replaceAll(' ', '.')}'
              : 'js.log';
          final content = request.payload["content"].toString();
          switch (level) {
            case "error":
              AppDiagnostics.error(channel, content, message: 'js_bridge_log');
            case "info":
              AppDiagnostics.info(channel, 'js_bridge_log', data: {'content': content});
            default:
              AppDiagnostics.warn(channel, 'js_bridge_log', data: {'content': content});
          }
          return null;
        case 'load_data':
          final key = request.requireString("key");
          final dataKey = request.requireString("data_key");
          return ComicSource.find(key)?.data[dataKey];
        case 'save_data':
          final key = request.requireString("key");
          final dataKey = request.requireString("data_key");
          if (dataKey == 'setting') {
            throw JavaScriptRuntimeException(
              "setting is not allowed to be saved",
            );
          }
          final source = ComicSource.find(key);
          if (source == null) {
            throw JavaScriptRuntimeException("Source not found: $key");
          }
          source.data[dataKey] = request.payload["data"];
          source.saveData();
          return null;
        case 'delete_data':
          final key = request.requireString("key");
          final dataKey = request.requireString("data_key");
          final source = ComicSource.find(key);
          source?.data.remove(dataKey);
          source?.saveData();
          return null;
        case 'http':
          final httpRequest = Map<String, dynamic>.from(request.payload);
          _validateHttpBridgeRequest(httpRequest);
          return _http(httpRequest);
        case 'html':
          return handleHtmlCallback(Map<String, dynamic>.from(request.payload));
        case 'convert':
          return _convert(Map<String, dynamic>.from(request.payload));
        case "random":
          return _random(
            request.payload["min"] is num ? request.payload["min"] : 0,
            request.payload["max"] is num ? request.payload["max"] : 1,
            request.payload["type"] is String ? request.payload["type"] : "",
          );
        case "cookie":
          return handleCookieCallback(
            Map<String, dynamic>.from(request.payload),
          );
        case "uuid":
          return const Uuid().v4();
        case "load_setting":
          final key = request.requireString("key");
          final settingKey = request.requireString("setting_key");
          final source = ComicSource.find(key);
          if (source == null) {
            throw JavaScriptRuntimeException("Source not found: $key");
          }
          return source.data["settings"]?[settingKey] ??
              source.settings?[settingKey]?['default'] ??
              (throw JavaScriptRuntimeException(
                "Setting not found: $settingKey",
              ));
        case "isLogged":
          final key = request.requireString("key");
          return ComicSource.find(key)?.isLogged ?? false;
        case "delay":
          final time = request.payload["time"];
          if (time is! int) {
            throw JavaScriptRuntimeException(
              "Malformed JS bridge request: 'time' must be an int",
            );
          }
          return Future.delayed(Duration(milliseconds: time));
        case "UI":
          return handleUIMessage(Map<String, dynamic>.from(request.payload));
        case "getLocale":
          return "${App.locale.languageCode}_${App.locale.countryCode}";
        case "getPlatform":
          return Platform.operatingSystem;
        case "setClipboard":
          final text = request.payload["text"];
          if (text is! String) {
            throw JavaScriptRuntimeException(
              "Malformed JS bridge request: 'text' must be a string",
            );
          }
          return Clipboard.setData(ClipboardData(text: text));
        case "getClipboard":
          return Future.sync(() async {
            final res = await Clipboard.getData(Clipboard.kTextPlain);
            return res?.text;
          });
        case "compute":
          final func = request.payload["function"];
          final args = request.payload["args"];
          if (func is JSInvokable) {
            func.free();
            throw JavaScriptRuntimeException("Function must be a string");
          }
          if (func is! String) {
            throw JavaScriptRuntimeException("Function must be a string");
          }
          if (args != null && args is! List) {
            throw JavaScriptRuntimeException("Args must be a list");
          }
          final sourceKey = request.payload["key"] is String
              ? request.payload["key"] as String
              : null;
          return JSPool().execute(func, args ?? [], sourceKey: sourceKey);
        default:
          return _bridgeError(
            code: "unsupported_method",
            message: "Unsupported JS bridge method: ${request.method}",
            method: request.method,
          );
      }
    } on JavaScriptRuntimeException catch (e) {
      return _bridgeError(
        code: "bridge_error",
        message: e.message,
        method: request.method,
      );
    } catch (e, s) {
      AppDiagnostics.error(
        'js.engine',
        e,
        stackTrace: s,
        message: 'handle_bridge_message_failed',
        data: {'rawMessage': '$message'},
      );
      return _bridgeError(
        code: "bridge_error",
        message: "Unexpected JS bridge failure",
        method: request.method,
      );
    }
  }

  Map<String, dynamic> _bridgeError({
    required String code,
    required String message,
    String? method,
  }) {
    return {
      "ok": false,
      "code": code,
      "error": message,
      if (method != null) "method": method,
    };
  }

  void _validateHttpBridgeRequest(Map<String, dynamic> req) {
    final rawUrl = req["url"];
    if (rawUrl is! String || rawUrl.isEmpty) {
      throw JavaScriptRuntimeException(
        "Malformed JS bridge request: 'url' must be a non-empty string",
      );
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw JavaScriptRuntimeException("Malformed HTTP URL");
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != "http" && scheme != "https") {
      throw JavaScriptRuntimeException(
        "HTTP bridge only supports http/https URLs",
      );
    }
    final sourceKey = req["key"];
    final allowPrivateTarget =
        sourceKey is String &&
        sourceKey.isNotEmpty &&
        canUsePrivateHttpTargets(sourceKey: sourceKey);
    if (!allowPrivateTarget && _isRestrictedHttpHost(uri.host)) {
      throw JavaScriptRuntimeException(
        "HTTP bridge target is blocked by capability policy",
      );
    }
  }

  bool _isRestrictedHttpHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == "localhost") {
      return true;
    }
    final address = InternetAddress.tryParse(normalized);
    if (address == null) {
      return false;
    }
    if (address.type == InternetAddressType.IPv4) {
      final octets = normalized.split('.').map(int.tryParse).toList();
      if (octets.length != 4 || octets.any((v) => v == null)) {
        return false;
      }
      final a = octets[0]!;
      final b = octets[1]!;
      if (a == 10 || a == 127 || a == 0) {
        return true;
      }
      if (a == 169 && b == 254) {
        return true;
      }
      if (a == 172 && b >= 16 && b <= 31) {
        return true;
      }
      if (a == 192 && b == 168) {
        return true;
      }
      if (a == 100 && b >= 64 && b <= 127) {
        return true;
      }
      return false;
    }
    if (address.type == InternetAddressType.IPv6) {
      if (normalized == "::1") {
        return true;
      }
      if (normalized.startsWith("fe80:")) {
        return true;
      }
      final compact = normalized.replaceAll(':', '');
      if (compact.startsWith('fc') || compact.startsWith('fd')) {
        return true;
      }
      return false;
    }
    return false;
  }

  Object? handleBridgeMessageForTesting(dynamic message) {
    return _messageReceiver(message);
  }

  Future<Map<String, dynamic>> _http(Map<String, dynamic> req) async {
    Response? response;
    String? error;

    try {
      var headers = Map<String, dynamic>.from(req["headers"] ?? {});
      var extra = Map<String, dynamic>.from(req["extra"] ?? {});
      if (headers["user-agent"] == null && headers["User-Agent"] == null) {
        headers["User-Agent"] = webUA;
      }
      var dio = _dio;
      if (headers['http_client'] == "dart:io") {
        dio = Dio(
          BaseOptions(
            responseType: ResponseType.plain,
            validateStatus: (status) => true,
          ),
        );
        var proxy = await getProxy();
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            return HttpClient()
              ..findProxy = (uri) => proxy == null ? "DIRECT" : "PROXY $proxy";
          },
        );
        dio.interceptors.add(
          CookieManagerSql(SingleInstanceCookieJar.instance!),
        );
        dio.interceptors.add(LogInterceptor());
      }
      response = await dio!.request(
        req["url"],
        data: req["data"],
        options: Options(
          method: req['http_method'],
          responseType: req["bytes"] == true
              ? ResponseType.bytes
              : ResponseType.plain,
          headers: headers,
          extra: extra,
        ),
      );
    } catch (e) {
      error = e.toString();
    }

    Map<String, String> headers = {};

    response?.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );

    dynamic body = response?.data;
    if (body is! Uint8List && body is List<int>) {
      body = Uint8List.fromList(body);
    }

    return {
      "status": response?.statusCode,
      "headers": headers,
      "body": body,
      "error": error,
    };
  }

  dynamic runCode(String js, [String? name]) {
    return _engine!.evaluate(js, name: name);
  }

  void dispose() {
    _cache = null;
    _closed = true;
    _engine?.close();
    _engine?.port.close();
  }
}

mixin class _JSEngineApi {
  CookieJarSql? _cookieJar;

  final _documents = <int, DocumentWrapper>{};

  Object? handleHtmlCallback(Map<String, dynamic> data) {
    switch (data["function"]) {
      case "parse":
        if (_documents.length > 8) {
          var shouldDelete = _documents.keys.first;
          AppDiagnostics.warn(
            'js.engine',
            'document_cache_trimmed',
            data: {
              'evictedKey': shouldDelete,
              'currentKeys': _documents.keys.toList(),
            },
          );
          _documents.remove(shouldDelete);
        }
        _documents[_requireInt(data, "key")] = DocumentWrapper.parse(
          _requireString(data, "data"),
        );
        return null;
      case "querySelector":
        return _requireDocument(
          data,
          "key",
        ).querySelector(_requireString(data, "query"));
      case "querySelectorAll":
        return _requireDocument(
          data,
          "key",
        ).querySelectorAll(_requireString(data, "query"));
      case "getText":
        return _requireDocument(
          data,
          "doc",
        ).elementGetText(_requireInt(data, "key"));
      case "getAttributes":
        var res = _requireDocument(
          data,
          "doc",
        ).elementGetAttributes(_requireInt(data, "key"));
        return res;
      case "dom_querySelector":
        var doc = _requireDocument(data, "doc");
        return doc.elementQuerySelector(
          _requireInt(data, "key"),
          _requireString(data, "query"),
        );
      case "dom_querySelectorAll":
        var doc = _requireDocument(data, "doc");
        return doc.elementQuerySelectorAll(
          _requireInt(data, "key"),
          _requireString(data, "query"),
        );
      case "getChildren":
        var doc = _requireDocument(data, "doc");
        return doc.elementGetChildren(_requireInt(data, "key"));
      case "getNodes":
        var doc = _requireDocument(data, "doc");
        return doc.elementGetNodes(_requireInt(data, "key"));
      case "getInnerHTML":
        var doc = _requireDocument(data, "doc");
        return doc.elementGetInnerHTML(_requireInt(data, "key"));
      case "getParent":
        var doc = _requireDocument(data, "doc");
        return doc.elementGetParent(_requireInt(data, "key"));
      case "node_text":
        return _requireDocument(
          data,
          "doc",
        ).nodeGetText(_requireInt(data, "key"));
      case "node_type":
        return _requireDocument(data, "doc").nodeType(_requireInt(data, "key"));
      case "node_to_element":
        return _requireDocument(
          data,
          "doc",
        ).nodeToElement(_requireInt(data, "key"));
      case "dispose":
        var docKey = _requireInt(data, "key");
        _documents.remove(docKey);
        return null;
      case "getClassNames":
        return _requireDocument(
          data,
          "doc",
        ).getClassNames(_requireInt(data, "key"));
      case "getId":
        return _requireDocument(data, "doc").getId(_requireInt(data, "key"));
      case "getLocalName":
        return _requireDocument(
          data,
          "doc",
        ).getLocalName(_requireInt(data, "key"));
      case "getElementById":
        return _requireDocument(
          data,
          "key",
        ).getElementById(_requireString(data, "id"));
      case "getPreviousSibling":
        return _requireDocument(
          data,
          "doc",
        ).getPreviousSibling(_requireInt(data, "key"));
      case "getNextSibling":
        return _requireDocument(
          data,
          "doc",
        ).getNextSibling(_requireInt(data, "key"));
    }
    return null;
  }

  DocumentWrapper _requireDocument(Map<String, dynamic> data, String keyName) {
    final key = _requireInt(data, keyName);
    final document = _documents[key];
    if (document == null) {
      throw JavaScriptRuntimeException('DOM document not found: $key');
    }
    return document;
  }

  int _requireInt(Map<String, dynamic> data, String keyName) {
    final value = data[keyName];
    if (value is int) {
      return value;
    }
    throw JavaScriptRuntimeException(
      "Malformed JS bridge request: '$keyName' must be an int",
    );
  }

  String _requireString(Map<String, dynamic> data, String keyName) {
    final value = data[keyName];
    if (value is String) {
      return value;
    }
    throw JavaScriptRuntimeException(
      "Malformed JS bridge request: '$keyName' must be a string",
    );
  }

  dynamic handleCookieCallback(Map<String, dynamic> data) {
    switch (data["function"]) {
      case "set":
        _cookieJar!.saveFromResponse(
          Uri.parse(data["url"]),
          (data["cookies"] as List).map((e) {
            var c = Cookie(e["name"], e["value"]);
            if (e['domain'] != null) {
              c.domain = e['domain'];
            }
            return c;
          }).toList(),
        );
        return null;
      case "get":
        var cookies = _cookieJar!.loadForRequest(Uri.parse(data["url"]));
        return cookies
            .map(
              (e) => {
                "name": e.name,
                "value": e.value,
                "domain": e.domain,
                "path": e.path,
                "expires": e.expires,
                "max-age": e.maxAge,
                "secure": e.secure,
                "httpOnly": e.httpOnly,
                "session": e.expires == null,
              },
            )
            .toList();
      case "delete":
        clearCookies([data["url"]]);
        return null;
    }
  }

  void clearCookies(List<String> domains) async {
    for (var domain in domains) {
      var uri = Uri.tryParse(domain);
      if (uri == null) continue;
      _cookieJar!.deleteUri(uri);
    }
  }

  Object? _convert(Map<String, dynamic> data) {
    String type = data["type"];
    var value = data["value"];
    bool isEncode = data["isEncode"];
    try {
      if (isSensitiveCryptoType(type)) {
        _requireTrustedCryptoSource(data, type);
      }
      switch (type) {
        case "utf8":
          return isEncode ? utf8.encode(value) : utf8.decode(value);
        case "gbk":
          final codec = const GbkCodec();
          return isEncode
              ? Uint8List.fromList(codec.encode(value))
              : codec.decode(value);
        case "base64":
          return isEncode ? base64Encode(value) : base64Decode(value);
        case "md5":
          return Uint8List.fromList(md5.convert(value).bytes);
        case "sha1":
          return Uint8List.fromList(sha1.convert(value).bytes);
        case "sha256":
          return Uint8List.fromList(sha256.convert(value).bytes);
        case "sha512":
          return Uint8List.fromList(sha512.convert(value).bytes);
        case "hmac":
          var key = data["key"];
          var hash = data["hash"];
          var hmac = Hmac(switch (hash) {
            "md5" => md5,
            "sha1" => sha1,
            "sha256" => sha256,
            "sha512" => sha512,
            _ => throw "Unsupported hash: $hash",
          }, key);
          if (data['isString'] == true) {
            return hmac.convert(value).toString();
          } else {
            return Uint8List.fromList(hmac.convert(value).bytes);
          }
        case "aes-ecb":
          var key = data["key"];
          var cipher = ECBBlockCipher(AESEngine());
          cipher.init(isEncode, KeyParameter(key));
          var offset = 0;
          var result = Uint8List(value.length);
          while (offset < value.length) {
            offset += cipher.processBlock(value, offset, result, offset);
          }
          return result;
        case "aes-cbc":
          var key = data["key"];
          var iv = data["iv"];
          var cipher = CBCBlockCipher(AESEngine());
          cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
          var offset = 0;
          var result = Uint8List(value.length);
          while (offset < value.length) {
            offset += cipher.processBlock(value, offset, result, offset);
          }
          return result;
        case "aes-cfb":
          var key = data["key"];
          var iv = data["iv"];
          var blockSize = data["blockSize"];
          var cipher = CFBBlockCipher(AESEngine(), blockSize);
          cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
          var offset = 0;
          var result = Uint8List(value.length);
          while (offset < value.length) {
            offset += cipher.processBlock(value, offset, result, offset);
          }
          return result;
        case "aes-ofb":
          var key = data["key"];
          var iv = data["iv"];
          var blockSize = data["blockSize"];
          var cipher = OFBBlockCipher(AESEngine(), blockSize);
          cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
          var offset = 0;
          var result = Uint8List(value.length);
          while (offset < value.length) {
            offset += cipher.processBlock(value, offset, result, offset);
          }
          return result;
        case "rsa":
          if (!isEncode) {
            var key = data["key"];
            final cipher = PKCS1Encoding(RSAEngine());
            cipher.init(
              false,
              PrivateKeyParameter<RSAPrivateKey>(_parsePrivateKey(key)),
            );
            return _processInBlocks(cipher, value);
          }
          return null;
        default:
          return value;
      }
    } catch (e, s) {
      AppDiagnostics.error(
        'js.engine',
        e,
        stackTrace: s,
        message: 'convert_value_failed',
        data: {'type': type},
      );
      return null;
    }
  }

  RSAPrivateKey _parsePrivateKey(String privateKeyString) {
    List<int> privateKeyDER = base64Decode(privateKeyString);
    var asn1Parser = ASN1Parser(privateKeyDER as Uint8List);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    asn1Parser = ASN1Parser(privateKey.valueBytes!);
    final pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      p.integer!,
      q.integer!,
    );
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
    final numBlocks =
        input.length ~/ engine.inputBlockSize +
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

    final output = Uint8List(numBlocks * engine.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;

      outputOffset += engine.processBlock(
        input,
        inputOffset,
        chunkSize,
        output,
        outputOffset,
      );

      inputOffset += chunkSize;
    }

    return (output.length == outputOffset)
        ? output
        : output.sublist(0, outputOffset);
  }

  num _random(num min, num max, String type) {
    final random = math.Random.secure();
    if (type == "double") {
      return min + (max - min) * random.nextDouble();
    }
    return (min + (max - min) * random.nextDouble()).toInt();
  }

  void _requireTrustedCryptoSource(Map<String, dynamic> data, String type) {
    final sourceKey = data["key"];
    if (sourceKey is! String || sourceKey.isEmpty) {
      throw JavaScriptRuntimeException(
        "Sensitive crypto operation requires source key: $type",
      );
    }
    if (!canUseSensitiveCrypto(sourceKey: sourceKey)) {
      throw JavaScriptRuntimeException(
        "Sensitive crypto operation is not allowed for source: $sourceKey",
      );
    }
  }
}

class DocumentWrapper {
  final dom.Document doc;

  DocumentWrapper.parse(String doc) : doc = html.parse(doc);

  var elements = <dom.Element>[];

  var nodes = <dom.Node>[];

  int? querySelector(String query) {
    var element = doc.querySelector(query);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  List<int> querySelectorAll(String query) {
    var res = doc.querySelectorAll(query);
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  String? elementGetText(int key) {
    return _elementAt(key).text;
  }

  Map<String, String> elementGetAttributes(int key) {
    return _elementAt(
      key,
    ).attributes.map((key, value) => MapEntry(key.toString(), value));
  }

  String? elementGetInnerHTML(int key) {
    return _elementAt(key).innerHtml;
  }

  int? elementGetParent(int key) {
    var res = _elementAt(key).parent;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? elementQuerySelector(int key, String query) {
    var res = _elementAt(key).querySelector(query);
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  List<int> elementQuerySelectorAll(int key, String query) {
    var res = _elementAt(key).querySelectorAll(query);
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetChildren(int key) {
    var res = _elementAt(key).children;
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetNodes(int key) {
    var res = _elementAt(key).nodes;
    var keys = <int>[];
    for (var node in res) {
      nodes.add(node);
      keys.add(nodes.length - 1);
    }
    return keys;
  }

  String? nodeGetText(int key) {
    return _nodeAt(key).text;
  }

  String nodeType(int key) {
    return switch (_nodeAt(key).nodeType) {
      dom.Node.ELEMENT_NODE => "element",
      dom.Node.TEXT_NODE => "text",
      dom.Node.COMMENT_NODE => "comment",
      dom.Node.DOCUMENT_NODE => "document",
      _ => "unknown",
    };
  }

  int? nodeToElement(int key) {
    final node = _nodeAt(key);
    if (node is dom.Element) {
      elements.add(node);
      return elements.length - 1;
    }
    return null;
  }

  List<String> getClassNames(int key) {
    return _elementAt(key).classes.toList();
  }

  String? getId(int key) {
    return _elementAt(key).id;
  }

  String? getLocalName(int key) {
    return _elementAt(key).localName;
  }

  int? getElementById(String id) {
    var element = doc.getElementById(id);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  int? getPreviousSibling(int key) {
    var res = _elementAt(key).previousElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? getNextSibling(int key) {
    var res = _elementAt(key).nextElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  dom.Element _elementAt(int key) {
    if (key < 0 || key >= elements.length) {
      throw JavaScriptRuntimeException('DOM element not found: $key');
    }
    return elements[key];
  }

  dom.Node _nodeAt(int key) {
    if (key < 0 || key >= nodes.length) {
      throw JavaScriptRuntimeException('DOM node not found: $key');
    }
    return nodes[key];
  }
}

class JSAutoFreeFunction {
  final JSInvokable func;
  bool _disposed = false;

  /// Automatically free the function when it's not used anymore
  JSAutoFreeFunction(this.func) {
    func.dup();
    finalizer.attach(this, func, detach: this);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    finalizer.detach(this);
    func.destroy();
  }

  dynamic call(List<dynamic> args) {
    if (_disposed) {
      throw StateError('JSAutoFreeFunction has been disposed');
    }
    return func(args);
  }

  static final finalizer = Finalizer<JSInvokable>((func) {
    try {
      func.destroy();
    } catch (_) {
      // Finalizers run outside normal control flow; resource cleanup must not
      // crash the isolate if the underlying JS runtime is already unavailable.
    }
  });
}
