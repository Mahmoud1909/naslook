// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚀 [MAIN] App starting - initializing Firebase...");
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("✅ [MAIN] Firebase initialized successfully.");
  } catch (e, st) {
    debugPrint("❌ [MAIN] Firebase initialization failed: $e");
    debugPrint(st.toString());
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    debugPrint("ℹ️ [APP] Building MaterialApp");
    return MaterialApp(
      title: 'Naslook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}
