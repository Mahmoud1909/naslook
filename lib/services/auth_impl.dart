import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SignInException implements Exception {
  final String code;
  final String message;
  SignInException(this.code, this.message);

  @override
  String toString() => 'SignInException($code): $message';
}

Future<UserCredential?> signInWithGoogle() async {
  debugPrint("🚀 [FLOW] Starting Google Sign-In...");

  try {
    final FirebaseAuth auth = FirebaseAuth.instance;
    late UserCredential userCredential;

    if (kIsWeb) {
      debugPrint("[WEB] Detected Web platform. Using popup...");
      final GoogleAuthProvider provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      userCredential = await auth.signInWithPopup(provider);
    } else if (Platform.isAndroid || Platform.isIOS) {
      debugPrint("[MOBILE] Detected Mobile platform. Opening Google Sign-In...");

      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint("[MOBILE][INFO] User cancelled Google Sign-In.");
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      userCredential = await auth.signInWithCredential(credential);
    } else {
      throw SignInException(
        'platform_not_supported',
        'Google Sign-In is only supported on web and mobile.',
      );
    }

    debugPrint("✅ Google Sign-In complete for ${userCredential.user?.email}");
    return userCredential;
  } catch (e, st) {
    debugPrint("💥 [ERROR] Google Sign-In failed: $e");
    debugPrint(st.toString());
    if (e is SignInException) rethrow;
    throw SignInException('unexpected', e.toString());
  }
}

Future<UserCredential?> signInWithApple() async {
  debugPrint("🚀 [FLOW] Starting Apple Sign-In...");

  try {
    final FirebaseAuth auth = FirebaseAuth.instance;
    late UserCredential userCredential;

    if (kIsWeb) {
      debugPrint("[WEB] Using Firebase web popup for Apple sign-in.");
      final provider = OAuthProvider("apple.com");
      provider.addScope('email');
      provider.addScope('name');
      userCredential = await auth.signInWithPopup(provider);
    } else if (Platform.isIOS) {
      debugPrint("[iOS] Starting native Apple Sign-In...");

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      userCredential = await auth.signInWithCredential(oauthCredential);
    } else {
      throw SignInException(
        'platform_not_supported',
        'Apple Sign-In is only supported on iOS and Web.',
      );
    }

    debugPrint("✅ Apple Sign-In complete for ${userCredential.user?.email}");
    return userCredential;
  } catch (e, st) {
    debugPrint("💥 [ERROR] Apple Sign-In failed: $e");
    debugPrint(st.toString());
    if (e is SignInException) rethrow;
    throw SignInException('unexpected', e.toString());
  }
}
