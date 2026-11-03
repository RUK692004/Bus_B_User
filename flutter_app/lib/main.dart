import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/screens/bus_search_screen.dart';
import 'package:flutter_app/screens/login_screen.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Determines the starting screen by validating the stored JWT session.
Future<Widget> determineInitialScreen({AuthService? authService}) async {
  final service = authService ?? AuthService();

  try {
    final token = await service.getToken();
    if (token != null && token.trim().isNotEmpty) {
      try {
        await service.getCurrentUser();
        return const BusSearchScreen();
      } on ApiException catch (e) {
        debugPrint('[Startup] Stored session rejected: $e');
        if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
          await service.logout();
        }
        return const LoginScreen();
      } catch (e) {
        debugPrint('[Startup] Could not validate stored session: $e');
        return const LoginScreen();
      }
    }
  } catch (e) {
    debugPrint('[Startup] Could not read stored token: $e');
    return const LoginScreen();
  }

  return const LoginScreen();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Every page is black, so keep the status and navigation bars dark too.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final initialScreen = await determineInitialScreen();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: initialScreen,
    );
  }
}
