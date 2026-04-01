import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/screens/intro_screen.dart';
import 'package:flutter_app/screens/bus_search_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  User? user = FirebaseAuth.instance.currentUser;
  Widget initialScreen = const IntroScreen();

  if (user != null) {
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn != null && DateTime.now().difference(lastSignIn).inDays >= 2) {
      await FirebaseAuth.instance.signOut();
    } else {
      initialScreen = const BusSearchScreen();
    }
  }

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
        colorScheme: ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.blueAccent,
        ),
      ),
      home: initialScreen,
    );
  }
}
