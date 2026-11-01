import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:tucao/common/constants.dart';
import 'package:tucao/services/cast/cast_exception.dart';
import 'package:tucao/utils/logger.dart';

/// 手机侧的媒体转发服务.
///
/// 站点直链常常校验 Referer 与 UA, 电视发请求时不会带, 于是出现手机能播,
/// 投屏后黑屏. 这里在本机开一个很小的 HTTP 服务, 只转发登记过的地址,
/// 补上请求头, 并把 https 统一成电视更容易接受的 http.
///
/// 离线缓存的本地文件也走这里, 由手机直接按 Range 读给电视, 不经过网络.
class CastProxy {
  CastProxy({
    this.userAgent = Constants.userAgent,
    String? referer,
    HttpClient? client,
    Future<String> Function()? addressResolver,
  }) : referer = referer ?? Constants.baseUrl,
       _client = client ?? HttpClient(),
       _addressResolver = addressResolver ?? _defaultAddress {
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.autoUncompress = false;
  }

  final String userAgent;

  final String referer;

  final HttpClient _client;

  final Future<String> Function() _addressResolver;

  final Map<String, Uri> _targets = {};

  /// 登记过的本地文件与其媒体类型.
  final Map<String, ({File file, String mime})> _files = {};

  HttpServer? _server;

  int get port => _server?.port ?? 0;

  bool get running => _server != null;

  /// 登记真实地址, 返回电视可以访问的转发地址.
  Future<Uri> register(String mediaUrl) async {
    final target = Uri.tryParse(mediaUrl);
    if (target == null ||
        (target.scheme != 'http' && target.scheme != 'https')) {
      throw const CastException('该地址无法投屏');
    }
    return _publish((token) => _targets[token] = target);
  }

  /// 登记本地文件, 返回电视可以访问的地址. [mime] 为空时按文件头判断.
  Future<Uri> registerFile(File file, {String? mime}) async {
    if (!await file.exists()) {
      throw const CastException('本地文件不存在, 无法投屏');
    }
    final type = mime ?? await sniffMime(file);
    return _publish((token) => _files[token] = (file: file, mime: type));
  }

  Future<Uri> _publish(void Function(String token) save) async {
    await _start();
    final address = await _addressResolver();
    final token = _token();
    save(token);
    return Uri(
      scheme: 'http',
      host: address,
      port: port,
      pathSegments: ['cast', token],
    );
  }

  /// 按文件头判断常见的媒体类型, 认不出时按 mp4 处理.
  ///
  /// 缓存文件没有可靠的后缀, 电视又会按这个类型决定能不能播.
  static Future<String> sniffMime(File file) async {
    final head = <int>[];
    try {
      await for (final chunk in file.openRead(0, 12)) {
        head.addAll(chunk);
      }
    } on FileSystemException {
      return 'video/mp4';
    }
    bool at(int offset, List<int> magic) {
      if (head.length < offset + magic.length) {
        return false;
      }
      for (var index = 0; index < magic.length; index++) {
        if (head[offset + index] != magic[index]) {
          return false;
        }
      }
      return true;
    }

    if (at(0, const [0x46, 0x4c, 0x56])) {
      return 'video/x-flv';
    }
    if (at(0, const [0x1a, 0x45, 0xdf, 0xa3])) {
      return 'video/x-matroska';
    }
    if (at(0, const [0x49, 0x44, 0x33]) || at(0, const [0xff, 0xfb])) {
      return 'audio/mpeg';
    }
    // mp4 / mov 第 4 字节起是 ftyp, 其余情况也当 mp4.
    return 'video/mp4';
  }

  Future<void> _start() async {
    if (_server != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object error) => Log.w('投屏转发服务出错: $error'),
    );
    Log.i('投屏转发服务已启动, 端口 $port');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final token = segments.length == 2 && segments.first == 'cast'
        ? segments[1]
        : null;
    final target = _targets[token];
    final local = _files[token];
    if (target == null && local == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    if (local != null) {
      try {
        await _serveFile(request, local.file, local.mime);
      } on FileSystemException catch (error) {
        Log.w('读取投屏本地文件失败: $error');
        await _abort(response, HttpStatus.notFound);
      } on IOException {
        // 电视中途跳转或退出时连接会断, 不算错误.
        await _abort(response, HttpStatus.ok);
      }
      return;
    }
    final remote = target!;
    try {
      await _forward(request, remote);
    } on SocketException catch (error) {
      Log.w('转发媒体失败 ${remote.host}: $error');
      await _abort(response, HttpStatus.badGateway);
    } catch (error) {
      Log.w('转发媒体出错: $error');
      await _abort(response, HttpStatus.badGateway);
    }
  }

  Future<void> _abort(HttpResponse response, int status) async {
    try {
      response.statusCode = status;
      await response.close();
    } catch (_) {
      // 客户端已经断开时忽略.
    }
  }

  Future<void> _forward(HttpRequest request, Uri target) async {
    final upstream = await _client.openUrl(request.method, target);
    upstream.headers.set(HttpHeaders.userAgentHeader, userAgent);
    upstream.headers.set(HttpHeaders.refererHeader, referer);
    upstream.headers.set(HttpHeaders.acceptHeader, '*/*');
    upstream.headers.set(HttpHeaders.connectionHeader, 'close');
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      upstream.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await upstream.close();
    final client = request.response;
    client.statusCode = response.statusCode;
    for (final header in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.cacheControlHeader,
    ]) {
      final value = response.headers.value(header);
      if (value != null) {
        client.headers.set(header, value);
      }
    }
    client.headers.set('server', 'tucao-cast');
    if (request.method == 'HEAD') {
      await response.drain<void>();
      await client.close();
      return;
    }
    try {
      await response.pipe(client);
    } on IOException {
      // 电视中途换分P或退出时连接会断, 不算错误.
      try {
        await client.close();
      } on IOException {
        // 已经断开, 忽略.
      }
    }
  }

  /// 直接读本地文件给电视, 支持单段 Range, 电视拖动进度要靠它.
  Future<void> _serveFile(HttpRequest request, File file, String mime) async {
    final client = request.response;
    final length = await file.length();
    client.headers.set(HttpHeaders.contentTypeHeader, mime);
    client.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    client.headers.set('server', 'tucao-cast');
    var start = 0;
    var end = length - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final parsed = _parseRange(range, length);
      if (parsed == null) {
        client.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        client.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await client.close();
        return;
      }
      (start, end) = parsed;
      client.statusCode = HttpStatus.partialContent;
      client.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    client.contentLength = end - start + 1;
    if (request.method == 'HEAD') {
      await client.close();
      return;
    }
    await client.addStream(file.openRead(start, end + 1));
    await client.close();
  }

  /// 解析 `bytes=a-b`, `bytes=a-`, `bytes=-n`, 不合法或越界时返回空.
  static (int, int)? _parseRange(String header, int length) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || length <= 0) {
      return null;
    }
    final first = int.tryParse(match.group(1)!);
    final last = int.tryParse(match.group(2)!);
    if (first == null) {
      // 只给了末尾长度, 取最后 n 字节.
      if (last == null || last <= 0) {
        return null;
      }
      return (last >= length ? 0 : length - last, length - 1);
    }
    if (first >= length || (last != null && last < first)) {
      return null;
    }
    return (first, last == null || last >= length ? length - 1 : last);
  }

  Future<void> close() async {
    _targets.clear();
    _files.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  void dispose() {
    unawaited(close());
    _client.close(force: true);
  }

  String _token() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 手机在局域网里的地址, 电视要能连上它.
  static Future<String> _defaultAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final candidates = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        if (_isPrivate(ip)) {
          candidates.add(ip);
        }
      }
    }
    if (candidates.isEmpty) {
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            candidates.add(address.address);
          }
        }
      }
    }
    if (candidates.isEmpty) {
      throw const CastException('没有可用的局域网地址, 请先连接 Wi-Fi');
    }
    // 家用网段优先, 其次是常见的容器与热点网段.
    candidates.sort((a, b) => _priority(a).compareTo(_priority(b)));
    return candidates.first;
  }

  static bool _isPrivate(String ip) {
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        _isPrivate172(ip);
  }

  static bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) {
      return false;
    }
    final second = int.tryParse(ip.split('.').elementAt(1));
    return second != null && second >= 16 && second <= 31;
  }

  static int _priority(String ip) {
    if (ip.startsWith('192.168.')) {
      return 0;
    }
    if (ip.startsWith('10.')) {
      return 1;
    }
    if (_isPrivate172(ip)) {
      return 2;
    }
    return 3;
  }
}
