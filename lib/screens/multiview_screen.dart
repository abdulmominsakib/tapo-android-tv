import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../player/live_player.dart';
import '../state/app_state.dart';
import '../state/grids.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'home_screen.dart' show cameraStatus, digitIndex, openLive;

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

Future<void> openGrid(BuildContext context, String gridId) async {
  final previous = guideSection.value;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: TopoMotion.navigation,
      pageBuilder: (_, _, _) => GridViewScreen(gridId: gridId),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
  guideSection.value = previous;
}

/// Opens the editor; returns the saved grid, or null when cancelled.
Future<GridPreset?> editGrid(BuildContext context, GridPreset? grid) {
  return Navigator.of(context).push<GridPreset>(MaterialPageRoute(builder: (_) => GridEditorScreen(initial: grid)));
}

/// Picks the camera for one tile. Returns '' for "empty", null on Back.
Future<String?> pickCamera(BuildContext context, {required int slot, String? current}) {
  final app = AppScope.read(context);
  return showTvDialog<String>(
    context,
    (context) => TvDialog(
      title: 'Camera for tile ${slot + 1}',
      children: [
        TvTile(
          title: 'Empty tile',
          icon: Icons.crop_square_rounded,
          selected: current == null,
          autofocus: current == null,
          onSelect: () => Navigator.pop(context, ''),
        ),
        for (final camera in app.cameras) ...[
          const SizedBox(height: TopoSpace.md),
          TvTile(
            title: camera.name,
            subtitle: camera.model,
            icon: Icons.videocam_rounded,
            selected: camera.deviceId == current,
            autofocus: camera.deviceId == current,
            onSelect: () => Navigator.pop(context, camera.deviceId),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------- Panel --

/// Multi-view tab: the saved grids, the built-in "All cameras" grid and a
/// "New grid" card.
class MultiviewPanel extends StatelessWidget {
  const MultiviewPanel({super.key});

  Future<void> _options(BuildContext context, GridPreset grid) async {
    final app = AppScope.read(context);
    final action = await showTvDialog<String>(
      context,
      (context) => TvDialog(
        title: grid.name,
        message: '${grid.cameraCount} cameras · ${grid.layout.label}',
        children: [
          TvTile(
            title: 'Watch',
            icon: Icons.play_arrow_rounded,
            autofocus: true,
            onSelect: () => Navigator.pop(context, 'open'),
          ),
          const SizedBox(height: TopoSpace.md),
          if (grid.isAuto)
            TvTile(
              title: 'Save a copy to customise',
              subtitle: 'All cameras updates by itself and cannot be edited',
              icon: Icons.copy_rounded,
              onSelect: () => Navigator.pop(context, 'copy'),
            )
          else ...[
            TvTile(title: 'Edit', icon: Icons.edit_rounded, onSelect: () => Navigator.pop(context, 'edit')),
            const SizedBox(height: TopoSpace.md),
            TvTile(title: 'Duplicate', icon: Icons.copy_rounded, onSelect: () => Navigator.pop(context, 'copy')),
            const SizedBox(height: TopoSpace.md),
            TvTile(
              title: 'Delete',
              icon: Icons.delete_rounded,
              danger: true,
              onSelect: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'open':
        await openGrid(context, grid.id);
      case 'edit':
        await editGrid(context, grid);
      case 'copy':
        await editGrid(context, GridPreset(id: '', name: '${grid.name} copy', layout: grid.layout, slots: grid.slots));
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete "${grid.name}"?',
          message: 'The cameras are not affected; only this saved grid is removed.',
          confirmLabel: 'Delete',
          danger: true,
        );
        if (ok) {
          await app.deleteGrid(grid.id);
          if (context.mounted) showToast(context, 'Grid deleted');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grids = app.grids;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: TopoSpace.cardGap,
              crossAxisSpacing: TopoSpace.cardGap,
              childAspectRatio: 1.3,
            ),
            itemCount: grids.length + 1,
            itemBuilder: (context, i) {
              if (i == grids.length) {
                return TvCard(
                  onSelect: () async {
                    final saved = await editGrid(context, null);
                    if (saved != null && context.mounted) showToast(context, '"${saved.name}" saved');
                  },
                  child: (focused) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_rounded, size: 48, color: TopoColors.primaryAction),
                      SizedBox(height: TopoSpace.md),
                      Text('New grid', style: TopoText.label),
                      Text('Pick a layout and cameras', style: TopoText.caption),
                    ],
                  ),
                );
              }
              final grid = grids[i];
              final last = grid.id == app.activeGridId;
              return Semantics(
                label: '${grid.name}, ${grid.cameraCount} cameras, ${grid.layout.label}${last ? ', last used' : ''}',
                child: TvCard(
                  autofocus: i == 0,
                  selected: last,
                  padding: const EdgeInsets.all(TopoSpace.md),
                  onSelect: () => openGrid(context, grid.id),
                  onLongSelect: () => _options(context, grid),
                  child: (focused) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutDiagram(app: app, grid: grid),
                      ),
                      const SizedBox(height: TopoSpace.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(grid.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TopoText.label),
                          ),
                          if (last) ...[
                            const Icon(Icons.check_circle_rounded, size: 18, color: TopoColors.primaryPressed),
                            const SizedBox(width: 4),
                            Text('Last used', style: TopoText.caption.copyWith(color: TopoColors.primaryPressed)),
                          ],
                        ],
                      ),
                      Text(
                        '${grid.cameraCount} cameras · ${grid.layout.label}${grid.isAuto ? ' · automatic' : ''}',
                        style: TopoText.caption,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: TopoSpace.sm),
        HintBar([
          (const KeyCap('OK'), 'Watch grid'),
          (const KeyCap('Hold OK'), 'Edit, duplicate or delete'),
          (const KeyCap('CH ±'), 'Switch grid while watching'),
        ]),
      ],
    );
  }
}

/// Miniature of a grid's layout with the camera names in each tile.
class LayoutDiagram extends StatelessWidget {
  const LayoutDiagram({super.key, required this.app, required this.grid});
  final AppState app;
  final GridPreset grid;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(gradient: featuredGradient, borderRadius: BorderRadius.circular(TopoRadius.sm)),
        padding: const EdgeInsets.all(6),
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _TileLayout(
              layout: grid.layout,
              gap: 4,
              builder: (i) {
                final camera = app.cameraById(grid.slots[i]);
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: camera != null ? TopoColors.primary : TopoColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: camera != null ? null : Border.all(color: TopoColors.outline),
                  ),
                  child: Text(
                    camera?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TopoColors.onPrimary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Positions one widget per tile of [layout] inside the available box.
class _TileLayout extends StatelessWidget {
  const _TileLayout({required this.layout, required this.builder, this.gap = 8});
  final GridLayout layout;
  final Widget Function(int index) builder;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cw = box.maxWidth / layout.cols, ch = box.maxHeight / layout.rows;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < layout.slots; i++)
              Positioned(
                left: layout.tiles[i].left * cw + gap / 2,
                top: layout.tiles[i].top * ch + gap / 2,
                width: layout.tiles[i].width * cw - gap,
                height: layout.tiles[i].height * ch - gap,
                child: builder(i),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- Watching --

/// Full-screen multi-view of one grid; CH± or the top bar switches grids.
class GridViewScreen extends StatefulWidget {
  const GridViewScreen({super.key, required this.gridId});
  final String gridId;

  @override
  State<GridViewScreen> createState() => _GridViewScreenState();
}

class _GridViewScreenState extends State<GridViewScreen> {
  late String _gridId = widget.gridId;
  final _firstTile = FocusNode(debugLabel: 'grid-first-tile');
  final _barEntry = FocusNode(debugLabel: 'grid-bar-entry');
  bool _barFocused = false;
  bool _flash = true;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.multiview;
    _flashBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.read(context).setActiveGrid(_gridId);
      _firstTile.requestFocus();
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _firstTile.dispose();
    _barEntry.dispose();
    super.dispose();
  }

  /// Moves focus back to the tiles (they are excluded while the bar is
  /// focused, so re-include them first).
  void _focusTiles() {
    setState(() => _barFocused = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstTile.requestFocus();
    });
  }

  void _flashBar() {
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _switchTo(String id, {bool keepBarFocus = false}) {
    final app = AppScope.read(context);
    setState(() => _gridId = id);
    app.setActiveGrid(id);
    _flashBar();
    if (!keepBarFocus) _focusTiles();
  }

  void _step(int delta) {
    final grids = AppScope.read(context).grids;
    final i = grids.indexWhere((g) => g.id == _gridId);
    _switchTo(grids[(i + delta) % grids.length].id);
  }

  Future<void> _changeTile(GridPreset grid, int slot) async {
    if (grid.isAuto) {
      final copy = await confirmDialog(
        context,
        title: 'All cameras is automatic',
        message: 'Save a copy of this grid to choose the camera in each tile.',
        confirmLabel: 'Save a copy',
      );
      if (!copy || !mounted) return;
      final saved = await editGrid(
        context,
        GridPreset(id: '', name: 'My grid', layout: grid.layout, slots: grid.slots),
      );
      if (saved != null && mounted) _switchTo(saved.id);
      return;
    }
    final picked = await pickCamera(context, slot: slot, current: grid.slots[slot]);
    if (picked == null || !mounted) return;
    final slots = [...grid.slots]..[slot] = picked.isEmpty ? null : picked;
    await AppScope.read(context).saveGrid(grid.copyWith(slots: slots));
  }

  void _openTile(GridPreset grid, int slot) {
    final id = grid.slots[slot];
    if (id == null) {
      _changeTile(grid, slot);
      return;
    }
    openLive(context, AppScope.read(context).cameraIndex(id));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, GridPreset grid) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_nextKeys.contains(key)) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (_prevKeys.contains(key)) {
      _step(-1);
      return KeyEventResult.handled;
    }
    final digit = digitIndex(key);
    if (digit != null && digit < grid.layout.slots) {
      _openTile(grid, digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Up from the top row of tiles enters the grid bar.
  KeyEventResult _tilesKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && !focused.focusInDirection(TraversalDirection.up)) {
      _barEntry.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _barKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    _focusTiles();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grid = app.gridById(_gridId);
    final grids = app.grids;
    final showBar = _barFocused || _flash;
    return PopScope(
      // Back first leaves the grid bar, then closes the grid.
      canPop: !_barFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focusTiles();
      },
      child: Scaffold(
        backgroundColor: TopoColors.media,
        body: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => _onKey(node, event, grid),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _tilesKey,
                  // While the grid bar has focus, arrows must stay inside it
                  // (the bar overlaps the top tiles); Down returns explicitly.
                  child: ExcludeFocus(
                    excluding: _barFocused,
                    child: FocusTraversalGroup(
                      child: _TileLayout(
                        layout: grid.layout,
                        gap: 14,
                        builder: (i) {
                          final camera = app.cameraById(grid.slots[i]);
                          return _GridTile(
                            key: ValueKey('${grid.id}-$i-${camera?.deviceId}'),
                            app: app,
                            camera: camera,
                            number: i + 1,
                            focusNode: i == 0 ? _firstTile : null,
                            active: app.foreground && (ModalRoute.of(context)?.isCurrent ?? true),
                            onSelect: () => _openTile(grid, i),
                            onLongSelect: () => _changeTile(grid, i),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedOpacity(
                  opacity: showBar ? 1 : 0,
                  duration: TopoMotion.navigation,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (f) => setState(() => _barFocused = f),
                    onKeyEvent: _barKey,
                    child: FocusTraversalGroup(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(48, 20, 48, 20),
                        decoration: const BoxDecoration(color: TopoColors.media),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(grid.name, style: TopoText.title.copyWith(color: TopoColors.onMedia)),
                                Text(
                                  '${grid.cameraCount} cameras · ${grid.layout.label} · CH ± to switch',
                                  style: TopoText.caption.copyWith(color: const Color(0xFFC9D3DC)),
                                ),
                              ],
                            ),
                            const SizedBox(width: TopoSpace.x2),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                child: Row(
                                  children: [
                                    for (final g in grids) ...[
                                      TvChip(
                                        label: g.name,
                                        selected: g.id == grid.id,
                                        onMedia: true,
                                        focusNode: g.id == grid.id ? _barEntry : null,
                                        onSelect: () => _switchTo(g.id, keepBarFocus: true),
                                      ),
                                      const SizedBox(width: TopoSpace.sm),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: TopoSpace.md),
                            TvButton(
                              label: grid.isAuto ? 'Save a copy' : 'Edit grid',
                              icon: grid.isAuto ? Icons.copy_rounded : Icons.edit_rounded,
                              onMedia: true,
                              onPressed: () async {
                                final saved = await editGrid(
                                  context,
                                  grid.isAuto
                                      ? GridPreset(id: '', name: 'My grid', layout: grid.layout, slots: grid.slots)
                                      : grid,
                                );
                                if (saved != null && mounted) _switchTo(saved.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _GridTile extends StatefulWidget {
  const _GridTile({
    super.key,
    required this.app,
    required this.camera,
    required this.number,
    required this.active,
    required this.onSelect,
    required this.onLongSelect,
    this.focusNode,
  });

  final AppState app;
  final Camera? camera;
  final int number;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onLongSelect;
  final FocusNode? focusNode;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  LiveState? _live;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    final (status, icon, color) = camera == null
        ? ('Empty', Icons.add_rounded, TopoColors.muted)
        : cameraStatus(camera, _live, previews: true);
    return Semantics(
      button: true,
      label: camera == null ? 'Tile ${widget.number}, empty' : 'Tile ${widget.number}, ${camera.name}, $status',
      child: TvFocusable(
        focusNode: widget.focusNode,
        ensureVisible: false,
        onSelect: widget.onSelect,
        onLongSelect: widget.onLongSelect,
        builder: (context, focused) => FocusRing(
          focused: focused,
          radius: TopoRadius.md,
          onMedia: true,
          scale: false,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TopoRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (camera == null)
                  Container(
                    color: const Color(0xFF1B2733),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: Color(0xFFC9D3DC), size: 36),
                        SizedBox(height: TopoSpace.sm),
                        Text('Empty tile · OK to add', style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 16)),
                      ],
                    ),
                  )
                else if (camera.privacy == true)
                  Container(
                    color: const Color(0xFF1B2733),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_off_rounded, color: Color(0xFFC9D3DC), size: 36),
                        SizedBox(height: TopoSpace.sm),
                        Text('Privacy mode on', style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 16)),
                      ],
                    ),
                  )
                else if (widget.active)
                  LiveVideo(
                    app: widget.app,
                    camera: camera,
                    compact: true,
                    onStateChanged: (s) => setState(() => _live = s),
                  ),
                // Name label on an opaque media backing for legibility.
                Positioned(
                  left: TopoSpace.sm,
                  bottom: TopoSpace.sm,
                  right: TopoSpace.sm,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: TopoColors.media.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(TopoRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.number}',
                                style: const TextStyle(
                                  color: TopoColors.onMedia,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: TopoSpace.sm),
                              Flexible(
                                child: Text(
                                  camera?.name ?? 'Empty',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TopoColors.onMedia,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (camera != null && status == 'Live') ...[
                                const SizedBox(width: TopoSpace.sm),
                                Icon(icon, size: 9, color: const Color(0xFF4CD99A)),
                                const SizedBox(width: 4),
                                const Text('Live', style: TextStyle(color: TopoColors.onMedia, fontSize: 13)),
                              ],
                              if (color == TopoColors.error) ...[
                                const SizedBox(width: TopoSpace.sm),
                                Text(status, style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Editor --

class GridEditorScreen extends StatefulWidget {
  const GridEditorScreen({super.key, this.initial});

  /// Grid to edit; id '' (or null) creates a new one.
  final GridPreset? initial;

  @override
  State<GridEditorScreen> createState() => _GridEditorScreenState();
}

class _GridEditorScreenState extends State<GridEditorScreen> {
  late String _name = widget.initial?.name ?? '';
  late GridLayout _layout = widget.initial?.layout ?? GridLayout.quad;
  late List<String?> _slots = [...?widget.initial?.slots];
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.initial == null || widget.initial!.id.isEmpty;

  List<String?> _fit(List<String?> slots, GridLayout layout) =>
      List.generate(layout.slots, (i) => i < slots.length ? slots[i] : null);

  void _fillAll() {
    final app = AppScope.read(context);
    setState(() => _slots = _fit([for (final c in app.cameras) c.deviceId], _layout));
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final slots = _fit(_slots, _layout);
    if (slots.every((s) => s == null)) {
      setState(() => _error = 'Add at least one camera to the grid.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.trim().isEmpty ? 'Grid ${app.savedGrids.length + 1}' : _name.trim();
    final saved = await app.saveGrid(
      GridPreset(id: _isNew ? '' : widget.initial!.id, name: name, layout: _layout, slots: slots),
    );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final slots = _fit(_slots, _layout);
    return Scaffold(
      body: Padding(
        padding: tvSafePadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: FocusTraversalGroup(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    Text(_isNew ? 'New grid' : 'Edit grid', style: TopoText.headline),
                    const Text('Choose a layout, then a camera for each tile.', style: TopoText.caption),
                    const SizedBox(height: TopoSpace.xl),
                    TvTextField(
                      label: 'Name',
                      hint: 'e.g. Downstairs',
                      icon: Icons.label_rounded,
                      value: _name,
                      autofocus: true,
                      onChanged: (v) => setState(() => _name = v),
                    ),
                    const SizedBox(height: TopoSpace.xl),
                    Text(
                      'Layout',
                      style: TopoText.caption.copyWith(color: TopoColors.onSurface, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: TopoSpace.sm),
                    Wrap(
                      spacing: TopoSpace.sm,
                      runSpacing: TopoSpace.md,
                      children: [
                        for (final l in GridLayout.values)
                          TvChip(label: l.label, selected: l == _layout, onSelect: () => setState(() => _layout = l)),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: TopoSpace.md),
                      Row(
                        children: [
                          const Icon(Icons.error_rounded, color: TopoColors.error),
                          const SizedBox(width: TopoSpace.sm),
                          Expanded(
                            child: Text(_error!, style: TopoText.body.copyWith(color: TopoColors.error)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: TopoSpace.x2),
                    TvButton(
                      label: 'Save grid',
                      icon: Icons.check_rounded,
                      style: TvButtonStyle.primary,
                      busy: _saving,
                      expand: true,
                      onPressed: _save,
                    ),
                    const SizedBox(height: TopoSpace.md),
                    Wrap(
                      spacing: TopoSpace.sm,
                      runSpacing: TopoSpace.sm,
                      children: [
                        TvButton(
                          label: 'Fill with all cameras',
                          icon: Icons.auto_awesome_mosaic_rounded,
                          onPressed: _fillAll,
                        ),
                        if (!_isNew)
                          TvButton(
                            label: 'Delete',
                            icon: Icons.delete_rounded,
                            style: TvButtonStyle.danger,
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete "${widget.initial!.name}"?',
                                message: 'Only this saved grid is removed.',
                                confirmLabel: 'Delete',
                                danger: true,
                              );
                              if (ok && context.mounted) {
                                await app.deleteGrid(widget.initial!.id);
                                if (context.mounted) Navigator.of(context).pop();
                              }
                            },
                          ),
                        TvButton(
                          label: 'Cancel',
                          style: TvButtonStyle.text,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: TopoSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const Text('Tiles', style: TopoText.title),
                  const Text('OK on a tile to choose its camera.', style: TopoText.caption),
                  const SizedBox(height: TopoSpace.lg),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: FocusTraversalGroup(
                          child: _TileLayout(
                            layout: _layout,
                            gap: 16,
                            builder: (i) {
                              final camera = app.cameraById(slots[i]);
                              return TvCard(
                                padding: const EdgeInsets.all(TopoSpace.sm),
                                onSelect: () async {
                                  final picked = await pickCamera(context, slot: i, current: slots[i]);
                                  if (picked == null) return;
                                  setState(() => _slots = [...slots]..[i] = picked.isEmpty ? null : picked);
                                },
                                child: (focused) => Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      camera == null ? Icons.add_circle_outline_rounded : Icons.videocam_rounded,
                                      color: TopoColors.primaryAction,
                                      size: _layout.slots > 6 ? 22 : 30,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      camera?.name ?? 'Tile ${i + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TopoText.label.copyWith(fontSize: _layout.slots > 6 ? 15 : 18),
                                    ),
                                    if (camera == null && _layout.slots <= 6)
                                      const Text('Add camera', style: TopoText.caption),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
