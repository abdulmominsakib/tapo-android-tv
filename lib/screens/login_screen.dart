import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';

/// Featured panel on the left of the sign-in screens.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    Widget feature(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: TopoSpace.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TopoColors.surface, borderRadius: BorderRadius.circular(TopoRadius.md)),
                child: Icon(icon, color: TopoColors.primary, size: 24),
              ),
              const SizedBox(width: TopoSpace.lg),
              Expanded(child: Text(text, style: TopoText.body)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(TopoSpace.x3),
      decoration: BoxDecoration(
        gradient: featuredGradient,
        borderRadius: BorderRadius.circular(TopoRadius.xl),
        boxShadow: featuredShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Image.asset('assets/topo.png', width: 64, height: 64, semanticLabel: 'Topo'),
              const SizedBox(width: TopoSpace.md),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Topo', style: TopoText.display),
                  Text('for Android TV', style: TextStyle(fontSize: 16, color: TopoColors.primaryAction, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: TopoSpace.x2),
          const Text('Your Tapo cameras on the big screen.', style: TopoText.title),
          const SizedBox(height: TopoSpace.xl),
          feature(Icons.cloud_rounded, 'Live view through the Tapo cloud'),
          feature(Icons.grid_view_rounded, 'Multi-view grids you can save'),
          feature(Icons.open_with_rounded, 'Pan & tilt with your remote'),
          const SizedBox(height: TopoSpace.sm),
          const Text('Unofficial app, not affiliated with TP-Link.', style: TopoText.caption),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.card});
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: tvSafePadding,
        child: Row(
          children: [
            const Expanded(flex: 10, child: Center(child: _Brand())),
            const SizedBox(width: TopoSpace.x3),
            Expanded(
              flex: 11,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.all(TopoSpace.x3),
                    decoration: BoxDecoration(
                      color: TopoColors.surface,
                      borderRadius: BorderRadius.circular(TopoRadius.xl),
                      boxShadow: cardShadow,
                    ),
                    child: card,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: TopoSpace.md),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_rounded, color: TopoColors.error, size: 22),
            const SizedBox(width: TopoSpace.sm),
            Expanded(child: Text(text!, style: TopoText.body.copyWith(color: TopoColors.error, height: 1.3))),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordFocus = FocusNode();
  final _signInFocus = FocusNode();
  late String _email = AppScope.read(context).accountHint;
  String _password = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.basics;
    _error = AppScope.read(context).camerasError;
  }

  @override
  void dispose() {
    _passwordFocus.dispose();
    _signInFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_email, _password);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Shell(
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sign in', style: TopoText.headline),
          const Text('Use the same account as the Tapo app.', style: TopoText.caption),
          const SizedBox(height: TopoSpace.xl),
          TvTextField(
            label: 'Email',
            hint: 'name@example.com',
            icon: Icons.alternate_email_rounded,
            value: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onChanged: (v) => setState(() => _email = v.trim()),
            onSubmitted: () => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: TopoSpace.lg),
          TvTextField(
            label: 'Password',
            hint: 'Your Tapo password',
            icon: Icons.lock_rounded,
            value: _password,
            obscure: true,
            focusNode: _passwordFocus,
            onChanged: (v) => setState(() => _password = v),
            onSubmitted: () => _signInFocus.requestFocus(),
          ),
          _ErrorText(_error),
          const SizedBox(height: TopoSpace.x2),
          TvButton(
            label: _busy ? 'Signing in…' : 'Sign in',
            icon: Icons.login_rounded,
            style: TvButtonStyle.primary,
            focusNode: _signInFocus,
            busy: _busy,
            expand: true,
            onPressed: _signIn,
          ),
          const SizedBox(height: TopoSpace.md),
          Row(
            children: [
              TvButton(
                label: 'Remote guide',
                icon: Icons.help_outline_rounded,
                style: TvButtonStyle.text,
                onPressed: () => showRemoteGuide(context),
              ),
              if (app.hasSavedSession) ...[
                const SizedBox(width: TopoSpace.sm),
                TvButton(
                  label: 'Retry saved session',
                  icon: Icons.refresh_rounded,
                  style: TvButtonStyle.text,
                  onPressed: app.retrySavedSession,
                ),
              ],
            ],
          ),
          const SizedBox(height: TopoSpace.sm),
          const Text('Your password is never stored on this TV.', style: TopoText.caption),
        ],
      ),
    );
  }
}

class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key});

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  final _codeFocus = FocusNode();
  final _verifyFocus = FocusNode();
  String _code = '';
  int? _sending;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _codeFocus.dispose();
    _verifyFocus.dispose();
    super.dispose();
  }

  Future<void> _request(int type) async {
    setState(() {
      _sending = type;
      _error = null;
    });
    try {
      await AppScope.read(context).requestMfa(type);
      WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await AppScope.read(context).verifyMfa(_code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Widget _spinner() => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: TopoColors.primaryAction),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pending = app.pendingMfa;
    if (pending == null) return const SizedBox.shrink();
    final requested = pending.requestedType;
    const chevron = Icon(Icons.chevron_right_rounded, color: TopoColors.muted);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.cancelMfa();
      },
      child: _Shell(
        card: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Verify it's you", style: TopoText.headline),
            Text(
              requested == null
                  ? 'This TV is new to your Tapo account. Choose how to get a code.'
                  : requested == 1
                      ? 'Open the Tapo app on your phone and enter the code it shows.'
                      : 'Enter the code sent to ${pending.username}.',
              style: TopoText.caption,
            ),
            const SizedBox(height: TopoSpace.xl),
            if (requested == null) ...[
              if (pending.types.contains(1)) ...[
                TvTile(
                  title: 'Tapo app notification',
                  subtitle: 'Get the code on your phone',
                  icon: Icons.phone_iphone_rounded,
                  autofocus: true,
                  trailing: _sending == 1 ? _spinner() : chevron,
                  onSelect: _sending == null ? () => _request(1) : null,
                ),
                const SizedBox(height: TopoSpace.md),
              ],
              if (pending.types.contains(2))
                TvTile(
                  title: 'Email code',
                  subtitle: 'Send a code to ${pending.username}',
                  icon: Icons.mail_rounded,
                  autofocus: !pending.types.contains(1),
                  trailing: _sending == 2 ? _spinner() : chevron,
                  onSelect: _sending == null ? () => _request(2) : null,
                ),
            ] else ...[
              TvTextField(
                label: 'Verification code',
                hint: '6-digit code',
                icon: Icons.pin_rounded,
                value: _code,
                keyboardType: TextInputType.number,
                focusNode: _codeFocus,
                onChanged: (v) => setState(() => _code = v.trim()),
                onSubmitted: () => _verifyFocus.requestFocus(),
              ),
              const SizedBox(height: TopoSpace.xl),
              TvButton(
                label: _verifying ? 'Verifying…' : 'Verify',
                icon: Icons.verified_user_rounded,
                style: TvButtonStyle.primary,
                expand: true,
                busy: _verifying,
                focusNode: _verifyFocus,
                onPressed: _verify,
              ),
              const SizedBox(height: TopoSpace.md),
              Wrap(
                spacing: TopoSpace.sm,
                children: [
                  TvButton(
                    label: 'Send again',
                    icon: Icons.refresh_rounded,
                    style: TvButtonStyle.text,
                    busy: _sending != null,
                    onPressed: () => _request(requested),
                  ),
                  if (pending.types.length > 1)
                    TvButton(
                      label: requested == 1 ? 'Use email instead' : 'Use Tapo app instead',
                      style: TvButtonStyle.text,
                      onPressed: () => _request(requested == 1 ? 2 : 1),
                    ),
                ],
              ),
            ],
            _ErrorText(_error),
            const SizedBox(height: TopoSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                label: 'Back to sign in',
                icon: Icons.arrow_back_rounded,
                style: TvButtonStyle.text,
                onPressed: app.cancelMfa,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
