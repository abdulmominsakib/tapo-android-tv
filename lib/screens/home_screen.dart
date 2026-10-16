import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../main.dart';
import '../player/live_player.dart';
import '../player/stream_queue.dart';
import '../state/app_state.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'live_screen.dart';
import 'multiview_screen.dart';
import 'settings_screen.dart';

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadKeys = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// Maps number keys 1–9 to a zero-based index, or null.
int? digitIndex(LogicalKeyboardKey key) {
  final i = _digitKeys.indexOf(key);
  if (i >= 0) return i;
  final n = _numpadKeys.indexOf(key);
  return n >= 0 ? n : null;
}

/// Opens the full-screen live view for camera [index].
Future<void> openLive(BuildContext context, int index) async {
  final app = AppScope.read(context);
  if (index < 0 || index >= app.cameras.length) return;
  final previous = guideSection.value;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: TopoMotion.navigation,
      pageBuilder: (_, _, _) => LiveScreen(initialIndex: index),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
  guideSection.value = previous;
}

enum HomeTab { cameras, multiview, settings }

/// Signed-in shell: a persistent top destination row and the active tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.cameras;
  bool _guideChecked = false;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.home;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuide());
  }

  Future<void> _maybeShowGuide() async {
    if (_guideChecked || !mounted) return;
    _guideChecked = true;
    final app = AppScope.read(context);
    if (!app.guideSeen) {
      await showRemoteGuide(context);
      await app.markGuideSeen();
    }
  }

  void _select(HomeTab tab) {
    setState(() => _tab = tab);
    guideSection.value = switch (tab) {
      HomeTab.cameras => GuideSection.home,
      HomeTab.multiview => GuideSection.multiview,
      HomeTab.settings => GuideSection.basics,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Previews run while this page is visible: a full page on top (live
    // view, a grid) turns tickers off for it, a dialog does not.
    final active = app.foreground && TickerMode.valuesOf(context).enabled;
    return Scaffold(
      body: Padding(
        padding: tvSafePadding.copyWith(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusTraversalGroup(
              child: Row(
                children: [
                  Image.asset('assets/topo.png', width: 40, height: 40, semanticLabel: 'Topo'),
                  const SizedBox(width: TopoSpace.sm),
                  const Text('Topo', style: TopoText.title),
                  const SizedBox(width: TopoSpace.x2),
                  for (final (tab, label, icon) in const [
                    (HomeTab.cameras, 'Cameras', Icons.videocam_rounded),
                    (HomeTab.multiview, 'Multi-view', Icons.grid_view_rounded),
                    (HomeTab.settings, 'Settings', Icons.settings_rounded),
                  ]) ...[
                    _NavItem(label: label, icon: icon, selected: _tab == tab, onSelect: () => _select(tab)),
                    const SizedBox(width: TopoSpace.sm),
                  ],
                  const Spacer(),
                  if (_tab == HomeTab.cameras) ...[
                    TvButton(
                      label: '',
                      semanticLabel: 'Refresh cameras',
                      icon: Icons.refresh_rounded,
                      busy: app.loadingCameras,
                      onPressed: app.refreshCameras,
                    ),
                    const SizedBox(width: TopoSpace.sm),
                  ],
                  TvButton(
                    label: 'Guide',
                    icon: Icons.help_outline_rounded,
                    onPressed: () => showRemoteGuide(context, section: guideSection.value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: TopoSpace.lg),
            Expanded(
              child: FocusTraversalGroup(
                child: AnimatedSwitcher(
                  duration: TopoMotion.navigation,
                  child: switch (_tab) {
                    HomeTab.cameras => CamerasPanel(key: const ValueKey('cameras'), active: active),
                    HomeTab.multiview => const MultiviewPanel(key: ValueKey('multiview')),
                    HomeTab.settings => const SettingsPanel(key: ValueKey('settings')),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top destination. Focus only outlines it; OK switches (no navigation on
/// focus). The active destination keeps its pale-blue surface.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onSelect});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TvFocusable(
        onSelect: onSelect,
        builder: (context, focused) {
          final fg = selected ? TopoColors.primaryPressed : TopoColors.muted;
          return FocusRing(
            focused: focused,
            radius: TopoRadius.full,
            child: AnimatedContainer(
              duration: TopoMotion.focus,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: TopoSpace.xl),
              decoration: BoxDecoration(
                color: selected ? TopoColors.surfaceSelected : TopoColors.surface,
                borderRadius: BorderRadius.circular(TopoRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(width: TopoSpace.sm),
                  Text(label, style: TopoText.label.copyWith(color: fg)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The camera list: one card per camera with a live preview.
class CamerasPanel extends StatefulWidget {
  const CamerasPanel({super.key, required this.active});
  final bool active;

  @override
  State<CamerasPanel> createState() => _CamerasPanelState();
}

class _CamerasPanelState extends State<CamerasPanel> {
  final _videoKeys = <String, GlobalKey<LiveVideoState>>{};

  Future<void> _quickActions(Camera camera, int index) async {
    final app = AppScope.read(context);
    final privacy = camera.privacy;
    final action = await showTvDialog<String>(
      context,
      (context) => TvDialog(
        title: camera.name,
        message: camera.model,
        children: [
          TvTile(
            title: 'Watch live',
            icon: Icons.play_arrow_rounded,
            autofocus: true,
            onSelect: () => Navigator.pop(context, 'live'),
          ),
          const SizedBox(height: TopoSpace.md),
          TvTile(
            title: privacy == true ? 'Turn privacy mode off' : 'Turn privacy mode on',
            subtitle: privacy == null
                ? 'Checking the camera…'
                : privacy
                    ? 'Video starts again'
                    : 'The lens is covered and video stops',
            icon: privacy == true ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            onSelect: privacy == null ? null : () => Navigator.pop(context, 'privacy'),
          ),
          const SizedBox(height: TopoSpace.md),
          TvTile(
            title: 'Reconnect preview',
            icon: Icons.refresh_rounded,
            onSelect: () => Navigator.pop(context, 'reconnect'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'live':
        await openLive(context, index);
      case 'reconnect':
        _videoKeys[camera.deviceId]?.currentState?.restart();
        await app.refreshCameraState(camera, force: true);
      case 'privacy':
        final enable = !(privacy ?? false);
        showToast(context, enable ? 'Turning privacy mode on…' : 'Turning privacy mode off…', icon: Icons.hourglass_top_rounded);
        try {
          await app.setPrivacy(camera, enable);
          if (mounted) showToast(context, enable ? 'Privacy mode is on' : 'Privacy mode is off');
        } catch (e) {
          if (mounted) showToast(context, e.toString(), error: true);
        }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final index = digitIndex(event.logicalKey);
    if (index == null) return KeyEventResult.ignored;
    openLive(context, index);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cameras = app.cameras;
    final showVideo = app.livePreviews && widget.active;
    if (cameras.isEmpty) return _Empty(app: app);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomScrollView(
              // Build only what is on (or next to) the screen: cards scrolled
              // away stop streaming and show their last picture instead.
              scrollCacheExtent: const ScrollCacheExtent.pixels(300),
              slivers: [
                SliverPadding(
                  // Room for the focus outline and scale; never clip focus.
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, TopoSpace.x2),
                  sliver: SliverToBoxAdapter(child: FavoriteGridCard(app: app, autofocus: true)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: TopoSpace.cardGap,
                      crossAxisSpacing: TopoSpace.cardGap,
                      childAspectRatio: 1.25,
                    ),
                    itemCount: cameras.length,
                    itemBuilder: (context, i) {
                      final camera = cameras[i];
                      return _CameraCard(
                        key: ValueKey(camera.deviceId),
                        app: app,
                        camera: camera,
                        number: i + 1,
                        showVideo: showVideo,
                        videoKey: _videoKeys.putIfAbsent(camera.deviceId, GlobalKey<LiveVideoState>.new),
                        onSelect: () => openLive(context, i),
                        onLongSelect: () => _quickActions(camera, i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TopoSpace.sm),
          HintBar([
            (const KeyCap('OK'), 'Watch live'),
            (const KeyCap('Hold OK'), 'Quick actions'),
            (const KeyCap('1–9'), 'Jump to camera'),
            (const KeyCap('', icon: Icons.menu_rounded), 'Remote guide'),
          ]),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final error = app.camerasError;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(gradient: featuredGradient, shape: BoxShape.circle, boxShadow: featuredShadow),
            child: Icon(error != null ? Icons.cloud_off_rounded : Icons.videocam_off_rounded, size: 44, color: TopoColors.primary),
          ),
          const SizedBox(height: TopoSpace.xl),
          Text(error != null ? 'Could not load your cameras' : 'No cameras on this account', style: TopoText.headline),
          const SizedBox(height: TopoSpace.sm),
          Text(
            error ?? 'Add cameras with the Tapo app on your phone, then refresh.',
            textAlign: TextAlign.center,
            style: TopoText.body.copyWith(color: error != null ? TopoColors.error : TopoColors.muted),
          ),
          const SizedBox(height: TopoSpace.x2),
          TvButton(
            label: error != null ? 'Try again' : 'Refresh',
            icon: Icons.refresh_rounded,
            style: TvButtonStyle.primary,
            autofocus: true,
            busy: app.loadingCameras,
            onPressed: app.refreshCameras,
          ),
        ],
      ),
    );
  }
}

/// Camera status as text plus icon (never color alone).
(String, IconData, Color) cameraStatus(Camera camera, LiveState? live, {required bool previews}) {
  if (camera.privacy == true) return ('Privacy on', Icons.visibility_off_rounded, TopoColors.muted);
  if (!previews) {
    final taken = snapshotTime(camera.deviceId);
    return (taken == null ? 'Ready' : 'Last seen $taken', Icons.photo_camera_rounded, TopoColors.muted);
  }
  return switch (live) {
    LiveState.playing => ('Live', Icons.circle, TopoColors.success),
    LiveState.failed => ('Not responding', Icons.error_outline_rounded, TopoColors.error),
    LiveState.retrying => ('Reconnecting', Icons.sync_rounded, TopoColors.muted),
    _ => ('Connecting', Icons.sync_rounded, TopoColors.muted),
  };
}

class _CameraCard extends StatefulWidget {
  const _CameraCard({
    super.key,
    required this.app,
    required this.camera,
    required this.number,
    required this.showVideo,
    required this.videoKey,
    required this.onSelect,
    required this.onLongSelect,
  });

  final AppState app;
  final Camera camera;
  final int number;
  final bool showVideo;
  final GlobalKey<LiveVideoState> videoKey;
  final VoidCallback onSelect;
  final VoidCallback onLongSelect;

  @override
  State<_CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<_CameraCard> {
  LiveState? _live;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    final privacy = camera.privacy == true;
    final (status, statusIcon, statusColor) = cameraStatus(camera, _live, previews: widget.showVideo);
    return Semantics(
      button: true,
      label: '${widget.number}. ${camera.name}, $status',
      child: TvCard(
        onSelect: () {
          final video = widget.videoKey.currentState;
          if (video != null && video.failed) {
            video.retry();
          } else {
            widget.onSelect();
          }
        },
        onLongSelect: widget.onLongSelect,
        padding: const EdgeInsets.all(TopoSpace.md),
        child: (focused) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TopoRadius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (privacy)
                      const _Placeholder(icon: Icons.visibility_off_rounded, text: 'Privacy mode on')
                    else if (widget.showVideo)
                      LiveVideo(
                        key: widget.videoKey,
                        app: widget.app,
                        camera: camera,
                        compact: true,
                        onStateChanged: (s) => setState(() => _live = s),
                      )
                    else
                      SnapshotView(
                        deviceId: camera.deviceId,
                        fallback: const _Placeholder(icon: Icons.videocam_rounded, text: 'Press OK to watch'),
                      ),
                    Positioned(
                      left: TopoSpace.sm,
                      top: TopoSpace.sm,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: TopoColors.surface, borderRadius: BorderRadius.circular(TopoRadius.sm)),
                        child: Text(
                          '${widget.number}',
                          style: const TextStyle(color: TopoColors.primaryPressed, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: TopoSpace.sm),
            Text(camera.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TopoText.label),
            Row(
              children: [
                Icon(statusIcon, size: status == 'Live' ? 10 : 16, color: statusColor),
                const SizedBox(width: 6),
                Text(status, style: TopoText.caption.copyWith(color: statusColor == TopoColors.muted ? TopoColors.muted : statusColor)),
                Expanded(
                  child: Text(
                    [' · ${camera.model}', if (camera.ptz == true) 'Pan & tilt'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TopoText.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: featuredGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: TopoColors.primary, size: 32),
            const SizedBox(height: TopoSpace.sm),
            Text(text, style: TopoText.caption),
          ],
        ),
      );
}

/// Picks the grid pinned to the home page. Returns the chosen id, '' to
/// unpin, or null when cancelled.
Future<void> chooseFavoriteGrid(BuildContext context) async {
  final app = AppScope.read(context);
  final current = app.favoriteGridId;
  final picked = await showTvDialog<String>(
    context,
    (context) => TvDialog(
      title: 'Favourite grid',
      message: 'Pinned at the top of the home page for one-press access.',
      children: [
        for (final grid in app.grids) ...[
          TvTile(
            title: grid.name,
            subtitle: '${grid.cameraCount} cameras · ${grid.layout.label}',
            icon: Icons.grid_view_rounded,
            selected: grid.id == current,
            autofocus: grid.id == current || (current == null && grid.isAuto),
            onSelect: () => Navigator.pop(context, grid.id),
          ),
          const SizedBox(height: TopoSpace.md),
        ],
        if (current != null)
          TvTile(
            title: 'Remove from home',
            icon: Icons.star_outline_rounded,
            danger: true,
            onSelect: () => Navigator.pop(context, ''),
          ),
      ],
    ),
  );
  if (picked == null) return;
  await app.setFavoriteGrid(picked.isEmpty ? null : picked);
  if (context.mounted) {
    showToast(context, picked.isEmpty ? 'Removed from home' : 'Pinned to home', icon: Icons.star_rounded);
  }
}

/// Home-page card for the favourite grid: last pictures of its cameras
/// (no live streams, so the home page stays light), OK opens the grid.
class FavoriteGridCard extends StatelessWidget {
  const FavoriteGridCard({super.key, required this.app, this.autofocus = false});
  final AppState app;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final grid = app.favoriteGrid;
    if (grid == null) {
      return Semantics(
        button: true,
        label: 'Add a favourite grid',
        child: TvCard(
          autofocus: autofocus,
          onSelect: () => chooseFavoriteGrid(context),
          padding: const EdgeInsets.symmetric(horizontal: TopoSpace.xl, vertical: TopoSpace.lg),
          child: (focused) => const Row(
            children: [
              Icon(Icons.star_outline_rounded, color: TopoColors.primaryAction, size: 32),
              SizedBox(width: TopoSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add a favourite grid', style: TopoText.label),
                    Text('Pin a multi-view grid here to open it with one press.', style: TopoText.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: TopoColors.muted),
            ],
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Favourite grid ${grid.name}, ${grid.cameraCount} cameras. Press OK to watch.',
      child: TvCard(
        autofocus: autofocus,
        padding: const EdgeInsets.all(TopoSpace.md),
        onSelect: () => openGrid(context, grid.id),
        onLongSelect: () => chooseFavoriteGrid(context),
        child: (focused) => Row(
          children: [
            SizedBox(
              width: 300,
              child: AspectRatio(aspectRatio: 16 / 9, child: GridSnapshotPreview(app: app, grid: grid)),
            ),
            const SizedBox(width: TopoSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, color: TopoColors.primaryAction, size: 20),
                      SizedBox(width: 6),
                      Text('Favourite grid', style: TextStyle(color: TopoColors.primaryPressed, fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: TopoSpace.xs),
                  Text(grid.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TopoText.headline),
                  Text('${grid.cameraCount} cameras · ${grid.layout.label}', style: TopoText.caption),
                  const SizedBox(height: TopoSpace.md),
                  HintBar([
                    (const KeyCap('OK'), 'Watch grid'),
                    (const KeyCap('Hold OK'), 'Change'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
