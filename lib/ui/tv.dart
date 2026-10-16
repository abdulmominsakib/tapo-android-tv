import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Keys that activate the focused item on a remote, gamepad or keyboard.
final selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.space,
};

/// Keys that open the remote guide from anywhere.
final guideKeys = {
  LogicalKeyboardKey.contextMenu,
  LogicalKeyboardKey.info,
  LogicalKeyboardKey.guide,
  LogicalKeyboardKey.f1,
};

/// A D-pad focusable item: OK/Enter selects, holding OK triggers
/// [onLongSelect]. Scrolls itself fully into view when focused.
///
/// Focus alone never activates anything; only OK does.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongSelect,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
    this.ensureVisible = true,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool ensureVisible;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  DateTime? _pressedAt;
  bool _longFired = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (widget.onSelect == null && widget.onLongSelect == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _pressedAt = DateTime.now();
      _longFired = false;
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Android only starts repeating after the long-press timeout, so the
      // first repeat of the OK key is a "hold".
      if (widget.onLongSelect != null && !_longFired && _pressedAt != null) {
        _longFired = true;
        widget.onLongSelect!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final pressed = _pressedAt;
      _pressedAt = null;
      // Ignore key-ups whose key-down happened on another screen.
      if (pressed == null || _longFired) return KeyEventResult.handled;
      final held = DateTime.now().difference(pressed);
      if (widget.onLongSelect != null && held > const Duration(milliseconds: 600)) {
        widget.onLongSelect!();
      } else {
        widget.onSelect?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused && widget.ensureVisible) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: TopoMotion.navigation,
            curve: TopoMotion.curve,
          );
        }
        widget.onFocusChange?.call(focused);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onLongPress: widget.onLongSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}

/// The TV focus indicator: a 3-unit `primary-pressed` outline drawn 3 units
/// outside the item, plus an optional 1.04 scale. Over video or dark
/// surfaces ([onMedia]) the gap is filled white so the blue stays visible.
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius = TopoRadius.lg,
    this.onMedia = false,
    this.scale = true,
  });

  final bool focused;
  final Widget child;
  final double radius;
  final bool onMedia;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    const gap = TopoSpace.focusGap, width = TopoSpace.focusWidth;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedScale(
      scale: focused && scale && !reduceMotion ? 1.04 : 1.0,
      duration: TopoMotion.focus,
      curve: TopoMotion.curve,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          child,
          if (focused)
            Positioned(
              left: -(gap + width),
              top: -(gap + width),
              right: -(gap + width),
              bottom: -(gap + width),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius >= TopoRadius.full ? radius : radius + gap + width),
                    border: Border.all(color: TopoColors.primaryPressed, width: width),
                  ),
                  padding: const EdgeInsets.all(0),
                  child: onMedia
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius >= TopoRadius.full ? radius : radius + gap),
                            border: Border.all(color: Colors.white, width: gap),
                          ),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum TvButtonStyle { primary, secondary, text, danger }

/// Fully rounded 48-unit button. Focus adds the outline; colors stay.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.style = TvButtonStyle.secondary,
    this.busy = false,
    this.expand = false,
    this.onMedia = false,
    this.onFocusChange,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final TvButtonStyle style;
  final bool busy;
  final bool expand;
  final bool onMedia;
  final ValueChanged<bool>? onFocusChange;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? label,
      child: TvFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        // Busy buttons keep focus but ignore presses (no duplicate submits).
        onSelect: busy ? () {} : onPressed,
        builder: (context, focused) {
          final (bg, fg) = disabled
              ? (TopoColors.disabledSurface, TopoColors.disabledText)
              : switch (style) {
                  TvButtonStyle.primary => (TopoColors.primaryAction, TopoColors.onPrimary),
                  TvButtonStyle.secondary => (TopoColors.surfaceSelected, TopoColors.primaryPressed),
                  TvButtonStyle.text => (focused ? TopoColors.surfaceSelected : Colors.transparent, TopoColors.primaryAction),
                  TvButtonStyle.danger => (const Color(0xFFFBE9E8), TopoColors.error),
                };
          return FocusRing(
            focused: focused,
            radius: TopoRadius.full,
            onMedia: onMedia,
            child: AnimatedContainer(
              duration: TopoMotion.press,
              height: 48,
              padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 12 : TopoSpace.x2),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TopoRadius.full)),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Progress replaces the leading icon while busy.
                  if (busy)
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                  else if (icon != null)
                    Icon(icon, size: 24, color: fg),
                  if ((icon != null || busy) && label.isNotEmpty) const SizedBox(width: TopoSpace.sm),
                  if (label.isNotEmpty)
                    Flexible(
                      child: Text(label, overflow: TextOverflow.ellipsis, style: TopoText.label.copyWith(color: fg)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fully rounded chip; selected chips are pale blue with a checkmark.
class TvChip extends StatelessWidget {
  const TvChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelect,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.onMedia = false,
    this.onFocusChange,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelect;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool onMedia;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TvFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onSelect: onSelect,
        onFocusChange: onFocusChange,
        builder: (context, focused) {
          final fg = selected ? TopoColors.primaryPressed : TopoColors.muted;
          return FocusRing(
            focused: focused,
            radius: TopoRadius.full,
            onMedia: onMedia,
            child: AnimatedContainer(
              duration: TopoMotion.press,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: TopoSpace.lg),
              decoration: BoxDecoration(
                color: selected ? TopoColors.surfaceSelected : TopoColors.surface,
                borderRadius: BorderRadius.circular(TopoRadius.full),
                border: Border.all(color: selected ? TopoColors.surfaceSelected : TopoColors.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected)
                    Icon(Icons.check_rounded, size: 20, color: fg)
                  else if (icon != null)
                    Icon(icon, size: 20, color: fg),
                  if (selected || icon != null) const SizedBox(width: 6),
                  Text(label, style: TopoText.label.copyWith(color: fg, fontSize: 17)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// White card. Focused cards turn pale blue and get the outline.
class TvCard extends StatelessWidget {
  const TvCard({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongSelect,
    this.autofocus = false,
    this.focusNode,
    this.padding = const EdgeInsets.all(TopoSpace.cardPadding),
    this.selected = false,
    this.onFocusChange,
  });

  final Widget Function(bool focused) child;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final bool selected;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      onFocusChange: onFocusChange,
      builder: (context, focused) => FocusRing(
        focused: focused,
        child: AnimatedContainer(
          duration: TopoMotion.focus,
          padding: padding,
          decoration: BoxDecoration(
            color: focused || selected ? TopoColors.surfaceSelected : TopoColors.surface,
            borderRadius: BorderRadius.circular(TopoRadius.lg),
            boxShadow: cardShadow,
          ),
          child: child(focused),
        ),
      ),
    );
  }
}

/// 64-unit list row for settings and option lists.
class TvTile extends StatelessWidget {
  const TvTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onSelect,
    this.autofocus = false,
    this.focusNode,
    this.danger = false,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onSelect;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool danger;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? TopoColors.error : TopoColors.primaryAction;
    return Semantics(
      button: onSelect != null,
      selected: selected,
      label: title,
      child: TvCard(
        autofocus: autofocus,
        focusNode: focusNode,
        onSelect: onSelect,
        selected: selected,
        padding: const EdgeInsets.symmetric(horizontal: TopoSpace.xl, vertical: TopoSpace.md),
        child: (focused) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: focused || selected ? TopoColors.surface : TopoColors.surfaceSelected,
                    borderRadius: BorderRadius.circular(TopoRadius.md),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: TopoSpace.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TopoText.label.copyWith(color: danger ? TopoColors.error : TopoColors.onSurface)),
                    if (subtitle != null) Text(subtitle!, style: TopoText.caption),
                  ],
                ),
              ),
              if (selected && trailing == null)
                const Icon(Icons.check_circle_rounded, color: TopoColors.primaryAction, size: 26),
              if (trailing != null) ...[const SizedBox(width: TopoSpace.lg), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A text field that works with a remote: a persistent label above a white
/// field; OK opens an entry dialog with the platform TV keyboard.
class TvTextField extends StatelessWidget {
  const TvTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.icon,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
  });

  final String label;
  final String value;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType keyboardType;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _TextEntryDialog(
        label: label,
        initial: value,
        hint: hint,
        obscure: obscure,
        keyboardType: keyboardType,
      ),
    );
    if (result != null) {
      onChanged(result);
      onSubmitted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? hint : (obscure ? '•' * value.length.clamp(0, 24) : value);
    return Semantics(
      textField: true,
      label: label,
      value: obscure ? null : value,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label, style: TopoText.caption.copyWith(color: TopoColors.onSurface, fontWeight: FontWeight.w500)),
          ),
          TvFocusable(
            autofocus: autofocus,
            focusNode: focusNode,
            onSelect: () => _edit(context),
            builder: (context, focused) => FocusRing(
              focused: focused,
              radius: TopoRadius.md,
              scale: false,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: TopoSpace.lg),
                decoration: BoxDecoration(
                  color: TopoColors.surface,
                  borderRadius: BorderRadius.circular(TopoRadius.md),
                  border: Border.all(color: TopoColors.muted),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: focused ? TopoColors.primaryAction : TopoColors.muted, size: 22),
                      const SizedBox(width: TopoSpace.md),
                    ],
                    Expanded(
                      child: Text(
                        shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TopoText.body.copyWith(color: value.isEmpty ? TopoColors.muted : TopoColors.onSurface),
                      ),
                    ),
                    if (focused)
                      Row(
                        children: [
                          const KeyCap('OK'),
                          const SizedBox(width: 6),
                          Text('to type', style: TopoText.caption.copyWith(fontSize: 15)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.label,
    required this.initial,
    required this.hint,
    required this.obscure,
    required this.keyboardType,
  });

  final String label;
  final String initial;
  final String hint;
  final bool obscure;
  final TextInputType keyboardType;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  // Existing text starts selected, so typing replaces it.
  late final TextEditingController _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  late bool _hidden = widget.obscure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TopoColors.surface,
      // Keep the entry above the on-screen keyboard, which rises from below.
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(120, 24, 120, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TopoRadius.xl)),
      child: Padding(
        padding: const EdgeInsets.all(TopoSpace.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: TopoText.title),
            const SizedBox(height: TopoSpace.lg),
            // Up/Down leave the single-line field so the buttons are reachable.
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
                SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
              },
              child: TextField(
                controller: _controller,
                autofocus: true,
                obscureText: _hidden,
                keyboardType: widget.keyboardType,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                style: TopoText.body,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TopoText.body.copyWith(color: TopoColors.muted),
                  filled: true,
                  fillColor: TopoColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: TopoSpace.lg, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TopoRadius.md),
                    borderSide: const BorderSide(color: TopoColors.muted),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TopoRadius.md),
                    borderSide: const BorderSide(color: TopoColors.primaryPressed, width: 3),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ),
            const SizedBox(height: TopoSpace.sm),
            const Text('You can also type from the Google TV app on your phone.', style: TopoText.caption),
            const SizedBox(height: TopoSpace.x2),
            Row(
              children: [
                TvButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  style: TvButtonStyle.primary,
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                ),
                const SizedBox(width: TopoSpace.md),
                if (widget.obscure) ...[
                  TvButton(
                    label: _hidden ? 'Show' : 'Hide',
                    icon: _hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                  const SizedBox(width: TopoSpace.md),
                ],
                TvButton(label: 'Cancel', style: TvButtonStyle.text, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A remote key glyph used in hints and the guide.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.icon, this.large = false, this.onMedia = false});
  final String label;
  final IconData? icon;
  final bool large;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final fg = onMedia ? TopoColors.onMedia : TopoColors.primaryPressed;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      constraints: BoxConstraints(minWidth: large ? 36 : 28),
      decoration: BoxDecoration(
        color: onMedia ? Colors.white.withValues(alpha: 0.16) : TopoColors.surfaceSelected,
        borderRadius: BorderRadius.circular(TopoRadius.sm),
      ),
      child: icon != null
          ? Icon(icon, size: large ? 20 : 17, color: fg)
          : Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: fg, fontSize: large ? 16 : 14, fontWeight: FontWeight.w700),
            ),
    );
  }
}

/// Row of remote hints, e.g. [OK] Watch live.
class HintBar extends StatelessWidget {
  const HintBar(this.hints, {super.key, this.onMedia = false});
  final List<(Widget, String)> hints;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: TopoSpace.x2,
      runSpacing: TopoSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (key, text) in hints)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              key,
              const SizedBox(width: TopoSpace.sm),
              Text(
                text,
                style: TopoText.caption.copyWith(color: onMedia ? TopoColors.onMedia : TopoColors.muted),
              ),
            ],
          ),
      ],
    );
  }
}

OverlayEntry? _currentToast;

/// Short, non-focusable status message; a new one replaces the last.
/// Important outcomes are also reflected on screen, not only here.
void showToast(BuildContext context, String message, {IconData? icon, bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _currentToast?.remove();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      icon: icon ?? (error ? Icons.error_outline_rounded : Icons.check_circle_rounded),
      error: error,
      onDone: () {
        if (identical(_currentToast, entry)) _currentToast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.icon, required this.error, required this.onDone});
  final String message;
  final IconData icon;
  final bool error;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _timer = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      setState(() => _visible = false);
      _timer = Timer(TopoMotion.navigation, widget.onDone);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.error ? TopoColors.error : TopoColors.success;
    return Positioned(
      top: 27,
      right: 48,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: TopoMotion.navigation,
          child: Material(
            color: Colors.transparent,
            child: Semantics(
              liveRegion: true,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.symmetric(horizontal: TopoSpace.xl, vertical: TopoSpace.md),
                decoration: BoxDecoration(
                  color: TopoColors.surface,
                  borderRadius: BorderRadius.circular(TopoRadius.lg),
                  boxShadow: const [BoxShadow(color: Color(0x2910486E), blurRadius: 20, offset: Offset(0, 6))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: color),
                    const SizedBox(width: TopoSpace.md),
                    Flexible(child: Text(widget.message, style: TopoText.body.copyWith(color: color, height: 1.3))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Concise centered TV dialog. Focus starts on the safe action.
class TvDialog extends StatelessWidget {
  const TvDialog({super.key, required this.title, this.message, required this.children, this.maxWidth = 560});
  final String title;
  final String? message;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TopoColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TopoRadius.xl)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TopoSpace.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TopoText.headline),
              if (message != null) ...[
                const SizedBox(height: TopoSpace.sm),
                Text(message!, style: TopoText.body.copyWith(color: TopoColors.muted)),
              ],
              const SizedBox(height: TopoSpace.x2),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showTvDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(context: context, barrierColor: Colors.black54, builder: builder);

/// Confirmation dialog; Cancel is focused and Back cancels.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final result = await showTvDialog<bool>(
    context,
    (context) => TvDialog(
      title: title,
      message: message,
      children: [
        Row(
          children: [
            TvButton(label: 'Cancel', autofocus: true, onPressed: () => Navigator.pop(context, false)),
            const SizedBox(width: TopoSpace.md),
            TvButton(
              label: confirmLabel,
              style: danger ? TvButtonStyle.danger : TvButtonStyle.primary,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}
