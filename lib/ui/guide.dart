import 'package:flutter/material.dart';

import 'theme.dart';
import 'tv.dart';

enum GuideSection { basics, home, multiview, live }

enum _RemoteKey { up, down, left, right, ok, back, home, menu, chUp, chDown, digits }

class _Row {
  const _Row(this.keys, this.label, this.detail, this.highlight);
  final List<Widget> keys;
  final String label;
  final String detail;
  final Set<_RemoteKey> highlight;
}

const _dpad = {_RemoteKey.up, _RemoteKey.down, _RemoteKey.left, _RemoteKey.right};

final Map<GuideSection, (String, IconData, List<_Row>)> _sections = {
  GuideSection.basics: (
    'Basics',
    Icons.gamepad_rounded,
    [
      _Row([const KeyCap('', icon: Icons.open_with_rounded, large: true)], 'Move around',
          'The arrows move the blue outline between items.', _dpad),
      _Row([const KeyCap('OK', large: true)], 'Select', 'Opens or activates the outlined item.', {_RemoteKey.ok}),
      _Row([const KeyCap('', icon: Icons.arrow_back_rounded, large: true)], 'Go back',
          'Closes dialogs and controls first, then returns to the previous screen.', {_RemoteKey.back}),
      _Row([const KeyCap('', icon: Icons.menu_rounded, large: true)], 'Remote guide',
          'Menu or Info opens this guide. No such key? Use the Guide button.', {_RemoteKey.menu}),
      _Row([const KeyCap('OK', large: true)], 'Typing',
          'On a text box press OK to open the TV keyboard, or type from the Google TV phone app.', {_RemoteKey.ok}),
    ],
  ),
  GuideSection.home: (
    'Cameras',
    Icons.videocam_rounded,
    [
      _Row([const KeyCap('OK', large: true)], 'Watch live', 'Opens the outlined camera full screen.', {_RemoteKey.ok}),
      _Row([const KeyCap('Hold OK', large: true)], 'Quick actions',
          'Hold OK on a camera for privacy mode and reconnect.', {_RemoteKey.ok}),
      _Row([const KeyCap('1 – 9', large: true)], 'Jump to camera', 'Number keys open camera 1 to 9.', {_RemoteKey.digits}),
      _Row([const KeyCap('', icon: Icons.arrow_upward_rounded, large: true)], 'Top menu',
          'Move up to switch between Cameras, Multi-view and Settings, then press OK.', {_RemoteKey.up}),
    ],
  ),
  GuideSection.multiview: (
    'Multi-view',
    Icons.grid_view_rounded,
    [
      _Row([const KeyCap('OK', large: true)], 'Open a grid', 'In Multi-view, OK opens the outlined grid.', {_RemoteKey.ok}),
      _Row([const KeyCap('CH +', large: true), const SizedBox(width: 6), const KeyCap('CH −', large: true)],
          'Switch grid', 'While watching a grid, channel keys go to the next or previous saved grid.',
          {_RemoteKey.chUp, _RemoteKey.chDown}),
      _Row([const KeyCap('', icon: Icons.arrow_upward_rounded, large: true)], 'Grid bar',
          'Move up from the top row to pick another grid or edit this one.', {_RemoteKey.up}),
      _Row([const KeyCap('OK', large: true)], 'Full screen', 'OK on a tile opens that camera full screen.', {_RemoteKey.ok}),
      _Row([const KeyCap('Hold OK', large: true)], 'Change a tile',
          'Hold OK on a tile to put another camera in it.', {_RemoteKey.ok}),
    ],
  ),
  GuideSection.live: (
    'Live view',
    Icons.live_tv_rounded,
    [
      _Row([const KeyCap('', icon: Icons.open_with_rounded, large: true)], 'Pan & tilt',
          'With the controls hidden, arrows move the camera. Hold to keep moving.', _dpad),
      _Row([const KeyCap('OK', large: true)], 'Show controls',
          'Privacy, step size, reconnect and previous/next camera.', {_RemoteKey.ok}),
      _Row([const KeyCap('CH +', large: true), const SizedBox(width: 6), const KeyCap('CH −', large: true)],
          'Switch camera', 'Channel keys, previous/next track keys or 1–9. Without pan & tilt, left/right also switch.',
          {_RemoteKey.chUp, _RemoteKey.chDown}),
      _Row([const KeyCap('', icon: Icons.arrow_back_rounded, large: true)], 'Back',
          'First hides the controls, then returns to where you came from.', {_RemoteKey.back}),
    ],
  ),
};

Future<void> showRemoteGuide(BuildContext context, {GuideSection section = GuideSection.basics}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: TopoMotion.navigation,
      pageBuilder: (_, _, _) => RemoteGuide(initial: section),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class RemoteGuide extends StatefulWidget {
  const RemoteGuide({super.key, this.initial = GuideSection.basics});
  final GuideSection initial;

  @override
  State<RemoteGuide> createState() => _RemoteGuideState();
}

class _RemoteGuideState extends State<RemoteGuide> {
  late GuideSection _section = widget.initial;
  Set<_RemoteKey> _highlight = {};

  @override
  Widget build(BuildContext context) {
    final (_, _, rows) = _sections[_section]!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
        child: Container(
          decoration: BoxDecoration(color: TopoColors.surface, borderRadius: BorderRadius.circular(TopoRadius.xl)),
          padding: const EdgeInsets.fromLTRB(TopoSpace.x3, TopoSpace.x2, TopoSpace.x3, TopoSpace.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 170, child: Center(child: _Remote(highlight: _highlight))),
              const SizedBox(width: TopoSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Remote control guide', style: TopoText.headline),
                    const SizedBox(height: TopoSpace.md),
                    Wrap(
                      spacing: TopoSpace.sm,
                      runSpacing: TopoSpace.sm,
                      children: [
                        for (final s in GuideSection.values)
                          TvChip(
                            label: _sections[s]!.$1,
                            icon: _sections[s]!.$2,
                            selected: s == _section,
                            autofocus: s == widget.initial,
                            onSelect: () => setState(() => _section = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: TopoSpace.lg),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final row in rows)
                            _GuideRow(row: row, onFocus: (f) => setState(() => _highlight = f ? row.highlight : {})),
                        ],
                      ),
                    ),
                    const SizedBox(height: TopoSpace.md),
                    Row(
                      children: [
                        TvButton(
                          label: 'Got it',
                          icon: Icons.check_rounded,
                          style: TvButtonStyle.primary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: TopoSpace.lg),
                        const Expanded(
                          child: Text('Open this guide any time with Menu or Info.', style: TopoText.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.row, required this.onFocus});
  final _Row row;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TopoSpace.md),
      child: Semantics(
        label: '${row.label}. ${row.detail}',
        child: TvFocusable(
          onFocusChange: onFocus,
          onSelect: () {},
          builder: (context, focused) => FocusRing(
            focused: focused,
            scale: false,
            child: AnimatedContainer(
              duration: TopoMotion.focus,
              padding: const EdgeInsets.symmetric(horizontal: TopoSpace.lg, vertical: TopoSpace.md),
              decoration: BoxDecoration(
                color: focused ? TopoColors.surfaceSelected : TopoColors.neutral,
                borderRadius: BorderRadius.circular(TopoRadius.lg),
              ),
              child: Row(
                children: [
                  SizedBox(width: 132, child: Row(children: row.keys)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.label, style: TopoText.label),
                        Text(row.detail, style: TopoText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple remote illustration; keys in [highlight] are shown in blue.
class _Remote extends StatelessWidget {
  const _Remote({required this.highlight});
  final Set<_RemoteKey> highlight;

  bool _on(_RemoteKey k) => highlight.contains(k);
  Color _bg(_RemoteKey k) => _on(k) ? TopoColors.primaryAction : TopoColors.surfaceSelected;
  Color _fg(_RemoteKey k) => _on(k) ? TopoColors.onPrimary : TopoColors.primaryPressed;

  Widget _round(_RemoteKey k, IconData icon) => AnimatedContainer(
        duration: TopoMotion.focus,
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: _bg(k), shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: _fg(k)),
      );

  Widget _arrow(_RemoteKey k, IconData icon) => AnimatedContainer(
        duration: TopoMotion.focus,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _on(k) ? TopoColors.primaryAction : Colors.transparent),
        child: Icon(icon, size: 22, color: _fg(k)),
      );

  Widget _rocker(String label, _RemoteKey? up, _RemoteKey? down) {
    final on = (up != null && _on(up)) || (down != null && _on(down));
    final fg = on ? TopoColors.onPrimary : TopoColors.primaryPressed;
    return AnimatedContainer(
      duration: TopoMotion.focus,
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: on ? TopoColors.primaryAction : TopoColors.surfaceSelected,
        borderRadius: BorderRadius.circular(TopoRadius.full),
      ),
      child: Column(
        children: [
          Icon(Icons.add_rounded, size: 16, color: fg),
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
          Icon(Icons.remove_rounded, size: 16, color: fg),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 124,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          gradient: featuredGradient,
          borderRadius: BorderRadius.circular(62),
          boxShadow: featuredShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: TopoColors.primary, shape: BoxShape.circle)),
            const SizedBox(height: 14),
            Container(
              width: 98,
              height: 98,
              decoration: const BoxDecoration(color: TopoColors.surface, shape: BoxShape.circle, boxShadow: cardShadow),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(top: 2, child: _arrow(_RemoteKey.up, Icons.keyboard_arrow_up_rounded)),
                  Positioned(bottom: 2, child: _arrow(_RemoteKey.down, Icons.keyboard_arrow_down_rounded)),
                  Positioned(left: 2, child: _arrow(_RemoteKey.left, Icons.keyboard_arrow_left_rounded)),
                  Positioned(right: 2, child: _arrow(_RemoteKey.right, Icons.keyboard_arrow_right_rounded)),
                  AnimatedContainer(
                    duration: TopoMotion.focus,
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _bg(_RemoteKey.ok), shape: BoxShape.circle),
                    child: Text('OK', style: TextStyle(color: _fg(_RemoteKey.ok), fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _round(_RemoteKey.back, Icons.arrow_back_rounded),
                _round(_RemoteKey.home, Icons.home_rounded),
                _round(_RemoteKey.menu, Icons.menu_rounded),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_rocker('VOL', null, null), _rocker('CH', _RemoteKey.chUp, _RemoteKey.chDown)],
            ),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: TopoMotion.focus,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _bg(_RemoteKey.digits), borderRadius: BorderRadius.circular(TopoRadius.sm)),
              child: Text('1 2 3 …', style: TextStyle(color: _fg(_RemoteKey.digits), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
