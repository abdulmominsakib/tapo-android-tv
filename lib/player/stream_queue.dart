import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Starts camera streams one at a time.
///
/// Opening several cloud relays and decoders at once makes slower TVs stutter,
/// so each stream waits for a slot; the slot is handed on when the stream
/// shows its first frame, fails, goes away, or after [slotTimeout]. A slow
/// camera then keeps connecting alongside the others instead of blocking
/// them.
class StreamQueue {
  StreamQueue._();
  static final instance = StreamQueue._();

  /// How many streams may be connecting at the same moment.
  static const maxStarting = 1;
  static const slotTimeout = Duration(seconds: 5);

  final _waiting = <StreamTicket>[];
  final _starting = <StreamTicket>{};

  StreamTicket request() {
    final ticket = StreamTicket._(this);
    _waiting.add(ticket);
    _pump();
    return ticket;
  }

  void _release(StreamTicket ticket) {
    _waiting.remove(ticket);
    ticket._timer?.cancel();
    if (_starting.remove(ticket)) _pump();
  }

  void _pump() {
    while (_starting.length < maxStarting && _waiting.isNotEmpty) {
      final ticket = _waiting.removeAt(0);
      _starting.add(ticket);
      ticket._timer = Timer(slotTimeout, () => _release(ticket));
      ticket._ready.complete();
    }
  }
}

class StreamTicket {
  StreamTicket._(this._queue);
  final StreamQueue _queue;
  final _ready = Completer<void>();
  Timer? _timer;

  /// Completes when this stream may start connecting.
  Future<void> get ready => _ready.future;

  /// Hands the slot to the next stream (safe to call more than once).
  void release() => _queue._release(this);
}

/// Last captured frame of each camera, saved by the native player
/// (LivePlayer.kt) in the app cache. Shown instantly while streams connect.
class Snapshots extends ChangeNotifier {
  Snapshots._();
  static final instance = Snapshots._();

  String? _dir;
  final _versions = <String, int>{};

  Future<void> init() async {
    try {
      _dir ??= await const MethodChannel('topo/player').invokeMethod<String>('snapshotDir');
    } catch (_) {
      // No snapshots (e.g. in tests); everything still works without them.
    }
  }

  /// Where the player should write this camera's snapshot.
  String? pathFor(String deviceId) {
    final dir = _dir;
    if (dir == null) return null;
    return '$dir/${deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg';
  }

  /// The saved snapshot, if there is one.
  File? fileFor(String deviceId) {
    final path = pathFor(deviceId);
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  int version(String deviceId) => _versions[deviceId] ?? 0;

  /// Called when the player wrote a new snapshot.
  void updated(String deviceId) {
    final path = pathFor(deviceId);
    if (path != null) FileImage(File(path)).evict();
    _versions[deviceId] = version(deviceId) + 1;
    notifyListeners();
  }
}

/// Shows a camera's last captured frame, or [fallback] when there is none.
class SnapshotView extends StatelessWidget {
  const SnapshotView({super.key, required this.deviceId, required this.fallback, this.fit = BoxFit.cover});
  final String deviceId;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Snapshots.instance,
      builder: (context, _) {
        final file = Snapshots.instance.fileFor(deviceId);
        if (file == null) return fallback;
        return Image.file(
          file,
          key: ValueKey('${file.path}#${Snapshots.instance.version(deviceId)}'),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

/// "08:27" or "Yesterday 21:04" for when a snapshot was taken.
String? snapshotTime(String deviceId) {
  final file = Snapshots.instance.fileFor(deviceId);
  if (file == null) return null;
  final t = file.lastModifiedSync();
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return hm;
  if (today.difference(day).inDays == 1) return 'Yesterday $hm';
  return '${t.day}/${t.month} $hm';
}
