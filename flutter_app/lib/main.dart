import 'package:flutter/material.dart';
import 'package:flutter_app/screens/bus_search_screen.dart';
import 'package:flutter_app/screens/login_screen.dart';
import 'package:flutter_app/services/auth_service.dart';

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
        if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
          await service.logout();
        }
        return const LoginScreen();
      } catch (_) {
        return const LoginScreen();
      }
    }
  } catch (_) {
    return const LoginScreen();
  }

  return const LoginScreen();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.blueAccent,
        ),
      ),
      home: initialScreen,
    );
  }
}
