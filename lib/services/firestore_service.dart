// lib/services/firestore_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _usersRef => _firestore.collection('users');

  Future<bool> saveUserData(String uid, Map<String, dynamic> data,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final docRef = _usersRef.doc(uid);
    debugPrint('➡️ [FS] saveUserData() start for uid=$uid');

    // Defensive checks
    if (uid.trim().isEmpty) {
      debugPrint('❌ [FS] uid is empty — nothing to save.');
      return false;
    }

    try {
      // Check if doc exists (timeout gives fast failure on network issues)
      debugPrint('ℹ️ [FS] Checking existing document for uid=$uid');
      final snapshot = await docRef.get().timeout(timeout);
      final exists = snapshot.exists;
      debugPrint('ℹ️ [FS] Document exists: $exists');

      final payload = <String, dynamic>{}..addAll(data);
      if (!exists) payload['createdAt'] = FieldValue.serverTimestamp();
      payload['updatedAt'] = FieldValue.serverTimestamp();

      debugPrint('ℹ️ [FS] Writing to users/$uid with keys=${payload.keys.toList()}');
      await docRef.set(payload, SetOptions(merge: true)).timeout(timeout);
      debugPrint('✅ [FS] saveUserData success for uid=$uid');
      return true;
    } on FirebaseException catch (fe) {
      // Key actionable feedback for common firestore errors
      debugPrint('❌ [FS] FirebaseException saving uid=$uid -> code=${fe.code} message=${fe.message}');
      if (fe.code == 'permission-denied') {
        debugPrint('👉 [FS] Permission denied. ACTIONS:');
        debugPrint('  1) Open Firestore Rules in Firebase Console and allow authenticated writes to /users/{uid} OR set a safe rule for testing:');
        debugPrint(r'''     rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}''');
        debugPrint('  2) Make sure the app is authenticated (FirebaseAuth.instance.currentUser != null).');
        debugPrint('  3) Ensure you are using the correct Firebase project (DefaultFirebaseOptions.projectId).');
      } else if (fe.code == 'unavailable' || fe.code == 'deadline-exceeded') {
        debugPrint('👉 [FS] Network/backend unavailable. Check internet and Firebase status.');
      } else if (fe.code == 'not-found') {
        debugPrint('👉 [FS] Resource not found. Possibly Firestore not initialized in console for this project.');
      } else if (fe.code == 'unauthenticated') {
        debugPrint('👉 [FS] Unauthenticated. Make sure user is signed in before writing.');
      }
      return false;
    } on TimeoutException catch (te) {
      debugPrint('❌ [FS] Timeout while saving uid=$uid -> $te');
      return false;
    } catch (e, st) {
      debugPrint('❌ [FS] Unknown error saving uid=$uid -> $e');
      debugPrint(st.toString());
      return false;
    }
  }

  /// Convenience function: write to fixed user doc you requested
  Future<bool> saveToFixedUserDoc(Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 8)}) {
    const fixedUid = 'SF9d8UzdjoEATMsN923O';
    debugPrint('➡️ [FS] saveToFixedUserDoc() -> users/$fixedUid');
    return saveUserData(fixedUid, data, timeout: timeout);
  }

  Future<Map<String, dynamic>?> getUserData(String uid, {Duration timeout = const Duration(seconds: 6)}) async {
    final docRef = _usersRef.doc(uid);
    debugPrint('➡️ [FS] getUserData() uid=$uid');
    try {
      final snap = await docRef.get().timeout(timeout);
      if (!snap.exists) {
        debugPrint('ℹ️ [FS] getUserData: document not found uid=$uid');
        return null;
      }
      final data = snap.data() as Map<String, dynamic>;
      debugPrint('✅ [FS] getUserData success keys=${data.keys.toList()}');
      return data;
    } catch (e, st) {
      debugPrint('❌ [FS] getUserData error for uid=$uid -> $e');
      debugPrint(st.toString());
      return null;
    }
  }
}
