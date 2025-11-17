// lib/main.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Try to show a dialog in a safe way if navigator context is ready.
void _tryShowSafeDialog(String title, String message) {
  try {
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx != null) {
      scheduleMicrotask(() {
        try {
          showDialog(
            context: ctx,
            builder: (_) => AlertDialog(
              title: Text(title),
              content: Text(message, maxLines: 6, overflow: TextOverflow.ellipsis),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
              ],
            ),
          );
        } catch (e) {
          debugPrint('⚠️ [_tryShowSafeDialog] Failed to show dialog: $e');
        }
      });
    } else {
      debugPrint('ℹ️ [_tryShowSafeDialog] Navigator context not available — skipping dialog.');
    }
  } catch (e) {
    debugPrint('⚠️ [_tryShowSafeDialog] Unexpected error building dialog: $e');
  }
}

/// Top-level lifecycle / keep-alive widget: observes binding and keeps timers running.
/// This helps debugging and avoids "app finished" situations on web by keeping an active timer.
class TopLevelLifecycleHandler extends StatefulWidget {
  final Widget child;
  const TopLevelLifecycleHandler({required this.child, super.key});

  @override
  State<TopLevelLifecycleHandler> createState() => _TopLevelLifecycleHandlerState();
}

class _TopLevelLifecycleHandlerState extends State<TopLevelLifecycleHandler> with WidgetsBindingObserver {
  Timer? _keepAliveTimer;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🔔 [LIFECYCLE] TopLevelLifecycleHandler initialized. platform=${defaultTargetPlatform.name} kIsWeb=$kIsWeb');

    // Keep-alive: prevents Flutter Web isolate from terminating early.
    // Also useful as a heartbeat on other platforms for debugging.
    final keepAliveInterval = kIsWeb ? const Duration(minutes: 15) : const Duration(minutes: 60);
    _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
      debugPrint('⏱️ [KEEP-ALIVE] ping (platform=${kIsWeb ? "web" : "non-web"}) at ${DateTime.now().toIso8601String()}');
    });

    // Small health check more frequent (only logs) so you can see activity in console while debugging.
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('💓 [HEALTH] app heartbeat at ${DateTime.now().toIso8601String()}');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAliveTimer?.cancel();
    _healthTimer?.cancel();
    debugPrint('🔔 [LIFECYCLE] TopLevelLifecycleHandler disposed.');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🔁 [LIFECYCLE] AppLifecycleState changed -> $state at ${DateTime.now().toIso8601String()}');
    // On paused/resumed you can optionally run small tasks or resync data.
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [LIFECYCLE] App resumed — consider re-syncing networked resources.');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> main() async {
  // Use runZonedGuarded to capture async/unhandled errors but DO NOT rethrow or exit.
  await runZonedGuarded(() async {
    // Ensure Flutter binding is initialized exactly once.
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('🔰 [MAIN] WidgetsFlutterBinding.ensureInitialized() called.');
    debugPrint('🔰 [MAIN] APP STARTING -> Naslook (verbose console enabled)');

    // Framework-level error handling (log only — do not rethrow into zone to avoid exit).
    FlutterError.onError = (FlutterErrorDetails details) {
      // Present in debug console and log
      FlutterError.presentError(details);
      debugPrint('🔥 [FlutterError.onError] Framework exception: ${details.exceptionAsString()}');
      debugPrint('🔥 [FlutterError.onError] Framework stack:\n${details.stack ?? "no stack"}');
      debugPrint('🔥 [FlutterError.onError] NOTE: logged and swallowed (app will not crash from this handler).');
      // Optionally forward to analytics/crash services here.
    };
    debugPrint('🔰 [MAIN] FlutterError.onError assigned (logging only).');

    // Platform-level uncaught errors (native)
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('💥 [PlatformDispatcher.onError] Uncaught platform error: $error');
      debugPrint('💥 [PlatformDispatcher.onError] Stack:\n$stack');
      debugPrint('💥 [PlatformDispatcher.onError] Returning true to mark handled and prevent termination.');
      // Try to surface safe dialog to user if possible (best effort).
      _tryShowSafeDialog('Unexpected platform error', error.toString());
      return true; // important: prevents default crash behavior
    };
    debugPrint('🔰 [MAIN] PlatformDispatcher.instance.onError assigned.');

    // Initialize Firebase safely
    try {
      debugPrint('🚀 [MAIN] Initializing Firebase with DefaultFirebaseOptions...');
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      debugPrint('✅ [MAIN] Firebase.initializeApp() completed successfully.');
    } catch (e, st) {
      debugPrint('❌ [MAIN] Firebase.initializeApp() FAILED: $e');
      debugPrint('❌ [MAIN] Stack:\n$st');
      debugPrint('❌ [MAIN] Continuing without blocking — some Firebase features may not work.');
      // Optionally notify the user or send to crash reporting
    }

    // Log Firebase.app info
    try {
      final apps = Firebase.apps;
      debugPrint('ℹ️ [MAIN] Firebase.apps count = ${apps.length}');
      for (var app in apps) {
        debugPrint('ℹ️ [MAIN] Firebase app: name=${app.name}, projectId=${app.options.projectId}');
      }
    } catch (e, st) {
      debugPrint('⚠️ [MAIN] Could not list Firebase.apps: $e');
      debugPrint(st.toString());
    }

    // Attach a robust authStateChanges listener
    try {
      FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (user == null) {
          debugPrint('ℹ️ [AUTH] authStateChanges -> no user signed in.');
        } else {
          debugPrint('✅ [AUTH] authStateChanges -> signed in uid=${user.uid} email=${user.email}');
          debugPrint('🔎 [AUTH] fetching token claims & syncing profile (if needed)...');
        }
      }, onError: (err) {
        debugPrint('⚠️ [AUTH] authStateChanges listener error: $err');
        // do not rethrow
      });
      debugPrint('ℹ️ [AUTH] authStateChanges listener attached.');
    } catch (e, st) {
      debugPrint('⚠️ [AUTH] Could not attach authStateChanges listener: $e');
      debugPrint(st.toString());
    }

    // Extra helpful startup hints
    debugPrint('🔎 [MAIN] Debug hints:');
    debugPrint('  - If the app closes unexpectedly, inspect logs above for PlatformDispatcher or FlutterError entries.');
    debugPrint('  - If Firestore fails, check rules & project config.');
    debugPrint('  - If Storage/images fail, check Firebase Storage bucket rules & permissions.');
    debugPrint('  - Web: a periodic keep-alive prevents the JS isolate from being garbage-collected by the browser in some dev setups.');

    // Start the app with a top-level lifecycle handler (keeps timers & lifecycle logs)
    runApp(
      TopLevelLifecycleHandler(
        child: const MyApp(),
      ),
    );

    debugPrint('🔰 [MAIN] runApp() invoked. Application UI should appear shortly.');

    // For Web: ensure there's an obvious keep alive ping to prevent "Application finished."
    // For non-web: this acts as an optional background heartbeat (safe).
    final globalKeepAliveInterval = kIsWeb ? const Duration(minutes: 15) : const Duration(hours: 1);
    Timer.periodic(globalKeepAliveInterval, (_) {
      debugPrint('⏱️ [GLOBAL KEEP-ALIVE] ping at ${DateTime.now().toIso8601String()} (kIsWeb=$kIsWeb)');
    });
  }, (error, stack) {
    // Zone-wide error handler (BEST-EFFORT: log and show dialog; DO NOT rethrow).
    try {
      debugPrint('💥 [ZONE ERROR] Uncaught async error: $error');
      debugPrint('💥 [ZONE ERROR] Stack:\n$stack');
      // Try best-effort to show dialog to user
      _tryShowSafeDialog('Unexpected error', error.toString());
    } catch (e) {
      debugPrint('⚠️ [ZONE ERROR] Failed in zone error handler: $e');
    }
    // NOTE: we intentionally do NOT rethrow or call exit(1).
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('ℹ️ [APP] Building MaterialApp (MyApp.build) - navigatorKey present: ${navigatorKey != null}');
    debugPrint('ℹ️ [APP] Starting UI - verbose console enabled for debugging.');
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Naslook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}
