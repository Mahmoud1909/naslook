// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Make sure auth_impl.dart exports signInWithGoogle() and signInWithApple()
import 'package:naslook/services/auth_impl.dart';

import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _logoScale = Tween<double>(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _logoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() => _loading = v);
    if (v) {
      _logoController.repeat(reverse: true);
    } else {
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
      debugPrint("🔸 [SAVE] Parsed names: first='$firstName', last='$lastName'");

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
        'providerData': user.providerData.map((p) => {'providerId': p.providerId, 'uid': p.uid}).toList(),
        'last_signed_in': FieldValue.serverTimestamp(),
      };

      debugPrint("🔹 [SAVE] Upserting user document into Firestore (users/${user.uid}) ...");
      final users = FirebaseFirestore.instance.collection('users');

      // Attempt to write with a timeout. If it fails we continue (use local doc fallback)
      try {
        debugPrint("🟡 [SAVE] Calling set() on users/${user.uid} with timeout...");
        await users.doc(user.uid).set(doc, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
        debugPrint("🟢 [SAVE] set() completed successfully.");
      } on TimeoutException catch (te) {
        debugPrint("⚠️ [SAVE] Firestore set() timed out: $te");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network slow: saving profile timed out. Continuing...')));
        }
        // don't return — proceed using local doc as fallback
      } catch (e, st) {
        debugPrint("❌ [SAVE] Firestore set() failed: $e");
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save profile to Firestore. Continuing offline.')));
        }
        // continue — we'll use the local doc fallback
      }

      // try to fetch the saved doc (non-fatal if fails)
      debugPrint("🟡 [SAVE] Attempting to fetch Firestore document (with timeout)...");
      DocumentSnapshot<Map<String, dynamic>>? snapshot;
      try {
        snapshot = await users.doc(user.uid).get().timeout(const Duration(seconds: 5));
        debugPrint("🟢 [SAVE] Firestore document fetched successfully.");
      } on TimeoutException catch (te) {
        debugPrint("⚠️ [SAVE] Firestore get() timed out: $te");
        snapshot = null;
      } catch (e, st) {
        debugPrint("❌ [SAVE] Firestore get() failed: $e");
        debugPrint(st.toString());
        snapshot = null;
      }

      debugPrint("🟡 [SAVE] snapshot is ${snapshot == null ? 'NULL' : 'not null'}");

      final raw = snapshot?.data();
      debugPrint("🟡 [SAVE] raw (snapshot.data) is ${raw == null ? 'NULL' : 'present'}");

      final Map<String, dynamic> data = <String, dynamic>{};

      if (raw != null) {
        try {
          debugPrint("🟡 [SAVE] Converting raw map keys->strings and collecting values...");
          raw.forEach((k, v) => data[k.toString()] = v);
          debugPrint("🟢 [SAVE] Conversion done, entries=${data.length}");
        } catch (e, st) {
          debugPrint("⚠️ [SAVE] Warning converting snapshot.data(): $e");
          debugPrint(st.toString());
          data.addAll(doc);
        }
      } else {
        debugPrint("🟡 [SAVE] raw is null — using local doc as fallback");
        data.addAll(doc);
      }
      debugPrint("ℹ️ [SAVE] Prepared raw data (before sanitize): $data");

      // Create a sanitized safe map for passing into widgets (avoid complex objects)
      debugPrint("🟡 [SAVE] Sanitizing data to safe primitives...");
      final safeData = _toSafeMap(data);
      debugPrint("🟢 [SAVE] Safe user data prepared: $safeData");

      if (!mounted) {
        debugPrint("ℹ️ [SAVE] Widget not mounted, skipping navigation.");
        return false;
      }

      // STOP loading *before* navigation so overlay/loader won't block the new route
      debugPrint("🟡 [SAVE] Stopping loading before navigation...");
      _setLoading(false);

      // Navigate on next frame to be safe
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          debugPrint("➡️ [NAV] Navigating to HomeScreen for uid=${user.uid}");
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(userData: safeData)));
          debugPrint("🟢 [NAV] pushReplacement invoked.");
        } catch (e, st) {
          debugPrint("❌ [NAV] Navigation failed: $e");
          debugPrint(st.toString());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Navigation failed. Check logs.')));
          }
        }
      });

      return true;
    } catch (e, st) {
      debugPrint("❌ [SAVE] Error saving/fetching user in Firestore: $e");
      debugPrint(st.toString());
      if (mounted) {
        _setLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save user data. Check logs.')));
      }
      return false;
    }
  }


  Future<void> _handleGoogleSignIn() async {
    debugPrint("➡️ [LOGIN] Google sign-in initiation.");
    _setLoading(true);
    bool navigated = false;
    try {
      final cred = await signInWithGoogle(); // from auth_impl.dart
      if (cred == null) {
        debugPrint("ℹ️ [LOGIN] Google sign-in cancelled by user.");
        return;
      }
      final user = cred.user;
      if (user == null) {
        debugPrint("❌ [LOGIN] Google sign-in returned no user.");
        return;
      }
      debugPrint("✅ [LOGIN] Google signed in: uid=${user.uid}, email=${user.email}");
      navigated = await _saveUserToFirestoreAndNavigate(user);
      debugPrint("ℹ️ [LOGIN] _saveUserToFirestoreAndNavigate returned: $navigated");
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Google sign-in error: $e");
      debugPrint(st.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google sign-in failed.')));
    } finally {
      // only stop loader if still loading (if navigation happened we already stopped it)
      if (mounted && _loading) _setLoading(false);
      debugPrint("ℹ️ [LOGIN] handleGoogleSignIn finished, navigated=$navigated");
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
        return;
      }
      final user = cred.user;
      if (user == null) {
        debugPrint("❌ [LOGIN] Apple sign-in returned no user.");
        return;
      }
      debugPrint("✅ [LOGIN] Apple signed in: uid=${user.uid}, email=${user.email}");
      navigated = await _saveUserToFirestoreAndNavigate(user);
      debugPrint("ℹ️ [LOGIN] _saveUserToFirestoreAndNavigate returned: $navigated");
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Apple sign-in error: $e");
      debugPrint(st.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Apple sign-in failed.')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email and password required')));
      return;
    }
    _setLoading(true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      final user = cred.user;
      if (user == null) throw Exception('No user returned');
      debugPrint("✅ [LOGIN] Email sign-in success: ${user.uid}");
      await _saveUserToFirestoreAndNavigate(user);
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ [LOGIN] Email sign-in FirebaseAuthException: ${e.code} - ${e.message}");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign-in failed')));
    } catch (e, st) {
      debugPrint("❌ [LOGIN] Email sign-in error: $e");
      debugPrint(st.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email sign-in failed.')));
    } finally {
      _setLoading(false);
    }
  }

  Widget _socialButton({required String label, required Widget icon, required VoidCallback? onPressed, Color? bg}) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: bg == null ? BorderSide(color: Colors.grey.shade300) : null,
        ),
      ),
    );
  }

  Widget _googleButton() {
    const googleIconUrl = 'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg';
    return _socialButton(
      label: 'Continue with Google',
      icon: Image.network(googleIconUrl, width: 20, height: 20, errorBuilder: (c, e, s) => const Icon(Icons.g_mobiledata)),
      onPressed: _loading ? null : _handleGoogleSignIn,
    );
  }

  Widget _appleButton() {
    final showApple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS || kIsWeb;
    if (!showApple) return const SizedBox.shrink();
    return _socialButton(
      label: 'Continue with Apple',
      icon: const Icon(Icons.apple, size: 20),
      onPressed: _loading ? null : _handleAppleSignIn,
      bg: Colors.black87,
    );
  }

  InputDecoration _inputDecoration({required String hint, required Widget prefix}) {
    return InputDecoration(
      prefixIcon: prefix,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("ℹ️ [UI] Building Login screen (loading=$_loading)");
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final cardWidth = w < 500 ? w : (w < 900 ? 520.0 : 640.0);

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                          backgroundImage: const AssetImage('assets/images/logo.jpg'),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Welcome to Naslook', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Sign in to continue', style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 20),

                    // AnimatedCrossFade: show form or subtle loader overlay
                    AnimatedCrossFade(
                      firstChild: _buildForm(cardWidth),
                      secondChild: _buildLoadingCard(cardWidth),
                      crossFadeState: _loading ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))
              ]),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 12),
                  Text('Signing you in...', style: TextStyle(fontWeight: FontWeight.w600)),
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
            Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('OR', style: TextStyle(color: Colors.grey.shade500))), const Expanded(child: Divider())]),
            const SizedBox(height: 18),

            // Email
            Align(alignment: Alignment.centerLeft, child: const Text('Email', style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(hint: 'you@example.com', prefix: const Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 12),

            // Password
            Align(alignment: Alignment.centerLeft, child: const Text('Password', style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _inputDecoration(
                hint: '••••••••',
                prefix: const Icon(Icons.lock_outline),
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                      : const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Sign in', style: TextStyle(fontSize: 16))),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Forgot password (black)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : () => debugPrint("ℹ️ [LOGIN] Forgot password pressed"),
                child: const Text('Forgot password?', style: TextStyle(color: Colors.black)),
              ),
            ),

            const SizedBox(height: 10),

            // Signup row
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Need an account? ', style: TextStyle(color: Colors.grey.shade700)),
              GestureDetector(
                onTap: _loading ? null : () => debugPrint("ℹ️ [LOGIN] Sign up pressed"),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Sign up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),

          ],
        ),
      ),
    );
  }
}
