import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget value(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: TopoSpace.md, vertical: 6),
          decoration: BoxDecoration(color: TopoColors.surface, borderRadius: BorderRadius.circular(TopoRadius.full)),
          child: Text(text, style: TopoText.label.copyWith(color: TopoColors.primaryPressed)),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              TvTile(
                title: 'Tapo account',
                subtitle: app.accountHint.isEmpty ? 'Signed in · ${app.regionHost}' : '${app.accountHint} · ${app.regionHost}',
                icon: Icons.person_rounded,
                autofocus: true,
              ),
              const SizedBox(height: TopoSpace.md),
              TvTile(
                title: 'Live previews on the camera list',
                subtitle: 'Turn off to save data on slower TVs',
                icon: Icons.videocam_rounded,
                // Changes only on OK, never on focus.
                trailing: ExcludeFocus(
                  child: Switch(
                    value: app.livePreviews,
                    activeThumbColor: TopoColors.onPrimary,
                    activeTrackColor: TopoColors.primaryAction,
                    onChanged: (v) => app.setLivePreviews(v),
                  ),
                ),
                onSelect: () => app.setLivePreviews(!app.livePreviews),
              ),
              const SizedBox(height: TopoSpace.md),
              TvTile(
                title: 'Pan & tilt step',
                subtitle: 'How far the camera moves per arrow press',
                icon: Icons.open_with_rounded,
                trailing: value('${app.ptzStep}°'),
                onSelect: () {
                  const steps = [5, 10, 20];
                  app.setPtzStep(steps[(steps.indexOf(app.ptzStep) + 1) % steps.length]);
                },
              ),
              const SizedBox(height: TopoSpace.md),
              TvTile(
                title: 'Remote control guide',
                subtitle: 'See which buttons do what',
                icon: Icons.help_outline_rounded,
                trailing: const Icon(Icons.chevron_right_rounded, color: TopoColors.muted),
                onSelect: () => showRemoteGuide(context),
              ),
              const SizedBox(height: TopoSpace.md),
              TvTile(
                title: 'Sign out',
                subtitle: 'Removes the saved Tapo session from this TV',
                icon: Icons.logout_rounded,
                danger: true,
                onSelect: () async {
                  final ok = await confirmDialog(
                    context,
                    title: 'Sign out?',
                    message: 'You will need your Tapo password and a verification code to sign in again.',
                    confirmLabel: 'Sign out',
                    danger: true,
                  );
                  if (ok && context.mounted) await app.logout();
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: TopoSpace.x3),
        SizedBox(
          width: 250,
          child: Container(
            padding: const EdgeInsets.all(TopoSpace.x2),
            decoration: BoxDecoration(
              gradient: featuredGradient,
              borderRadius: BorderRadius.circular(TopoRadius.lg),
              boxShadow: featuredShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/topo.png', width: 56, height: 56, semanticLabel: 'Topo'),
                const SizedBox(height: TopoSpace.md),
                const Text('Topo TV 1.2.0', style: TopoText.label),
                const SizedBox(height: TopoSpace.xs),
                const Text(
                  'Android TV port of github.com/filirnd/topo. MIT licence. Not affiliated with TP-Link.',
                  style: TopoText.caption,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
