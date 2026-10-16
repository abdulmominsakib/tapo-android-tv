// Dart port of upstream `tapo_cloud_probe.py` + the relay part of
// `tapo_cloud_app.py` (https://github.com/filirnd/topo).
//
// It talks only to the Tapo cloud: account login with MFA, device list,
// camera control through the IoT gateway, and the CIPC video relay. The API
// is private and undocumented; it may change without notice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const appName = 'TP-Link_Tapo_Android';
const appVersion = '3.21.114';
const productName = 'Topo TV';
const loginUrl = 'https://n-wap-gw.tplinkcloud.com';
const defaultCipcUrl = 'https://cipc.api.cloud';

// App-level credentials of the Tapo Android client. They identify the client
// application, not the user's account.
const _accessKey = '4d11b6b9d5ea4d19a829adbb9714b057';
const _accessSecret = '6ed7d97f3e73467f8a5bab90b577ba4c';

const _deviceErrorMessages = {
  -64303: 'Motor busy, wait for the movement to finish',
  -64304: 'Maximum pan/tilt limit reached',
  -64324: 'Privacy mode is on',
  -64336: 'Movement blocked by a privacy zone',
};

const _loginErrorMessages = {
  -20601: 'Incorrect email or password',
  -20600: 'Account not found',
};

class TapoException implements Exception {
  TapoException(this.message, {this.code});
  final String message;
  final int? code;

  /// True when the cloud session token is no longer accepted.
  bool get isAuthError => code == -20651;

  @override
  String toString() => message;
}

String randomUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

int errorCode(Object? value) {
  if (value is! Map) return 0;
  for (final key in const ['error_code', 'errorCode']) {
    if (value.containsKey(key)) {
      final v = value[key];
      if (v is int) return v;
      return int.tryParse('$v') ?? 1;
    }
  }
  return 0;
}

Map<String, dynamic> resultOf(Map<String, dynamic> response) {
  final value = response['result'];
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

String _describe(String what, int code) {
  final known = _loginErrorMessages[code];
  return known != null ? '$known ($code)' : '$what (code $code)';
}

/// Result of [TapoCloud.login]: either a token or a pending MFA challenge.
class LoginResult {
  LoginResult(this.baseUrl, this.result);
  final String baseUrl;
  final Map<String, dynamic> result;

  String? get token => result['token'] as String?;
  String? get mfaProcessId => result['MFAProcessId']?.toString();
  List<int> get mfaTypes {
    final raw = result['supportedMFATypes'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => int.tryParse('$e') ?? 2).toList();
    }
    return const [2];
  }
}

class RelayInfo {
  RelayInfo({
    required this.host,
    required this.port,
    required this.path,
    required this.token,
    required this.playerId,
    this.elbCookie,
  });
  final String host;
  final int port;
  final String path;
  final String token;
  final String playerId;
  final String? elbCookie;
}

class TapoCloud {
  TapoCloud({required this.terminalUuid, required SecurityContext context})
      : _context = context,
        _http = HttpClient(context: context)
          ..connectionTimeout = const Duration(seconds: 15)
          ..idleTimeout = const Duration(seconds: 30);

  /// TP-Link serves a CA chain that ships with the Tapo app but not with all
  /// trust stores. Keep the system roots and add those two public roots; TLS
  /// and hostname verification stay enabled.
  static SecurityContext buildContext(List<int> tpLinkRootsPem) {
    return SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(tpLinkRootsPem);
  }

  final String terminalUuid;
  final SecurityContext _context;
  final HttpClient _http;
  String token = '';
  String _cipcUrl = defaultCipcUrl;
  String _cipcDiscoveryBase = '';
  String _iotAppServer = '';
  String _servicesSyncVersion = 'v2';

  void close() => _http.close(force: true);

  // ---------------------------------------------------------------- HTTP --

  static Uint8List _body(Map<String, dynamic> payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));

  Map<String, String> _signedHeaders(Uint8List body, String endpoint) {
    final nonce = randomUuid();
    const timestamp = '9999999999';
    final contentMd5 = base64.encode(md5.convert(body).bytes);
    final message = [contentMd5, timestamp, nonce, endpoint].join('\n');
    final signature = Hmac(sha1, utf8.encode(_accessSecret))
        .convert(utf8.encode(message))
        .toString();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Content-MD5': contentMd5,
      'X-Authorization': 'Timestamp=$timestamp, Nonce=$nonce, '
          'AccessKey=$_accessKey, Signature=$signature',
      'User-Agent': 'okhttp/3.12.13',
    };
  }

  Future<(int, Map<String, dynamic>)> _postRaw(
    Uri uri,
    Uint8List body,
    Map<String, String> headers,
  ) async {
    final HttpClientResponse response;
    try {
      final request = await _http.postUrl(uri);
      headers.forEach((k, v) => request.headers.set(k, v, preserveHeaderCase: true));
      request.contentLength = body.length;
      request.add(body);
      response = await request.close().timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw TapoException('Network error: ${e.osError?.message ?? e.message}');
    } on HandshakeException catch (e) {
      throw TapoException('Secure connection failed: ${e.message}');
    } on TimeoutException {
      throw TapoException('The Tapo cloud did not answer in time');
    } on HttpException catch (e) {
      throw TapoException('Network error: ${e.message}');
    }
    final raw = await response.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, chunk) => b..add(chunk),
    );
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw.takeBytes()));
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      if (response.statusCode >= 400) {
        throw TapoException('Cloud rejected the request (HTTP ${response.statusCode})');
      }
      throw TapoException('Unexpected answer from the Tapo cloud');
    }
    return (response.statusCode, decoded);
  }

  Future<Map<String, dynamic>> post(
    String baseUrl,
    String endpoint,
    Map<String, dynamic> payload, {
    required bool withToken,
  }) async {
    final body = _body(payload);
    var uri = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '') + endpoint);
    if (withToken) uri = uri.replace(queryParameters: {'token': token});
    final (_, decoded) = await _postRaw(uri, body, _signedHeaders(body, endpoint));
    return decoded;
  }

  Future<Map<String, dynamic>> postCipc(
    String endpoint,
    Map<String, dynamic> payload,
    String playerId,
  ) async {
    final body = _body(payload);
    final uri = Uri.parse(_cipcUrl.replaceAll(RegExp(r'/+$'), '') + endpoint);
    try {
      final (_, decoded) = await _postRaw(uri, body, {
        // CIPC expects the raw cloud token (no `ut|` prefix).
        'Authorization': token,
        'Content-Type': 'application/json; charset=UTF-8',
        'User-Agent': 'Tapo_APP/Linux/${appVersion}_Android/Android 14',
        'X-Client-Id': playerId,
        'X-Source': 'tapo-app',
        'X-Brand': 'TPLINK',
        'X-Ca-Type': 'cloud-self',
        'X-Request-Signature': randomUuid().replaceAll('-', '').substring(0, 10),
      });
      return decoded;
    } on TapoException {
      _cipcDiscoveryBase = '';
      rethrow;
    }
  }

  Future<String> _discoverService(String baseUrl, String serviceId) async {
    final response = await post(
      baseUrl,
      '/api/v2/common/getAppServiceUrl',
      {
        'serviceIds': [serviceId],
      },
      withToken: true,
    );
    final code = errorCode(response);
    if (code != 0) {
      throw TapoException('Service discovery rejected (code $code)', code: code);
    }
    final services = resultOf(response)['serviceUrls'];
    final url = services is Map ? services[serviceId] : null;
    if (url == null || '$url'.isEmpty) {
      throw TapoException('$serviceId endpoint missing from cloud response');
    }
    return '$url'.replaceFirst('http://', 'https://');
  }

  Future<void> _ensureCipc(String baseUrl) async {
    if (_cipcDiscoveryBase == baseUrl) return;
    _cipcUrl = await _discoverService(baseUrl, 'cipc.api.cloud');
    _cipcDiscoveryBase = baseUrl;
  }

  // --------------------------------------------------------------- Login --

  Map<String, dynamic> _loginPayload(String username, String password) => {
        'appType': appName,
        'appVersion': appVersion,
        'cloudPassword': password,
        'cloudUserName': username,
        'platform': 'Android 14',
        'refreshTokenNeeded': false,
        'supportBindAccount': false,
        'terminalMeta': '1',
        'terminalName': '$productName - Android TV',
        'terminalUUID': terminalUuid,
      };

  Future<LoginResult> login(String username, String password) async {
    final payload = _loginPayload(username, password);
    var response = await post(loginUrl, '/api/v2/account/login', payload, withToken: false);
    var code = errorCode(response);
    if (code != 0) throw TapoException(_describe('Login rejected', code), code: code);
    var result = resultOf(response);
    // Accounts outside the global region are redirected to a regional URL.
    if (errorCode(result) == -20212 && result['appServerUrl'] != null) {
      final regional = '${result['appServerUrl']}';
      response = await post(regional, '/api/v2/account/login', payload, withToken: false);
      code = errorCode(response);
      if (code != 0) throw TapoException(_describe('Login rejected', code), code: code);
      result = resultOf(response);
      return LoginResult(regional, result);
    }
    final inner = errorCode(result);
    if (inner != 0 && result['MFAProcessId'] == null) {
      throw TapoException(_describe('Login rejected', inner), code: inner);
    }
    return LoginResult(loginUrl, result);
  }

  /// [mfaType] 1 = push to the Tapo phone app, 2 = email code.
  Future<void> requestMfa(String baseUrl, String username, String password, int mfaType) async {
    final endpoint = mfaType == 1
        ? '/api/v2/account/getPushVC4TerminalMFA'
        : '/api/v2/account/getEmailVC4TerminalMFA';
    final sent = await post(
      baseUrl,
      endpoint,
      {
        'appType': appName,
        'cloudPassword': password,
        'cloudUserName': username,
        'terminalUUID': terminalUuid,
      },
      withToken: false,
    );
    final outer = errorCode(sent), inner = errorCode(resultOf(sent));
    if (outer != 0 || inner != 0) {
      final code = inner != 0 ? inner : outer;
      throw TapoException(_describe('Could not send the verification code', code), code: code);
    }
  }

  Future<Map<String, dynamic>> verifyMfa(
    String baseUrl,
    String username,
    String code,
    String processId,
    int mfaType,
  ) async {
    final checked = await post(
      baseUrl,
      '/api/v2/account/checkMFACodeAndLogin',
      {
        'appType': appName,
        'cloudUserName': username,
        'code': code,
        'MFAProcessId': processId,
        'MFAType': mfaType,
        'terminalBindEnabled': true,
      },
      withToken: false,
    );
    final outer = errorCode(checked), inner = errorCode(resultOf(checked));
    if (outer != 0 || inner != 0) {
      final c = inner != 0 ? inner : outer;
      throw TapoException(_describe('Verification code rejected', c), code: c);
    }
    return resultOf(checked);
  }

  // ------------------------------------------------------------- Devices --

  Future<List<Map<String, dynamic>>> listCameras(String baseUrl) async {
    final devices = <Map<String, dynamic>>[];
    for (var index = 0; index < 200; index += 20) {
      final response = await post(
        baseUrl,
        '/api/v2/common/getDeviceListByPage',
        {
          'deviceTypeList': ['SMART.IPCAMERA'],
          'index': index,
          'limit': 20,
        },
        withToken: true,
      );
      final code = errorCode(response);
      if (code != 0) {
        throw TapoException('Could not load cameras (code $code)', code: code);
      }
      final page = resultOf(response)['deviceList'];
      if (page is! List) break;
      devices.addAll(page.whereType<Map<String, dynamic>>());
      final total = resultOf(response)['totalNum'];
      if (page.length < 20 || (total is int && devices.length >= total)) break;
    }
    return devices;
  }

  Map<String, String> _iotHeaders() => {
        'Authorization': 'ut|$token',
        'app-cid': 'app:$appName:$terminalUuid',
        'x-app-name': appName,
        'x-app-version': appVersion,
        'x-term-id': terminalUuid,
        'x-ospf': 'Android 14',
        'x-net-type': 'wifi',
        'x-strict': '0',
        'x-locale': 'en_US',
        'Content-Type': 'application/json; charset=UTF-8',
        'User-Agent': '$appName/$appVersion(cloud-only;AndroidTV)',
      };

  /// Send camera control methods through Tapo's IoT cloud gateway.
  Future<List<dynamic>> servicesSync(
    String baseUrl,
    String deviceId,
    List<Map<String, dynamic>> requests,
  ) async {
    if (_iotAppServer.isEmpty) {
      _iotAppServer = await _discoverService(baseUrl, 'nbu.iot-app-server.app');
    }
    final body = _body({
      'inputParams': {
        'requestData': {
          'method': 'multipleRequest',
          'params': {'requests': requests},
        },
      },
      'serviceId': 'passthrough',
    });
    Uri url(String version) => Uri.parse(
        '${_iotAppServer.replaceAll(RegExp(r'/+$'), '')}/$version/things/'
        '${Uri.encodeComponent(deviceId)}/services-sync');
    var (status, decoded) = await _postRaw(url(_servicesSyncVersion), body, _iotHeaders());
    if ({404, 405, 501}.contains(status) && _servicesSyncVersion == 'v2') {
      // Older regional gateways only expose v1.
      _servicesSyncVersion = 'v1';
      (status, decoded) = await _postRaw(url('v1'), body, _iotHeaders());
    }
    if (status >= 400) {
      final msg = decoded['message'] ?? decoded['msg'];
      throw TapoException('Camera control rejected (HTTP $status)${msg != null ? ': $msg' : ''}');
    }
    final output = decoded['outputParams'];
    final data = output is Map ? output['responseData'] : null;
    if (data is! Map) throw TapoException('Camera did not answer');
    final code = errorCode(data);
    if (code != 0) {
      throw TapoException(_deviceErrorMessages[code] ?? 'Camera control rejected (code $code)', code: code);
    }
    final responses = (data['result'] is Map) ? data['result']['responses'] : null;
    if (responses is! List) throw TapoException('Camera returned no answer');
    return responses;
  }

  Map<String, dynamic> _firstResponse(List<dynamic> responses, String method) {
    if (responses.isEmpty || responses.first is! Map) {
      throw TapoException('Incomplete $method response');
    }
    final response = Map<String, dynamic>.from(responses.first as Map);
    final code = errorCode(response);
    if (code != 0) {
      throw TapoException(_deviceErrorMessages[code] ?? '$method rejected by camera (code $code)', code: code);
    }
    return response;
  }

  Future<bool> getPrivacyMode(String baseUrl, String deviceId) async {
    final responses = await servicesSync(baseUrl, deviceId, [
      {
        'method': 'getLensMaskConfig',
        'params': {
          'lens_mask': {
            'name': ['lens_mask_info'],
          },
        },
      },
    ]);
    final result = _firstResponse(responses, 'getLensMaskConfig')['result'];
    final lensMask = result is Map ? result['lens_mask'] : null;
    final info = lensMask is Map ? lensMask['lens_mask_info'] : null;
    final enabled = info is Map ? info['enabled'] : null;
    if (enabled != 'on' && enabled != 'off') {
      throw TapoException('Privacy state missing from camera answer');
    }
    return enabled == 'on';
  }

  Future<bool> setPrivacyMode(String baseUrl, String deviceId, bool enabled) async {
    final responses = await servicesSync(baseUrl, deviceId, [
      {
        'method': 'setLensMaskConfig',
        'params': {
          'lens_mask': {
            'lens_mask_info': {'enabled': enabled ? 'on' : 'off'},
          },
        },
      },
    ]);
    _firstResponse(responses, 'setLensMaskConfig');
    // The camera applies the change asynchronously; poll for the new state.
    Object? lastError;
    for (final delay in const [0, 400, 800, 1200, 1600]) {
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      try {
        if (await getPrivacyMode(baseUrl, deviceId) == enabled) return enabled;
        lastError = null;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw TapoException('Privacy mode did not change, try again');
  }

  Future<bool> ptzSupported(String baseUrl, String deviceId) async {
    final responses = await servicesSync(baseUrl, deviceId, [
      {
        'method': 'getAppComponentList',
        'params': {
          'app_component': {
            'name': ['app_component_list'],
          },
        },
      },
    ]);
    final result = _firstResponse(responses, 'getAppComponentList')['result'];
    final list = (result is Map && result['app_component'] is Map)
        ? result['app_component']['app_component_list']
        : null;
    return list is List && list.any((item) => item is Map && item['name'] == 'ptz');
  }

  /// Relative pan/tilt step; x>0 pans right, y>0 tilts up.
  Future<void> moveMotor(String baseUrl, String deviceId, int x, int y) async {
    if (x.abs() > 200 || y.abs() > 200) {
      throw TapoException('Movement must be between -200 and 200');
    }
    final responses = await servicesSync(baseUrl, deviceId, [
      {
        'method': 'motorMove',
        'params': {
          'motor': {
            'move': {'x_coord': '$x', 'y_coord': '$y'},
          },
        },
      },
    ]);
    _firstResponse(responses, 'motorMove');
  }

  // --------------------------------------------------------------- Relay --

  Future<RelayInfo> requestRelay(String baseUrl, Map<String, dynamic> device) async {
    final deviceId = '${device['deviceId'] ?? ''}';
    if (deviceId.isEmpty) throw TapoException('Camera has no deviceId');
    await _ensureCipc(baseUrl);
    final playerId = randomUuid();
    final response = await postCipc('/v2/relay/request', {
      'deviceId': deviceId,
      'dataTimeoutCount': 0,
      'cloudType': 2,
      'deviceType': device['deviceType'] ?? 'SMART.IPCAMERA',
      'playerId': playerId,
      'rootCaVer': '1',
      'streamType': 0,
      'preConnection': 0,
      'resolution': 'HD',
    }, playerId);
    final info = resultOf(response);
    final code = errorCode(response);
    if (code != 0) {
      throw TapoException(
        code == -40401 || code == -40406
            ? 'Camera is offline'
            : 'Cloud relay rejected the stream (code $code)',
        code: code,
      );
    }
    final relayUrl = '${info['relayUrl'] ?? ''}';
    final relayToken = '${info['relayToken'] ?? info['sessionToken'] ?? ''}';
    if (relayUrl.isEmpty || relayToken.isEmpty) {
      throw TapoException('Incomplete relay answer from the cloud');
    }
    // The relay query is an opaque signed string: keep it byte-for-byte.
    final full = relayUrl.contains('://') ? relayUrl : 'https://$relayUrl';
    final schemeEnd = full.indexOf('://') + 3;
    final pathStart = full.indexOf('/', schemeEnd);
    final authority = pathStart < 0 ? full.substring(schemeEnd) : full.substring(schemeEnd, pathStart);
    var pathAndQuery = pathStart < 0 ? '/' : full.substring(pathStart);
    pathAndQuery += pathAndQuery.contains('?') ? '&retryTime=0' : '?retryTime=0';
    final colon = authority.lastIndexOf(':');
    final host = colon > 0 ? authority.substring(0, colon) : authority;
    final port = colon > 0 ? int.tryParse(authority.substring(colon + 1)) ?? 443 : 443;
    return RelayInfo(
      host: host,
      port: port,
      path: pathAndQuery,
      token: relayToken,
      playerId: playerId,
      elbCookie: info['elbCookie']?.toString(),
    );
  }

  /// Opens the relay and yields the raw MPEG-TS video bytes.
  Stream<Uint8List> openVideoStream(String baseUrl, Map<String, dynamic> device) async* {
    final relay = await requestRelay(baseUrl, device);
    final headers = <String, String>{
      'Host': relay.host,
      'User-Agent': 'Client=$appName Android $appVersion/1.3',
      'Keep-Relay': '3600',
      'Accept': '*/*',
      'Content-Type': 'multipart/mixed;boundary=--client-stream-boundary--',
      'Content-Length': '9223372036854775807',
      'X-token': relay.token,
      'X-Client-Model': '${device['deviceModel'] ?? 'C200'}',
      'X-Client-UUID': relay.playerId,
      'X-Redirect-Times': '0',
      // PullMode.DIRECT_FORWARDING of the official client.
      'X-Pull-Mode': '2',
      'X-Version': '2.0',
      'X-Arrive-Latency': '0',
      'Connection': 'Keep-alive',
      if (relay.elbCookie != null && relay.elbCookie!.isNotEmpty) 'Cookie': relay.elbCookie!,
    };
    final request = StringBuffer('POST ${relay.path} HTTP/1.1\r\n');
    headers.forEach((k, v) => request.write('$k: $v\r\n'));
    request.write('\r\n');

    final SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        relay.host,
        relay.port,
        context: _context,
        timeout: const Duration(seconds: 15),
      );
    } on SocketException catch (e) {
      throw TapoException('Could not reach the video relay: ${e.message}');
    }
    try {
      socket.add(ascii.encode(request.toString()));
      await socket.flush();
      yield* parseRelayResponse(socket);
    } finally {
      socket.destroy();
    }
  }
}

/// Parses the relay's HTTP response: a `multipart/mixed` body whose parts
/// (boundary `--device-stream-boundary--`) carry MPEG-TS video. Yields the
/// raw video bytes as they arrive.
Stream<Uint8List> parseRelayResponse(Stream<Uint8List> source) async* {
  final reader = _ByteReader(source);
  try {
    final status = await reader.readHttpHeaders();
    if (!status.startsWith('HTTP/1.1 200')) {
      throw TapoException('Video relay refused the connection');
    }
    while (true) {
      final line = await reader.readLine();
      // The wire boundary normally has four leading hyphens; match by
      // containment like the official client.
      if (line.isEmpty || !line.contains('--device-stream-boundary--')) continue;
      final partHeaders = <String, String>{};
      while (true) {
        final h = await reader.readLine();
        if (h.isEmpty) break;
        final sep = h.indexOf(':');
        if (sep > 0) {
          partHeaders[h.substring(0, sep).trim().toLowerCase()] = h.substring(sep + 1).trim();
        }
      }
      if (partHeaders['x-if-encrypt'] == '1') {
        throw TapoException('This camera sends encrypted video, which is not supported yet');
      }
      final length = int.tryParse(partHeaders['content-length'] ?? '0') ?? 0;
      if (length <= 0) continue;
      yield* reader.readExact(length);
    }
  } finally {
    await reader.cancel();
  }
}

/// Minimal buffered reader over a socket for HTTP/multipart framing.
class _ByteReader {
  _ByteReader(Stream<Uint8List> source) : _it = StreamIterator(source);

  static const _timeout = Duration(seconds: 20);
  final StreamIterator<Uint8List> _it;
  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  int get _available => _buf.length - _pos;

  Future<void> _fill() async {
    final hasMore = await _it.moveNext().timeout(
          _timeout,
          onTimeout: () => throw TapoException('Camera stopped sending video'),
        );
    if (!hasMore) throw TapoException('Video relay closed the connection');
    final chunk = _it.current;
    if (_available == 0) {
      _buf = chunk;
    } else {
      final merged = Uint8List(_available + chunk.length)
        ..setRange(0, _available, _buf, _pos)
        ..setRange(_available, _available + chunk.length, chunk);
      _buf = merged;
    }
    _pos = 0;
  }

  int _indexOfCrlf(int from) {
    for (var i = from; i < _buf.length - 1; i++) {
      if (_buf[i] == 13 && _buf[i + 1] == 10) return i;
    }
    return -1;
  }

  Future<String> readLine() async {
    var scanFrom = _pos;
    while (true) {
      final idx = _indexOfCrlf(scanFrom);
      if (idx >= 0) {
        final line = latin1.decode(Uint8List.sublistView(_buf, _pos, idx));
        _pos = idx + 2;
        return line;
      }
      if (_available > 65536) throw TapoException('Malformed video relay data');
      final consumed = _pos;
      final scanned = max(_buf.length - 1, _pos);
      await _fill();
      scanFrom = max(0, scanned - consumed);
    }
  }

  /// Reads the HTTP response head and returns its status line.
  Future<String> readHttpHeaders() async {
    final status = await readLine();
    while ((await readLine()).isNotEmpty) {}
    return status;
  }

  Stream<Uint8List> readExact(int length) async* {
    var remaining = length;
    while (remaining > 0) {
      if (_available == 0) await _fill();
      final take = min(remaining, _available);
      yield Uint8List.sublistView(_buf, _pos, _pos + take);
      _pos += take;
      remaining -= take;
    }
  }

  Future<void> cancel() => _it.cancel();
}
