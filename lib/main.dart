import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/backup.dart';
import 'core/sync.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'ui.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState.instance;
  await app.load();
  await SyncEngine.instance.init();
  runApp(const FreelyApp());
  if (app.approved) Backup.runAutoIfDue();
}

class FreelyApp extends StatelessWidget {
  const FreelyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (_, __) => MaterialApp(
        title: 'Freely NGO',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        themeMode: AppState.instance.themeMode,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => SkyBackground(child: child ?? const SizedBox.shrink()),
        home: const Root(),
      ),
    );
  }
}

/// Chooses the screen from the login state. Login is a one-time activity: once the admin approved this device the app opens
/// straight on the dashboard every time.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String _lastStatus = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final app = AppState.instance;
        if (!app.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final s = app.session;
        final status = (s?['status'] ?? '') as String;
        if (status != _lastStatus) {
          _lastStatus = status;
          if (status == 'approved' || status == 'pending') {
            WidgetsBinding.instance.addPostFrameCallback((_) => SyncEngine.instance.start());
          }
        }
        if (s == null) return const WelcomeScreen();
        return switch (status) {
          'approved' => const HomeScreen(),
          'pending' => const PendingScreen(),
          'disabled' => const BlockedScreen(),
          _ => const WelcomeScreen(),
        };
      },
    );
  }
}
