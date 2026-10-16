import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../ui/theme.dart';
import 'stream_queue.dart';

enum LiveState { connecting, playing, retrying, failed }

/// Routes native player events (see LivePlayer.kt) to their view.
class _PlayerEvents {
  _PlayerEvents._() {
    const MethodChannel('topo/player').setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      _listeners[(args['id'] as num).toInt()]?.call(args);
    });
  }
  static final instance = _PlayerEvents._();
  final _listeners = <int, void Function(Map<String, dynamic>)>{};
}

/// The native ExoPlayer view, embedded with hybrid composition. One view is
/// one stream session: a new key means a new connection.
class _NativeVideo extends StatelessWidget {
  const _NativeVideo({super.key, required this.url, required this.snapshotPath, required this.onEvent});
  final String url;
  final String? snapshotPath;
  final void Function(Map<String, dynamic>) onEvent;

  static const _viewType = 'topo/live-video';

  @override
  Widget build(BuildContext context) {
    // The native view never takes focus; keep it out of D-pad traversal.
    return ExcludeFocus(
      child: PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          _PlayerEvents.instance._listeners[params.id] = onEvent;
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: {'url': url, 'snapshot': snapshotPath},
            creationParamsCodec: const StandardMessageCodec(),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
          return controller;
        },
      ),
    );
  }
}

/// Live camera video with connection state, auto-retry and error display.
class LiveVideo extends StatefulWidget {
  const LiveVideo({
    super.key,
    required this.app,
    required this.camera,
    this.compact = false,
    this.queued = true,
    this.onStateChanged,
  });

  final AppState app;
  final Camera camera;

  /// Compact = grid thumbnail: smaller texts, no long error explanations.
  final bool compact;

  /// Wait for a [StreamQueue] slot before connecting (lists and grids).
  /// The full-screen live view starts at once.
  final bool queued;
  final ValueChanged<LiveState>? onStateChanged;

  @override
  State<LiveVideo> createState() => LiveVideoState();
}

class LiveVideoState extends State<LiveVideo> {
  /// Increments for every connection attempt; null while disconnected.
  int? _session;
  int _sessions = 0;
  LiveState _state = LiveState.connecting;
  String? _error;
  double _aspect = 16 / 9;
  int _failures = 0;
  Timer? _retryTimer;
  Timer? _stallTimer;
  bool _disposed = false;
  StreamTicket? _ticket;

  /// True while waiting for this stream's turn in the [StreamQueue].
  bool _waiting = false;

  LiveState get state => _state;

  @override
  void initState() {
    super.initState();
    _waiting = widget.queued;
    _start();
  }

  @override
  void didUpdateWidget(LiveVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera.deviceId != widget.camera.deviceId) restart(resetFailures: true);
  }

  void _setState(LiveState s, {String? error}) {
    if (_disposed) return;
    setState(() {
      _state = s;
      _error = error;
    });
    widget.onStateChanged?.call(s);
  }

  Future<void> _start() async {
    _stallTimer?.cancel();
    _releaseTicket();
    if (widget.queued) {
      final ticket = _ticket = StreamQueue.instance.request();
      // initState sets _waiting itself; setState is only for restarts.
      if (!_waiting) setState(() => _waiting = true);
      await ticket.ready;
      // Superseded by a restart, or the view went away while waiting.
      if (_disposed || !identical(_ticket, ticket)) {
        ticket.release();
        return;
      }
      setState(() => _waiting = false);
    }
    // If no frame arrives in time the relay is half-open; start over.
    _stallTimer = Timer(const Duration(seconds: 35), () {
      if (_state != LiveState.playing) _onFailure('The camera did not send video in time');
    });
    if (!_disposed) setState(() => _session = ++_sessions);
  }

  void _releaseTicket() {
    _ticket?.release();
    _ticket = null;
  }

  void _onEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    switch (event['state']) {
      case 'firstFrame':
        _releaseTicket();
        _failures = 0;
        _stallTimer?.cancel();
        _setState(LiveState.playing);
      case 'size':
        final w = (event['width'] as num).toDouble(), h = (event['height'] as num).toDouble();
        if (w > 0 && h > 0 && mounted) setState(() => _aspect = w / h);
      case 'snapshot':
        Snapshots.instance.updated(widget.camera.deviceId);
      case 'error':
        final relayError = widget.app.relay.lastErrors[widget.camera.deviceId];
        _onFailure(relayError ?? '${event['message'] ?? 'Stream interrupted'}');
    }
  }

  void _onFailure(String message) {
    if (_disposed) return;
    _stallTimer?.cancel();
    _releaseTicket();
    _releaseTexture();
    _failures++;
    if (_failures > 3) {
      _setState(LiveState.failed, error: message);
      return;
    }
    _setState(LiveState.retrying, error: message);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 2 * _failures), () {
      if (!_disposed) {
        _setState(LiveState.connecting);
        _start();
      }
    });
  }

  void _releaseTexture() {
    if (_session != null && mounted) setState(() => _session = null);
  }

  /// Reconnect from scratch (e.g. after privacy mode is turned off).
  void restart({bool resetFailures = true}) {
    _retryTimer?.cancel();
    _releaseTexture();
    if (resetFailures) _failures = 0;
    _setState(LiveState.connecting);
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _releaseTicket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return ColoredBox(
      color: TopoColors.media,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (session != null)
            Center(
              child: AspectRatio(
                aspectRatio: _aspect,
                child: _NativeVideo(
                  key: ValueKey(session),
                  url: widget.app.streamUrl(widget.camera),
                  snapshotPath: Snapshots.instance.pathFor(widget.camera.deviceId),
                  onEvent: _onEvent,
                ),
              ),
            ),
          if (_state != LiveState.playing) _overlay(context),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final compact = widget.compact;
    final failed = _state == LiveState.failed;
    final text = switch (_state) {
      _ when _waiting => compact ? 'Waiting' : 'Waiting for other cameras to load…',
      LiveState.connecting => compact ? 'Connecting' : 'Connecting to camera through Tapo cloud…',
      LiveState.retrying => 'Reconnecting…',
      LiveState.failed => compact ? 'Unavailable' : 'Could not load the live view',
      LiveState.playing => '',
    };
    const soft = Color(0xFFC9D3DC);
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (failed)
          Icon(Icons.videocam_off_rounded, color: soft, size: compact ? 26 : 48)
        else
          SizedBox(
            width: compact ? 22 : 36,
            height: compact ? 22 : 36,
            child: const CircularProgressIndicator(strokeWidth: 3, color: TopoColors.onMedia),
          ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: TopoColors.onMedia, fontSize: compact ? 16 : 22, fontWeight: FontWeight.w600),
        ),
        if (!compact && _error != null && _state != LiveState.connecting) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: soft, fontSize: 16),
            ),
          ),
        ],
      ],
    );
    final taken = snapshotTime(widget.camera.deviceId);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: TopoColors.media,
          child: SnapshotView(
            deviceId: widget.camera.deviceId,
            fit: compact ? BoxFit.cover : BoxFit.contain,
            fallback: const SizedBox.expand(),
          ),
        ),
        if (compact && taken != null)
          // The last frame stays clear; a small chip says what's happening.
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: TopoColors.media.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(TopoRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed)
                    const Icon(Icons.videocam_off_rounded, size: 14, color: soft)
                  else
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: TopoColors.onMedia),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    failed ? 'Unavailable · $taken' : text,
                    style: const TextStyle(color: TopoColors.onMedia, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            color: TopoColors.media.withValues(alpha: taken != null ? 0.55 : 0.85),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: taken == null
                ? status
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    decoration: BoxDecoration(
                      color: TopoColors.media.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(TopoRadius.lg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        status,
                        const SizedBox(height: 8),
                        Text('Showing the last picture from $taken', style: const TextStyle(color: soft, fontSize: 15)),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}
