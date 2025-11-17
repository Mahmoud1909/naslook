// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:naslook/services/auth_impl.dart';

import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;

  // Fixed fallback document id you asked about
  static const String _fixedUserDocId = 'SF9d8UzdjoEATMsN923O';

  @override
  void initState() {
    super.initState();
    debugPrint("ℹ️ [LIFECYCLE] initState: LoginScreen initialized.");
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _logoScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // If we are on the web, check for a pending redirect result (completes redirect flows).
    if (kIsWeb) {
      debugPrint(
        "ℹ️ [WEB] initState: Checking for pending redirect result (getRedirectResult)...",
      );
      Future.microtask(() async {
        try {
          _setLoading(true);
          debugPrint(
            "ℹ️ [WEB] Calling FirebaseAuth.instance.getRedirectResult() to handle redirected sign-in (if any).",
          );
          final result = await FirebaseAuth.instance.getRedirectResult();
          if (result != null && result.user != null) {
            debugPrint(
              "✅ [WEB] getRedirectResult returned a user: ${result.user?.email}, uid=${result.user?.uid}",
            );
            final handled = await _saveUserToFirestoreAndNavigate(result.user!);
            debugPrint("ℹ️ [WEB] Redirect result handled: $handled");
          } else {
            debugPrint("ℹ️ [WEB] No redirect sign-in result available.");
          }
        } catch (e, st) {
          debugPrint("❌ [WEB] Error while handling redirect result: $e");
          debugPrint(st.toString());
        } finally {
          _setLoading(false);
        }
      });
    }
  }

  @override
  void dispose() {
    debugPrint("ℹ️ [LIFECYCLE] dispose: Cleaning up controllers.");
    _logoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() => _loading = v);
    if (v) {
      debugPrint("ℹ️ [UI] setLoading(true) -> start logo animation.");
      _logoController.repeat(reverse: true);
    } else {
      debugPrint("ℹ️ [UI] setLoading(false) -> reset logo animation.");
      _logoController.reset();
    }
  }

  /// Convert any complex firestore returned data into safe primitive-friendly map
  Map<String, dynamic> _toSafeMap(Map<String, dynamic> raw) {
    final Map<String, dynamic> safe = {};
    raw.forEach((key, value) {
      final k = key.toString();
      final v = value;
      if (v == null) {
        safe[k] = '';
      } else if (v is String || v is num || v is bool) {
        safe[k] = v;
      } else if (v is Timestamp) {
        try {
          safe[k] = v.toDate().toIso8601String();
        } catch (_) {
          safe[k] = v.toString();
        }
      } else if (v is DateTime) {
        safe[k] = v.toIso8601String();
      } else if (v is Map || v is List) {
        try {
          safe[k] = jsonEncode(v);
        } catch (_) {
          safe[k] = v.toString();
        }
      } else {
        // fallback: string representation
        safe[k] = v.toString();
      }
    });
    return safe;
  }

  /// Save user document to Firestore with detailed logging and fallback.
  /// Returns true if saved (either primary or fallback), false otherwise.
  Future<bool> _writeUserDoc(
    String docId,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final users = FirebaseFirestore.instance.collection('users');
    final docRef = users.doc(docId);
    debugPrint("➡️ [FS] _writeUserDoc() start -> users/$docId");

    try {
      // add timestamps server-side
      final Map<String, dynamic> toWrite = Map.from(payload);
      toWrite['updatedAt'] = FieldValue.serverTimestamp();
      // if doc doesn't exist, set createdAt too
      final existsSnap = await docRef.get().timeout(const Duration(seconds: 5));
      if (!existsSnap.exists) {
        debugPrint(
          "ℹ️ [FS] Document users/$docId does not exist yet. Will set createdAt.",
        );
        toWrite['createdAt'] = FieldValue.serverTimestamp();
      } else {
        debugPrint(
          "ℹ️ [FS] Document users/$docId already exists. Will merge updates.",
        );
      }

      debugPrint(
        "ℹ️ [FS] Writing keys=${toWrite.keys.toList()} to users/$docId ...",
      );
      await docRef.set(toWrite, SetOptions(merge: true)).timeout(timeout);
      debugPrint("✅ [FS] Write succeeded to users/$docId");
      return true;
    } on FirebaseException catch (fe) {
      debugPrint(
        "❌ [FS] FirebaseException writing to users/$docId -> code=${fe.code} message=${fe.message}",
      );
      // Provide actionable hints for common errors:
      if (fe.code == 'permission-denied') {
        debugPrint(
          "👉 [FS] permission-denied: your Firestore rules disallow this write.",
        );
        debugPrint(
          "👉 [FS] ACTION: In Firebase Console → Firestore → Rules, allow authenticated user write to /users/{userId} or use a safe test rule temporarily.",
        );
        debugPrint("👉 [FS] Example secure rule to use (only allow owner):");
        debugPrint(r"""rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}""");
        debugPrint(
          "👉 [FS] Example TEMPORARY test rule (UNSAFE - revert after testing):",
        );
        debugPrint(r"""rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}""");
      } else if (fe.code == 'not-found') {
        debugPrint(
          "👉 [FS] not-found: Firestore default database might not exist for this project. Go to Firebase Console → Firestore → Create database.",
        );
      } else if (fe.code == 'unauthenticated') {
        debugPrint(
          "👉 [FS] unauthenticated: user is not authenticated; ensure FirebaseAuth.currentUser is not null.",
        );
      } else if (fe.code == 'unavailable' || fe.code == 'deadline-exceeded') {
        debugPrint(
          "👉 [FS] backend unavailable or request timed out. Check network & Firebase status.",
        );
      }
      return false;
    } on TimeoutException catch (te) {
      debugPrint("❌ [FS] TimeoutException writing to users/$docId -> $te");
      return false;
    } catch (e, st) {
      debugPrint("❌ [FS] Unknown error writing to users/$docId -> $e");
      debugPrint(st.toString());
      return false;
    }
  }

  Future<bool> _saveUserToFirestoreAndNavigate(User user) async {
    debugPrint("➡️ [SAVE] Starting save & navigate for uid=${user.uid}");
    try {
      debugPrint("🔹 [SAVE] Getting ID token claims...");
      final idTokenResult = await user.getIdTokenResult();
      final claims = idTokenResult.claims ?? {};
      debugPrint("🔸 [SAVE] ID token claims: $claims");

      // parse name into first/last
      debugPrint("🔹 [SAVE] Parsing displayName...");
      String firstName = '';
      String lastName = '';
      final display = user.displayName ?? '';
      if (display.trim().isNotEmpty) {
        final parts = display.trim().split(RegExp(r'\s+'));
        firstName = parts.first;
        lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      debugPrint(
        "🔸 [SAVE] Parsed names: first='$firstName', last='$lastName'",
      );

      final doc = <String, dynamic>{
        'uid': user.uid,
        'email': user.email ?? '',
        'first_name': firstName,
        'last_name': lastName,
        'displayName': display,
        'photo_url': user.photoURL ?? '',
        'phone': user.phoneNumber ?? claims['phone'] ?? '',
        'age': claims['age']?.toString() ?? '',
        'gender': claims['gender']?.toString() ?? '',
        'providerData': user.providerData
            .map((p) => {'providerId': p.providerId, 'uid': p.uid})
            .toList(),
        // last_signed_in will be set server-side as 'updatedAt'
      };

      debugPrint(
        "🔹 [SAVE] Upserting user document into Firestore (users/${user.uid}) ...",
      );

      // Primary attempt: write to /users/{uid}
      final primaryOk = await _writeUserDoc(user.uid, doc);
      if (!primaryOk) {
        debugPrint(
          "⚠️ [SAVE] Primary write to users/${user.uid} failed. Trying fallback to users/$_fixedUserDocId ...",
        );
        final fallbackOk = await _writeUserDoc(_fixedUserDocId, doc);
        if (!fallbackOk) {
          debugPrint(
            "🔴 [SAVE] Fallback write also failed. Likely Firestore rules or project configuration issue.",
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Failed to save profile to Firestore. Check console for rules/project config.',
                ),
              ),
            );
          }
          // still proceed using local doc for navigation
        } else {
          debugPrint(
            "🟡 [SAVE] Fallback write succeeded to users/$_fixedUserDocId.",
          );
        }
      } else {
        debugPrint("🟢 [SAVE] Primary write succeeded to users/${user.uid}.");
      }

      // Try to fetch the saved doc (non-fatal if fails)
      debugPrint(
        "🟡 [SAVE] Attempting to fetch Firestore document (with timeout) for users/${user.uid} ...",
      );
      Map<String, dynamic>? fetchedData;
      try {
        /*FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists) {
            print('User data: ${snapshot.data()}');
          } else {
            print('Document does not exist');
          }
        });*/
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        //.timeout(const Duration(seconds: 5));
        if (snap.exists) {
          fetchedData = snap.data() as Map<String, dynamic>?;
          debugPrint(
            "🟢 [SAVE] Firestore document fetched: keys=${fetchedData?.keys.toList()}",
          );
        } else {
          debugPrint(
            "ℹ️ [SAVE] Firestore document users/${user.uid} not found after write.",
          );
        }
      } on TimeoutException catch (te) {
        debugPrint("⚠️ [SAVE] Firestore get() timed out: $te");
        fetchedData = null;
      } catch (e, st) {
        debugPrint("❌ [SAVE] Firestore get() failed: $e");
        debugPrint(st.toString());
        fetchedData = null;
      }

      final Map<String, dynamic> dataForUi = {};
      if (fetchedData != null) {
        try {
          fetchedData.forEach((k, v) => dataForUi[k.toString()] = v);
        } catch (e, st) {
          debugPrint("⚠️ [SAVE] Error converting fetched data: $e");
          debugPrint(st.toString());
          dataForUi.addAll(doc);
        }
      } else {
        debugPrint("🟡 [SAVE] Using local doc as fallback for UI.");
        dataForUi.addAll(doc);
      }

      debugPrint("ℹ️ [SAVE] Prepared raw data (before sanitize): $dataForUi");

      // Sanitize
      debugPrint("🟡 [SAVE] Sanitizing data to safe primitives...");
      final safeData = _toSafeMap(dataForUi);
      debugPrint("🟢 [SAVE] Safe user data prepared: $safeData");

      if (!mounted) {
        debugPrint("ℹ️ [SAVE] Widget not mounted, skipping navigation.");
        return false;
      }

      debugPrint("🟡 [SAVE] Stopping loading before navigation...");
      _setLoading(false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          debugPrint("➡️ [NAV] Navigating to HomeScreen for uid=${user.uid}");
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(userData: safeData)),
          );
          debugPrint("🟢 [NAV] pushReplacement invoked.");
        } catch (e, st) {
          debugPrint("❌ [NAV] Navigation failed: $e");
          debugPrint(st.toString());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Navigation failed. Check logs.')),
            );
          }
        }
      });

      return true;
    } catch (e, st) {
      debugPrint("❌ [SAVE] Error saving/fetching user in Firestore: $e");
      debugPrint(st.toString());
      if (mounted) {
        _setLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save user data. Check logs.'),
          ),
        );
      }
      return false;
    }
  }

  /// GOOGLE SIGN-IN HANDLER
  Future<void> _handleGoogleSignIn() async {
    debugPrint("➡️ [LOGIN] Google sign-in initiation.");
    _setLoading(true);
    bool navigated = false;
    try {
      UserCredential? cred;

      if (kIsWeb) {
        debugPrint(
          "[WEB] Detected web platform. Attempting signInWithPopup(GoogleAuthProvider()).",
        );
        final provider = GoogleAuthProvider();
        try {
          debugPrint(
            "[WEB] Calling FirebaseAuth.instance.signInWithPopup(provider) now...",
          );
          cred = await FirebaseAuth.instance.signInWithPopup(provider);
          debugPrint(
            "[WEB] signInWithPopup returned credential. user=${cred.user?.email}, uid=${cred.user?.uid}",
          );
        } on FirebaseAuthException catch (e, st) {
          debugPrint(
            "[WEB][ERROR] Firebase web signInWithPopup failed: ${e.code} - ${e.message}",
          );
          debugPrint(st.toString());
          final code = (e.code ?? '').toString();
          if (code.contains('popup-closed-by-user') ||
              code.contains('popup-blocked') ||
              code.contains('auth/popup-blocked')) {
            debugPrint(
              "[WEB] Popup was closed or blocked. Falling back to signInWithRedirect()...",
            );
            try {
              await FirebaseAuth.instance.signInWithRedirect(provider);
              debugPrint(
                "[WEB] signInWithRedirect invoked; returning to allow redirect flow to complete.",
              );
              return;
            } catch (re, rst) {
              debugPrint("❌ [WEB][ERROR] signInWithRedirect failed: $re");
              debugPrint(rst.toString());
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Web redirect sign-in failed. Check console.',
                    ),
                  ),
                );
              return;
            }
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Web Google sign-in failed. Check console.'),
                ),
              );
            return;
          }
        } catch (e, st) {
          debugPrint(
            "[WEB][ERROR] Unexpected error during web Google sign-in: $e",
          );
          debugPrint(st.toString());
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unexpected web sign-in error.')),
            );
          return;
        }
      } else {
        debugPrint(
          "[PLATFORM] Non-web detected. Calling signInWithGoogle() from auth_impl.dart",
        );
        try {
          cred = await signInWithGoogle();
          debugPrint(
            "[PLATFORM] signInWithGoogle() returned: ${cred != null ? 'credential present' : 'null credential'}",
          );
        } catch (e, st) {
          debugPrint("[PLATFORM][ERROR] signInWithGoogle() threw: $e");
          debugPrint(st.toString());
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google sign-in failed.')),
            );
          return;
        }
      }

      if (cred == null) {
        debugPrint(
          "ℹ️ [LOGIN] Google sign-in cancelled by user or returned null credential.",
        );
        _setLoading(false);
        return;
      }

      final user = cred.user;
      if (user == null) {
        debugPrint("❌ [LOGIN] Google sign-in returned no user.");
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google sign-in failed: no user returned.'),
            ),
          );
        _setLoading(false);
        return;
      }

      debugPrint(
        "✅ [LOGIN] Google signed in: uid=${user.uid}, email=${user.email}",
      );
      navigated = await _saveUserToFirestoreAndNavigate(user);
      debugPrint(
        "ℹ️ [LOGIN] _saveUserToFirestoreAndNavigate returned: $navigated",
      );
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Google sign-in error (outer): $e");
      debugPrint(st.toString());
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in failed (see logs).')),
        );
    } finally {
      if (mounted && _loading) {
        _setLoading(false);
      }
      debugPrint(
        "ℹ️ [LOGIN] handleGoogleSignIn finished, navigated=$navigated",
      );
    }
  }

  Future<void> _handleAppleSignIn() async {
    debugPrint("➡️ [LOGIN] Apple sign-in initiation.");
    _setLoading(true);
    bool navigated = false;
    try {
      final cred = await signInWithApple(); // from auth_impl.dart
      if (cred == null) {
        debugPrint("ℹ️ [LOGIN] Apple sign-in cancelled or not available.");
        _setLoading(false);
        return;
      }
      final user = cred.user;
      if (user == null) {
        debugPrint("❌ [LOGIN] Apple sign-in returned no user.");
        _setLoading(false);
        return;
      }
      debugPrint(
        "✅ [LOGIN] Apple signed in: uid=${user.uid}, email=${user.email}",
      );
      navigated = await _saveUserToFirestoreAndNavigate(user);
      debugPrint(
        "ℹ️ [LOGIN] _saveUserToFirestoreAndNavigate returned: $navigated",
      );
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Apple sign-in error: $e");
      debugPrint(st.toString());
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Apple sign-in failed.')));
    } finally {
      if (mounted && _loading) _setLoading(false);
      debugPrint("ℹ️ [LOGIN] handleAppleSignIn finished, navigated=$navigated");
    }
  }

  Future<void> _handleEmailSignIn() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    debugPrint("➡️ [LOGIN] Email sign-in started for: $email");
    if (email.isEmpty || pass.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email and password required')),
        );
      return;
    }
    _setLoading(true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final user = cred.user;
      if (user == null) throw Exception('No user returned');
      debugPrint("✅ [LOGIN] Email sign-in success: ${user.uid}");
      await _saveUserToFirestoreAndNavigate(user);
    } on FirebaseAuthException catch (e) {
      debugPrint(
        "❌ [LOGIN] Email sign-in FirebaseAuthException: ${e.code} - ${e.message}",
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign-in failed')));
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Email sign-in error: $e");
      debugPrint(st.toString());
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email sign-in failed.')));
    } finally {
      _setLoading(false);
    }
  }

  Widget _socialButton({
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
    Color? bg,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg ?? Colors.white,
          foregroundColor: bg != null ? Colors.white : Colors.black87,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: bg == null ? BorderSide(color: Colors.grey.shade300) : null,
        ),
      ),
    );
  }

  Widget _googleButton() {
    const googleIconUrl =
        'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg';
    return _socialButton(
      label: 'Continue with Google',
      icon: Image.network(
        googleIconUrl,
        width: 20,
        height: 20,
        errorBuilder: (c, e, s) => const Icon(Icons.g_mobiledata),
      ),
      onPressed: _loading ? null : _handleGoogleSignIn,
    );
  }

  Widget _appleButton() {
    final showApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        kIsWeb;
    if (!showApple) return const SizedBox.shrink();
    return _socialButton(
      label: 'Continue with Apple',
      icon: const Icon(Icons.apple, size: 20),
      onPressed: _loading ? null : _handleAppleSignIn,
      bg: Colors.black87,
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required Widget prefix,
  }) {
    return InputDecoration(
      prefixIcon: prefix,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("ℹ️ [UI] Building Login screen (loading=$_loading)");
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cardWidth = w < 500 ? w : (w < 900 ? 520.0 : 640.0);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Animated logo with Hero
                      ScaleTransition(
                        scale: _logoScale,
                        child: Hero(
                          tag: 'app-logo-hero',
                          child: CircleAvatar(
                            radius: (w < 350) ? 36 : 48,
                            backgroundImage: const AssetImage(
                              'assets/images/logo.jpg',
                            ),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Welcome to Naslook',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to continue',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),

                      // AnimatedCrossFade: show form or subtle loader overlay
                      AnimatedCrossFade(
                        firstChild: _buildForm(cardWidth),
                        secondChild: _buildLoadingCard(cardWidth),
                        crossFadeState: _loading
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingCard(double w) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      child: SizedBox(
        width: w,
        child: Column(
          children: [
            // Keep social buttons visible during loading but disabled
            Opacity(opacity: 0.6, child: _googleButton()),
            const SizedBox(height: 12),
            Opacity(opacity: 0.6, child: _appleButton()),
            const SizedBox(height: 18),
            const SizedBox(height: 8),
            const SizedBox(height: 18),
            // central loader
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 12),
                  Text(
                    'Signing you in...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(double cardWidth) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: Colors.black.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          children: [
            _googleButton(),
            const SizedBox(height: 12),
            _appleButton(),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'OR',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 18),

            // Email
            Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'Email',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(
                hint: 'you@example.com',
                prefix: const Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Password
            Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'Password',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration:
                  _inputDecoration(
                    hint: '••••••••',
                    prefix: const Icon(Icons.lock_outline),
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
            ),
            const SizedBox(height: 16),

            // Sign in button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _handleEmailSignIn,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _loading
                      ? const SizedBox.shrink()
                      : const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Sign in',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Forgot password (black)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => debugPrint("ℹ️ [LOGIN] Forgot password pressed"),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Signup row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Need an account? ',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                GestureDetector(
                  onTap: _loading
                      ? null
                      : () => debugPrint("ℹ️ [LOGIN] Sign up pressed"),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Sign up',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
//https://chatgpt.com/c/6918b06d-2df8-8327-81d4-f102f6ec8d55