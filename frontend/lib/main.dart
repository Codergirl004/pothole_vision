import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'providers/pothole_provider.dart';
import 'providers/calibration_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/user/user_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PotholeVisionApp());
}

class PotholeVisionApp extends StatelessWidget {
  const PotholeVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PotholeProvider()),
        ChangeNotifierProvider(create: (_) => CalibrationProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/user_dashboard': (_) => const UserDashboard(),
          '/admin_dashboard': (_) => const AdminDashboard(),
        },
      ),
    );
  }
}

/// Determines which screen to show based on authentication state and user role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.uninitialized:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading...'),
              ],
            ),
          ),
        );
      case AuthStatus.loading:
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        if (auth.isAdmin) {
          return const AdminDashboard();
        }
        return const UserDashboard();
    }
  }
}
