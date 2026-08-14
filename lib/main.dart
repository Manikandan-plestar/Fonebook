import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/session_store.dart';
import 'models/user_session.dart';
import 'screens/login_screen.dart';
import 'screens/add_profile_screen.dart';
import 'screens/app_shell.dart';

import 'services/payment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb) {
    PaymentService().initialize();
  }
  
  final store = SessionStore();
  final session = await store.read();
  runApp(FonebookApp(initialSession: session));
}

class FonebookApp extends StatelessWidget {
  final UserSession initialSession;
  const FonebookApp({super.key, required this.initialSession});

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (initialSession.email == null) {
      home = const LoginScreen();
    } else if (initialSession.phone == null) {
      home = AddProfileScreen(email: initialSession.email!);
    } else {
      home = const AppShell();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fone Book',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD7B41A),
          primary: const Color(0xFFD7B41A),
          secondary: const Color(0xFF5F6368),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'sans-serif',
      ),
      home: home,
    );
  }
}
