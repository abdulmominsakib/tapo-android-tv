import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/tapo_cloud.dart';
import '../main.dart';
import '../player/live_player.dart';
import '../state/app_state.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'home_screen.dart' show digitIndex;

final _nextKeys = {
  LogicalKeyboardKey.channelUp,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.mediaTrackNext,
  LogicalKeyboardKey.mediaFastForward,
};
final _prevKeys = {
  LogicalKeyboardKey.channelDown,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.mediaTrackPrevious,
  LogicalKeyboardKey.mediaRewind,
};

/// Full-screen live view: arrows pan/tilt, OK shows the controls,
/// channel keys switch cameras, Back hides controls then exits.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.initialIndex});
  final int initialIndex;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late int _index = widget.initialIndex;
  final _rootFocus = FocusNode(debugLabel: 'live-root');
  final _firstControlFocus = FocusNode(debugLabel: 'live-first-control');
  int _reconnects = 0;

  bool _hud = false;
  bool _showTitle = true;
  Timer? _hudTimer;
  Timer? _titleTimer;
  LiveState _liveState = LiveState.connecting;
  bool _privacyBusy = false;

  // Pan/tilt: one request in flight; while busy remember only the latest
  // direction so holding an arrow moves continuously without overshooting.
  bool _moving = false;
  (int, int)? _pendingMove;
  (int, int)? _lastDirection;
  Timer? _arrowTimer;
  DateTime _lastErrorToast = DateTime(2000);

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.live;
    _flashTitle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rootFocus.requestFocus();
      _refreshState();
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _titleTimer?.cancel();
    _arrowTimer?.cancel();
    _rootFocus.dispose();
    _firstControlFocus.dispose();
    super.dispose();
  }

  AppState get _app => AppScope.read(context);
  Camera? get _camera {
    final cams = _app.cameras;
    if (cams.isEmpty) return null;
    return cams[_index.clamp(0, cams.length - 1)];
  }

  void _refreshState() {
    final camera = _camera;
    if (camera != null) _app.refreshCameraState(camera);
  }

  void _flashTitle() {
    setState(() => _showTitle = true);
    _titleTimer?.cancel();
    _titleTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showTitle = false);
    });
  }

  void _showHud() {
    if (!_hud) {
      setState(() => _hud = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstControlFocus.requestFocus());
    }
    _bumpHud();
  }

  void _bumpHud() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 8), _hideHud);
  }

  void _hideHud() {
    _hudTimer?.cancel();
    if (!mounted || !_hud) return;
    setState(() => _hud = false);
    _rootFocus.requestFocus();
  }

  void _switchCamera(int delta, {int? absolute}) {
    final count = _app.cameras.length;
    if (count == 0) return;
    final next = absolute ?? (_index + delta) % count;
    if (next < 0 || next >= count) return;
    if (next == _index) {
      _flashTitle();
      return;
    }
    setState(() {
      _index = next;
      _liveState = LiveState.connecting;
      _pendingMove = null;
    });
    _flashTitle();
    _refreshState();
    if (!_hud) _rootFocus.requestFocus();
  }

  Future<void> _move(int dx, int dy) async {
    final camera = _camera;
    if (camera == null) return;
    setState(() => _lastDirection = (dx.sign, dy.sign));
    _arrowTimer?.cancel();
    _arrowTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _lastDirection = null);
    });
    if (_moving) {
      _pendingMove = (dx, dy);
      return;
    }
    _moving = true;
    try {
      await _app.move(camera, dx, dy);
    } on TapoException catch (e) {
      final now = DateTime.now();
      if (mounted && now.difference(_lastErrorToast) > const Duration(seconds: 2)) {
        _lastErrorToast = now;
        showToast(context, e.message, error: true, icon: Icons.block_rounded);
      }
      _pendingMove = null;
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
      _pendingMove = null;
    } finally {
      _moving = false;
    }
    final pending = _pendingMove;
    _pendingMove = null;
    if (pending != null && mounted) await _move(pending.$1, pending.$2);
  }

  Future<void> _togglePrivacy() async {
    final camera = _camera;
    if (camera == null || _privacyBusy) return;
    final enable = !(camera.privacy ?? false);
    setState(() => _privacyBusy = true);
    try {
      await _app.setPrivacy(camera, enable);
      if (mounted) showToast(context, enable ? 'Privacy mode is on' : 'Privacy mode is off');
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent;

    if (_nextKeys.contains(key)) {
      if (isDown) _switchCamera(1);
      return KeyEventResult.handled;
    }
    if (_prevKeys.contains(key)) {
      if (isDown) _switchCamera(-1);
      return KeyEventResult.handled;
    }
    final digit = digitIndex(key);
    if (digit != null) {
      if (isDown) _switchCamera(0, absolute: digit);
      return KeyEventResult.handled;
    }

    if (_hud) {
      // Any activity keeps the controls on screen.
      _bumpHud();
      return KeyEventResult.ignored;
    }

    // Controls hidden: this node has focus, so the D-pad drives the camera.
    final camera = _camera;
    final canPtz = camera?.ptz == true && camera?.privacy != true;
    final step = _app.ptzStep;
    if (selectKeys.contains(key)) {
      if (isDown) camera?.privacy == true ? _togglePrivacy() : _showHud();
      return KeyEventResult.handled;
    }
    final dir = switch (key) {
      LogicalKeyboardKey.arrowLeft => (-1, 0),
      LogicalKeyboardKey.arrowRight => (1, 0),
      LogicalKeyboardKey.arrowUp => (0, 1),
      LogicalKeyboardKey.arrowDown => (0, -1),
      _ => null,
    };
    if (dir == null) return KeyEventResult.ignored;
    if (canPtz) {
      _move(dir.$1 * step, dir.$2 * step);
    } else if (isDown && dir.$1 != 0) {
      _switchCamera(dir.$1);
    } else if (isDown) {
      _showHud();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final camera = _camera;
    if (camera == null) {
      return const Scaffold(body: Center(child: Text('No camera')));
    }
    final privacy = camera.privacy == true;
    final canPtz = camera.ptz == true && !privacy;

    return PopScope(
      canPop: !_hud,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hideHud();
      },
      child: Scaffold(
        backgroundColor: TopoColors.media,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (privacy)
                _PrivacyCover(busy: _privacyBusy, onTurnOff: _togglePrivacy)
              else if (app.foreground)
                LiveVideo(
                  key: ValueKey('live-${camera.deviceId}-$_reconnects'),
                  app: app,
                  camera: camera,
                  onStateChanged: (s) => setState(() => _liveState = s),
                ),
              // Directional feedback for pan & tilt.
              if (_lastDirection != null) _ArrowFlash(direction: _lastDirection!),
              // Top bar.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: (_hud || _showTitle) ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: _TopBar(
                      camera: camera,
                      index: _index,
                      count: app.cameras.length,
                      live: !privacy && _liveState == LiveState.playing,
                    ),
                  ),
                ),
              ),
              // Bottom controls.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ExcludeFocus(
                  excluding: !_hud,
                  child: AnimatedSlide(
                    offset: _hud ? Offset.zero : const Offset(0, 0.4),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _hud ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _Controls(
                        camera: camera,
                        firstFocus: _firstControlFocus,
                        hasMultiple: app.cameras.length > 1,
                        privacyBusy: _privacyBusy,
                        step: app.ptzStep,
                        canPtz: canPtz,
                        onPrev: () => _switchCamera(-1),
                        onNext: () => _switchCamera(1),
                        onPrivacy: _togglePrivacy,
                        onStep: () {
                          const steps = [5, 10, 20];
                          app.setPtzStep(steps[(steps.indexOf(app.ptzStep) + 1) % steps.length]);
                        },
                        onReconnect: () {
                          // A new key recreates the player and its relay.
                          setState(() {
                            _reconnects++;
                            _liveState = LiveState.connecting;
                          });
                          app.refreshCameraState(camera, force: true);
                        },
                        onGuide: () => showRemoteGuide(context, section: GuideSection.live),
                        onHide: _hideHud,
                      ),
                    ),
                  ),
                ),
              ),
              // Persistent hint while the controls are hidden.
              if (!_hud && !privacy)
                Positioned(
                  right: 40,
                  bottom: 26,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showTitle ? 1 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      child: _HintChip(canPtz: canPtz, multiple: app.cameras.length > 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.camera, required this.index, required this.count, required this.live});
  final Camera camera;
  final int index;
  final int count;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6101820), Color(0x00101820)],
        ),
      ),
      child: Row(
        children: [
          if (live) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: TopoColors.error, borderRadius: BorderRadius.circular(6)),
              child: const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.white),
                  SizedBox(width: 5),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8)),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    camera.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Text(camera.model, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              ],
            ),
          ),
          if (count > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text('Camera ${index + 1} of $count', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.camera,
    required this.firstFocus,
    required this.hasMultiple,
    required this.privacyBusy,
    required this.step,
    required this.canPtz,
    required this.onPrev,
    required this.onNext,
    required this.onPrivacy,
    required this.onStep,
    required this.onReconnect,
    required this.onGuide,
    required this.onHide,
  });

  final Camera camera;
  final FocusNode firstFocus;
  final bool hasMultiple;
  final bool privacyBusy;
  final int step;
  final bool canPtz;
  final VoidCallback onPrev, onNext, onPrivacy, onStep, onReconnect, onGuide, onHide;

  @override
  Widget build(BuildContext context) {
    final privacy = camera.privacy == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 60, 48, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2101820), Color(0x00101820)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusTraversalGroup(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasMultiple) ...[
                  TvButton(label: 'Previous', icon: Icons.skip_previous_rounded, onMedia: true, onPressed: onPrev),
                  const SizedBox(width: 10),
                ],
                TvButton(
                  label: privacy ? 'Turn privacy off' : 'Turn privacy on',
                  icon: privacy ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  onMedia: true,
                  focusNode: firstFocus,
                  busy: privacyBusy || camera.privacy == null,
                  style: privacy ? TvButtonStyle.primary : TvButtonStyle.secondary,
                  onPressed: onPrivacy,
                ),
                const SizedBox(width: 10),
                if (camera.ptz == true) ...[
                  TvButton(label: 'Step $step°', icon: Icons.straighten_rounded, onMedia: true, onPressed: onStep),
                  const SizedBox(width: 10),
                  TvButton(label: 'Pan & tilt', icon: Icons.open_with_rounded, onMedia: true, onPressed: onHide),
                  const SizedBox(width: 10),
                ],
                TvButton(label: 'Reconnect', icon: Icons.refresh_rounded, onMedia: true, onPressed: onReconnect),
                const SizedBox(width: 10),
                TvButton(label: '', icon: Icons.help_outline_rounded, onMedia: true, onPressed: onGuide),
                if (hasMultiple) ...[
                  const SizedBox(width: 10),
                  TvButton(label: 'Next', icon: Icons.skip_next_rounded, onMedia: true, onPressed: onNext),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          HintBar(onMedia: true, [
            if (canPtz) (const KeyCap('', icon: Icons.arrow_back_rounded, onMedia: true), 'Hide controls, then use arrows to pan & tilt'),
            if (!canPtz) (const KeyCap('', icon: Icons.arrow_back_rounded, onMedia: true), 'Hide controls'),
            if (hasMultiple) (const KeyCap('CH ±', onMedia: true), 'Switch camera'),
          ]),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.canPtz, required this.multiple});
  final bool canPtz;
  final bool multiple;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: TopoColors.media.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(TopoRadius.md)),
      child: HintBar(onMedia: true, [
        if (canPtz) (const KeyCap('', icon: Icons.open_with_rounded, onMedia: true), 'Pan & tilt'),
        if (!canPtz && multiple) (const KeyCap('', icon: Icons.swap_horiz_rounded, onMedia: true), 'Switch camera'),
        (const KeyCap('OK', onMedia: true), 'Controls'),
      ]),
    );
  }
}

class _ArrowFlash extends StatelessWidget {
  const _ArrowFlash({required this.direction});
  final (int, int) direction;

  @override
  Widget build(BuildContext context) {
    final (dx, dy) = direction;
    final align = Alignment(dx.toDouble() * 0.92, -dy.toDouble() * 0.85);
    final icon = switch (direction) {
      (-1, 0) => Icons.chevron_left_rounded,
      (1, 0) => Icons.chevron_right_rounded,
      (0, 1) => Icons.expand_less_rounded,
      _ => Icons.expand_more_rounded,
    };
    return IgnorePointer(
      child: Align(
        alignment: align,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: TopoColors.media.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(color: TopoColors.onMedia, width: 2),
          ),
          child: Icon(icon, color: TopoColors.onMedia, size: 52),
        ),
      ),
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({required this.busy, required this.onTurnOff});
  final bool busy;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TopoColors.media,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: TopoColors.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.visibility_off_rounded, size: 46, color: TopoColors.onMedia),
          ),
          const SizedBox(height: 20),
          const Text('Privacy mode is on', style: TextStyle(color: TopoColors.onMedia, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'The camera lens is covered and no video is recorded.',
            style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 18),
          ),
          const SizedBox(height: 24),
          // The screen itself handles OK (see _onKey); this is the visual cue
          // and a touch target.
          GestureDetector(
            onTap: onTurnOff,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              decoration: BoxDecoration(
                color: TopoColors.primaryAction,
                borderRadius: BorderRadius.circular(TopoRadius.full),
                // White separator + blue outline: this control is the
                // screen's focused action (OK triggers it).
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: TopoColors.onPrimary),
                    )
                  else
                    const KeyCap('OK', onMedia: true),
                  const SizedBox(width: 10),
                  Text(
                    busy ? 'Turning off…' : 'Turn off privacy mode',
                    style: const TextStyle(color: TopoColors.onPrimary, fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
