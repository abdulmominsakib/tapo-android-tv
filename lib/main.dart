import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'ui/guide.dart';
import 'ui/theme.dart';
import 'ui/tv.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final app = AppState()..init();
  runApp(TopoTvApp(app: app));
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Which guide tab the Menu key opens; screens update it when shown.
final guideSection = ValueNotifier(GuideSection.basics);

final navigatorKey = GlobalKey<NavigatorState>();

class TopoTvApp extends StatefulWidget {
  const TopoTvApp({super.key, required this.app});
  final AppState app;

  @override
  State<TopoTvApp> createState() => _TopoTvAppState();
}

class _TopoTvAppState extends State<TopoTvApp> {
  bool _guideOpen = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => widget.app.setForeground(state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  KeyEventResult _globalKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !guideKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    final context = navigatorKey.currentContext;
    if (context == null || _guideOpen) return KeyEventResult.handled;
    _guideOpen = true;
    showRemoteGuide(context, section: guideSection.value).whenComplete(() => _guideOpen = false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: widget.app,
      child: MaterialApp(
        title: 'Topo TV',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorKey: navigatorKey,
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
        },
        builder: (context, child) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _globalKeys,
          child: child!,
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget screen = switch (app.stage) {
      AuthStage.starting => const _Splash(),
      AuthStage.signedOut => const LoginScreen(key: ValueKey('login')),
      AuthStage.mfa => const MfaScreen(key: ValueKey('mfa')),
      AuthStage.signedIn => const HomeScreen(key: ValueKey('home')),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: screen);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/topo.png', width: 120, height: 120),
            const SizedBox(height: 20),
            const Text('Topo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: TopoColors.onSurface)),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: TopoColors.primaryAction),
            ),
            const SizedBox(height: 14),
            const Text('Connecting to your Tapo account…', style: TextStyle(color: TopoColors.muted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
