import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/relay_bridge.dart';
import '../api/tapo_cloud.dart';
import '../player/stream_queue.dart';
import 'grids.dart';

enum AuthStage { starting, signedOut, mfa, signedIn }

class Camera {
  Camera(this.raw);
  final Map<String, dynamic> raw;

  String get deviceId => '${raw['deviceId'] ?? ''}';
  String get name => '${raw['alias'] ?? raw['deviceName'] ?? 'Camera'}'.trim();
  String get model => '${raw['deviceModel'] ?? ''}';
  String get firmware => '${raw['fwVer'] ?? ''}'.split(' ').first;

  /// Account list status; not a live reachability check (the relay can still
  /// work while this reports 0), so it is only used as a hint.
  bool get reportedOnline => raw['status'] == 1;

  bool? privacy;
  bool? ptz;
  String? stateError;
  DateTime? checkedAt;
}

class PendingMfa {
  PendingMfa({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.processId,
    required this.types,
  });
  final String baseUrl;
  final String username;
  final String password;
  final String processId;
  final List<int> types;
  int? requestedType;
}

class AppState extends ChangeNotifier {
  /// UI test mode (`--dart-define=TOPO_DEMO=true`): fake cameras, no cloud.
  static const demo = bool.fromEnvironment('TOPO_DEMO');

  static const _kSession = 'session';
  static const _kTerminal = 'terminal_uuid';
  static const _kLivePreviews = 'live_previews';
  static const _kPtzStep = 'ptz_step';
  static const _kGuideSeen = 'guide_seen';
  static const _kAccount = 'account_hint';
  static const _kGrids = 'grids';
  static const _kActiveGrid = 'active_grid';
  static const _kFavoriteGrid = 'favorite_grid';

  late SharedPreferences _prefs;
  late SecurityContext _context;
  bool _bootstrapped = false;
  TapoCloud? _client;
  String _baseUrl = loginUrl;
  late final RelayBridge relay = RelayBridge(_resolveForRelay);

  AuthStage stage = AuthStage.starting;
  PendingMfa? pendingMfa;
  List<Camera> cameras = [];
  bool loadingCameras = false;
  String? camerasError;
  String accountHint = '';

  /// False while the app is in the background: all video is stopped.
  bool foreground = true;

  bool livePreviews = true;
  int ptzStep = 10;
  bool guideSeen = false;

  /// User-saved multi-view grids (the built-in "All cameras" is not stored).
  List<GridPreset> savedGrids = [];
  String activeGridId = GridPreset.allCamerasId;

  /// Grid pinned to the top of the home page, if any.
  String? favoriteGridId;

  TapoCloud? get client => _client;

  Future<void> init() async {
    if (!_bootstrapped) {
      _prefs = await SharedPreferences.getInstance();
      final pem = await rootBundle.load('assets/tapo-cloud-roots.pem');
      _context = TapoCloud.buildContext(pem.buffer.asUint8List());
      livePreviews = _prefs.getBool(_kLivePreviews) ?? true;
      ptzStep = _prefs.getInt(_kPtzStep) ?? 10;
      guideSeen = _prefs.getBool(_kGuideSeen) ?? false;
      accountHint = _prefs.getString(_kAccount) ?? '';
      _loadGrids();
      await Snapshots.instance.init();
      await relay.start();
      _bootstrapped = true;
    }
    camerasError = null;

    if (demo) {
      cameras = [
        for (final (name, model, ptz, privacy) in const [
          ('Living room', 'C200', true, false),
          ('Front door', 'C320WS', false, false),
          ('Garden', 'C500', true, false),
          ('Baby room', 'C210', true, true),
          ('Garage', 'C110', false, false),
        ])
          Camera({'deviceId': 'demo-$name', 'alias': name, 'deviceModel': model, '_ptz': ptz, '_privacy': privacy}),
      ];
      stage = AuthStage.signedIn;
      notifyListeners();
      for (final c in cameras) {
        unawaited(refreshCameraState(c));
      }
      return;
    }

    final saved = _prefs.getString(_kSession);
    if (saved != null) {
      try {
        final session = jsonDecode(saved) as Map<String, dynamic>;
        final client = _newClient()..token = '${session['token']}';
        final baseUrl = '${session['base_url'] ?? loginUrl}';
        final devices = await client.listCameras(baseUrl);
        _setSignedIn(client, baseUrl, devices);
        return;
      } on TapoException catch (e) {
        if (e.code != null) await _prefs.remove(_kSession);
        // Without a code it was a network problem: keep the session and let
        // the user retry from the sign-in screen.
        camerasError = e.message;
      } catch (_) {
        await _prefs.remove(_kSession);
      }
    }
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  bool get hasSavedSession => _prefs.getString(_kSession) != null;

  Future<void> retrySavedSession() async {
    stage = AuthStage.starting;
    notifyListeners();
    await init();
  }

  TapoCloud _newClient() {
    var terminal = _prefs.getString(_kTerminal);
    if (terminal == null || terminal.isEmpty) {
      terminal = randomUuid().replaceAll('-', '').toUpperCase();
      _prefs.setString(_kTerminal, terminal);
    }
    return TapoCloud(terminalUuid: terminal, context: _context);
  }

  (TapoCloud, String, Map<String, dynamic>)? _resolveForRelay(String deviceId) {
    final client = _client;
    if (client == null) return null;
    for (final c in cameras) {
      if (c.deviceId == deviceId) return (client, _baseUrl, c.raw);
    }
    return null;
  }

  /// Demo mode only: an MPEG-TS URL used instead of the cloud relay, e.g.
  /// `--dart-define=TOPO_DEMO_STREAM=http://127.0.0.1:8099/live.ts` with
  /// `adb reverse tcp:8099 tcp:8099`.
  static const _demoStream = String.fromEnvironment('TOPO_DEMO_STREAM');

  String streamUrl(Camera camera) =>
      demo && _demoStream.isNotEmpty ? '$_demoStream?cam=${Uri.encodeComponent(camera.deviceId)}' : relay.urlFor(camera.deviceId);

  // ---------------------------------------------------------------- Auth --

  /// Returns true when a verification step is needed.
  Future<bool> login(String username, String password) async {
    username = username.trim();
    if (username.isEmpty || password.isEmpty) {
      throw TapoException('Enter your Tapo email and password');
    }
    final client = _newClient();
    final result = await client.login(username, password);
    final processId = result.mfaProcessId;
    accountHint = username;
    await _prefs.setString(_kAccount, username);
    if (processId != null && processId.isNotEmpty) {
      _client?.close();
      _client = client;
      pendingMfa = PendingMfa(
        baseUrl: result.baseUrl,
        username: username,
        password: password,
        processId: processId,
        types: result.mfaTypes,
      );
      stage = AuthStage.mfa;
      notifyListeners();
      return true;
    }
    await _finishLogin(client, result.baseUrl, result.result);
    return false;
  }

  Future<void> requestMfa(int type) async {
    final pending = pendingMfa;
    final client = _client;
    if (pending == null || client == null) throw TapoException('Sign in again');
    await client.requestMfa(pending.baseUrl, pending.username, pending.password, type);
    pending.requestedType = type;
    notifyListeners();
  }

  Future<void> verifyMfa(String code) async {
    final pending = pendingMfa;
    final client = _client;
    if (pending == null || client == null) throw TapoException('Sign in again');
    final type = pending.requestedType;
    if (type == null) throw TapoException('Request a verification code first');
    code = code.trim();
    if (code.isEmpty) throw TapoException('Enter the verification code');
    final result = await client.verifyMfa(pending.baseUrl, pending.username, code, pending.processId, type);
    await _finishLogin(client, pending.baseUrl, result);
  }

  void cancelMfa() {
    pendingMfa = null;
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  Future<void> _finishLogin(TapoCloud client, String baseUrl, Map<String, dynamic> result) async {
    final token = result['token'];
    if (token == null || '$token'.isEmpty) {
      throw TapoException('The cloud did not return a session token');
    }
    client.token = '$token';
    final devices = await client.listCameras(baseUrl);
    // Only the session token is stored; the password never is.
    await _prefs.setString(
      _kSession,
      jsonEncode({
        'base_url': baseUrl,
        'token': '$token',
        'refreshToken': result['refreshToken'],
        'saved_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }),
    );
    pendingMfa = null;
    _setSignedIn(client, baseUrl, devices);
  }

  void _setSignedIn(TapoCloud client, String baseUrl, List<Map<String, dynamic>> devices) {
    if (!identical(_client, client)) _client?.close();
    _client = client;
    _baseUrl = baseUrl;
    cameras = devices.map(Camera.new).toList();
    camerasError = null;
    stage = AuthStage.signedIn;
    notifyListeners();
    for (final camera in cameras) {
      unawaited(refreshCameraState(camera));
    }
  }

  Future<void> logout() async {
    _client?.close();
    _client = null;
    cameras = [];
    pendingMfa = null;
    await _prefs.remove(_kSession);
    // Forget the terminal identity too so the next sign-in asks for MFA.
    await _prefs.remove(_kTerminal);
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  void _handleAuthFailure(Object error) {
    if (error is TapoException && error.isAuthError) {
      unawaited(logout());
    }
  }

  // ------------------------------------------------------------- Cameras --

  Future<void> refreshCameras() async {
    if (demo) return;
    final client = _client;
    if (client == null) return;
    loadingCameras = true;
    camerasError = null;
    notifyListeners();
    try {
      final devices = await client.listCameras(_baseUrl);
      final previous = {for (final c in cameras) c.deviceId: c};
      cameras = devices.map((d) {
        final camera = Camera(d);
        final old = previous[camera.deviceId];
        camera.privacy = old?.privacy;
        camera.ptz = old?.ptz;
        return camera;
      }).toList();
      for (final camera in cameras) {
        unawaited(refreshCameraState(camera, force: true));
      }
    } catch (e) {
      camerasError = e.toString();
      _handleAuthFailure(e);
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  Future<void> refreshCameraState(Camera camera, {bool force = false}) async {
    if (demo) {
      camera.ptz = camera.raw['_ptz'] == true;
      camera.privacy ??= camera.raw['_privacy'] == true;
      notifyListeners();
      return;
    }
    final client = _client;
    if (client == null) return;
    final checked = camera.checkedAt;
    if (!force && checked != null && DateTime.now().difference(checked) < const Duration(seconds: 10)) {
      return;
    }
    camera.checkedAt = DateTime.now();
    try {
      camera.privacy = await client.getPrivacyMode(_baseUrl, camera.deviceId);
      camera.stateError = null;
    } catch (e) {
      camera.stateError = e.toString();
      _handleAuthFailure(e);
    }
    try {
      camera.ptz ??= await client.ptzSupported(_baseUrl, camera.deviceId);
    } catch (_) {
      camera.ptz ??= null;
    }
    notifyListeners();
  }

  Future<void> setPrivacy(Camera camera, bool enabled) async {
    if (demo) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      camera.privacy = enabled;
      notifyListeners();
      return;
    }
    final client = _client;
    if (client == null) return;
    camera.privacy = await client.setPrivacyMode(_baseUrl, camera.deviceId, enabled);
    camera.checkedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> move(Camera camera, int x, int y) async {
    if (demo) return Future<void>.delayed(const Duration(milliseconds: 300));
    final client = _client;
    if (client == null) return;
    await client.moveMotor(_baseUrl, camera.deviceId, x, y);
  }

  void setForeground(bool value) {
    if (foreground == value) return;
    foreground = value;
    notifyListeners();
  }

  // ------------------------------------------------------------ Settings --

  Future<void> setLivePreviews(bool value) async {
    livePreviews = value;
    await _prefs.setBool(_kLivePreviews, value);
    notifyListeners();
  }

  Future<void> setPtzStep(int value) async {
    ptzStep = value;
    await _prefs.setInt(_kPtzStep, value);
    notifyListeners();
  }

  Future<void> markGuideSeen() async {
    guideSeen = true;
    await _prefs.setBool(_kGuideSeen, true);
    notifyListeners();
  }

  // ---------------------------------------------------------- Multi-view --

  void _loadGrids() {
    try {
      final raw = jsonDecode(_prefs.getString(_kGrids) ?? '[]') as List;
      savedGrids = [for (final g in raw) GridPreset.fromJson(Map<String, dynamic>.from(g as Map))];
    } catch (_) {
      savedGrids = [];
    }
    activeGridId = _prefs.getString(_kActiveGrid) ?? GridPreset.allCamerasId;
    favoriteGridId = _prefs.getString(_kFavoriteGrid);
  }

  Future<void> _saveGrids() =>
      _prefs.setString(_kGrids, jsonEncode([for (final g in savedGrids) g.toJson()]));

  /// Built-in grid showing every camera (first nine) in a fitting layout.
  GridPreset get allCamerasGrid {
    final layout = GridLayout.fitting(cameras.length);
    return GridPreset(
      id: GridPreset.allCamerasId,
      name: 'All cameras',
      layout: layout,
      slots: [for (final c in cameras.take(layout.slots)) c.deviceId],
    );
  }

  /// All grids in switching order: "All cameras" first, then saved ones.
  List<GridPreset> get grids => [allCamerasGrid, ...savedGrids];

  GridPreset gridById(String id) => grids.firstWhere((g) => g.id == id, orElse: () => allCamerasGrid);

  Camera? cameraById(String? deviceId) {
    if (deviceId == null) return null;
    for (final c in cameras) {
      if (c.deviceId == deviceId) return c;
    }
    return null;
  }

  int cameraIndex(String deviceId) => cameras.indexWhere((c) => c.deviceId == deviceId);

  GridPreset? get favoriteGrid {
    final id = favoriteGridId;
    if (id == null) return null;
    for (final g in grids) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Pins [id] to the home page, or unpins with null.
  Future<void> setFavoriteGrid(String? id) async {
    favoriteGridId = id;
    if (id == null) {
      await _prefs.remove(_kFavoriteGrid);
    } else {
      await _prefs.setString(_kFavoriteGrid, id);
    }
    notifyListeners();
  }

  Future<void> setActiveGrid(String id) async {
    activeGridId = id;
    await _prefs.setString(_kActiveGrid, id);
    notifyListeners();
  }

  /// Inserts or replaces a saved grid; returns the stored preset.
  Future<GridPreset> saveGrid(GridPreset grid) async {
    final stored = grid.id.isEmpty
        ? GridPreset(
            id: 'g${DateTime.now().millisecondsSinceEpoch}',
            name: grid.name,
            layout: grid.layout,
            slots: grid.slots,
          )
        : grid;
    final i = savedGrids.indexWhere((g) => g.id == stored.id);
    if (i >= 0) {
      savedGrids[i] = stored;
    } else {
      savedGrids.add(stored);
    }
    await _saveGrids();
    notifyListeners();
    return stored;
  }

  Future<void> deleteGrid(String id) async {
    savedGrids.removeWhere((g) => g.id == id);
    if (favoriteGridId == id) {
      favoriteGridId = null;
      await _prefs.remove(_kFavoriteGrid);
    }
    if (activeGridId == id) {
      activeGridId = GridPreset.allCamerasId;
      await _prefs.setString(_kActiveGrid, activeGridId);
    }
    await _saveGrids();
    notifyListeners();
  }

  String get regionHost => Uri.tryParse(_baseUrl)?.host ?? _baseUrl;
}
