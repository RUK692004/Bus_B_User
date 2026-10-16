import 'package:flutter/material.dart';
import 'package:flutter_app/screens/intro_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initial landing screen defaults to IntroScreen.
  // Session verification via FlutterSecureStorage will be wired in TICKET-202.
  const Widget initialScreen = IntroScreen();

  runApp(const MyApp(initialScreen: initialScreen));
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
        colorScheme: ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.blueAccent,
        ),
      ),
      home: initialScreen,
    );
  }
}
