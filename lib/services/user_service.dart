// lib/services/user_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

class UserService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserService() {
    debugPrint('🔧 [UserService] Initialized -> Using default Firestore instance.');
    if (kDebugMode) debugPrint('🔎 [UserService] Debug mode ON - verbose logs enabled.');
  }

  String? get currentUid => _auth.currentUser?.uid;

  Map<String, DocumentReference<Map<String, dynamic>>> _docRefsForUid(String uid) {
    return {'users': _fs.collection('users').doc(uid), 'usersL': _fs.collection('usersL').doc(uid)};
  }

  /*Map<String, dynamic> _normalizeDocData(String docId, Map<String, dynamic> raw) {
    debugPrint('ℹ️ [UserService] Normalizing doc ($docId). Raw keys: ${raw.keys.toList()}');
    final r = Map<String, dynamic>.from(raw);
    final out = <String, dynamic>{};

    out['uid'] = (r['uid'] is String && (r['uid'] as String).trim().isNotEmpty) ? r['uid'] as String : docId;

    // name
    String name = '';
    if (r['name'] is String && (r['name'] as String).trim().isNotEmpty) {
      name = (r['name'] as String).trim();
    } else if (r['displayName'] is String && (r['displayName'] as String).trim().isNotEmpty) {
      name = (r['displayName'] as String).trim();
    } else {
      final first = (r['first_name'] as String?)?.trim() ?? '';
      final last = (r['last_name'] as String?)?.trim() ?? '';
      if (first.isNotEmpty || last.isNotEmpty) name = (first + (last.isNotEmpty ? ' $last' : '')).trim();
    }
    out['name'] = name;

    // images
    final profileCandidates = <String?>[
      (r['profileImageUrl'] as String?)?.trim(),
      (r['profile_image_url'] as String?)?.trim(),
      (r['photo_url'] as String?)?.trim(),
      (r['photoUrl'] as String?)?.trim(),
      (r['photo'] as String?)?.trim(),
    ];
    out['profileImageUrl'] = profileCandidates.firstWhere((c) => c != null && c.isNotEmpty, orElse: () => '') ?? '';

    final bgCandidates = <String?>[
      (r['backgroundImageUrl'] as String?)?.trim(),
      (r['background_image'] as String?)?.trim(),
      (r['background'] as String?)?.trim(),
    ];
    out['backgroundImageUrl'] = bgCandidates.firstWhere((c) => c != null && c.isNotEmpty, orElse: () => '') ?? '';

    out['jobTitle'] = (r['jobTitle'] as String?)?.trim() ?? (r['title'] as String?)?.trim() ?? (r['role'] as String?)?.trim() ?? '';
    out['displayId'] = (r['displayId'] as String?)?.trim() ?? (r['display_id'] as String?)?.trim() ?? out['uid'];

    out['email'] = (r['email'] as String?)?.trim() ?? '';
    out['phone'] = (r['phone'] as String?)?.trim() ?? '';
    out['bio'] = (r['bio'] as String?)?.trim() ?? (r['about'] as String?)?.trim() ?? '';

    // skills
    final skillsRaw = r['skills'];
    List<String> skills = [];
    try {
      if (skillsRaw is List) {
        skills = skillsRaw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
      } else if (skillsRaw is String) {
        final s = skillsRaw.trim();
        if (s.startsWith('[') && s.endsWith(']')) {
          final decoded = jsonDecode(s);
          if (decoded is List) skills = decoded.map((e) => e?.toString() ?? '').where((x) => x.isNotEmpty).cast<String>().toList();
        } else if (s.contains(',')) {
          skills = s.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        } else if (s.isNotEmpty) {
          skills = [s];
        }
      }
    } catch (e, st) {
      debugPrint('⚠️ [UserService] skills normalization failed: $e');
      debugPrint(st.toString());
      skills = [];
    }
    out['skills'] = skills;

    // providerData
    try {
      if (r['providerData'] is List) {
        out['providerData'] = (r['providerData'] as List).map((e) => e is Map ? Map<String, dynamic>.from(e) : {'raw': e.toString()}).toList();
      } else if (r['providerData'] != null) {
        out['providerData'] = [r['providerData'].toString()];
      } else {
        out['providerData'] = [];
      }
    } catch (_) {
      out['providerData'] = [];
    }

    // createdAt/updatedAt: keep as Timestamp when possible
    dynamic created = r['createdAt'] ?? r['created_at'];
    dynamic updated = r['updatedAt'] ?? r['updated_at'];
    Timestamp? createdTs;
    Timestamp? updatedTs;

    if (created is Timestamp) {
      createdTs = created;
      out['_raw_createdAt'] = created;
    } else if (created is DateTime) {
      createdTs = Timestamp.fromDate(created);
      out['_raw_createdAt'] = created;
    } else if (created is String) {
      final dt = DateTime.tryParse(created);
      if (dt != null) {
        createdTs = Timestamp.fromDate(dt);
        out['_raw_createdAt'] = created;
      } else {
        out['_raw_createdAt'] = created;
      }
    } else {
      out['_raw_createdAt'] = created;
    }

    if (updated is Timestamp) {
      updatedTs = updated;
      out['_raw_updatedAt'] = updated;
    } else if (updated is DateTime) {
      updatedTs = Timestamp.fromDate(updated);
      out['_raw_updatedAt'] = updated;
    } else if (updated is String) {
      final dt = DateTime.tryParse(updated);
      if (dt != null) {
        updatedTs = Timestamp.fromDate(dt);
        out['_raw_updatedAt'] = updated;
      } else {
        out['_raw_updatedAt'] = updated;
      }
    } else {
      out['_raw_updatedAt'] = updated;
    }

    out['createdAt'] = createdTs;
    out['updatedAt'] = updatedTs;

    out['_raw'] = r;
    out['age'] = (r['age'] is String) ? r['age'] : (r['age']?.toString() ?? '');
    out['gender'] = (r['gender'] as String?)?.trim() ?? '';

    debugPrint('✅ [UserService] Normalization complete for doc $docId -> canonical keys: ${out.keys.toList()}');
    return out;
  }*/
  Map<String, dynamic> _normalizeDocData(String docId, Map<String, dynamic> raw) {
    debugPrint('ℹ️ [UserService] Normalizing doc ($docId). Raw keys: ${raw.keys.toList()}');
    final r = Map<String, dynamic>.from(raw);
    final out = <String, dynamic>{};

    out['uid'] = (r['uid'] is String && (r['uid'] as String).trim().isNotEmpty) ? r['uid'] as String : docId;

    // name
    String name = '';
    if (r['name'] is String && (r['name'] as String).trim().isNotEmpty) {
      name = (r['name'] as String).trim();
    } else if (r['displayName'] is String && (r['displayName'] as String).trim().isNotEmpty) {
      name = (r['displayName'] as String).trim();
    } else {
      final first = (r['first_name'] as String?)?.trim() ?? '';
      final last = (r['last_name'] as String?)?.trim() ?? '';
      if (first.isNotEmpty || last.isNotEmpty) name = (first + (last.isNotEmpty ? ' $last' : '')).trim();
    }
    out['name'] = name;

    // images
    final profileCandidates = <String?>[
      (r['profileImageUrl'] as String?)?.trim(),
      (r['profile_image_url'] as String?)?.trim(),
      (r['photo_url'] as String?)?.trim(),
      (r['photoUrl'] as String?)?.trim(),
      (r['photo'] as String?)?.trim(),
    ];
    out['profileImageUrl'] = profileCandidates.firstWhere((c) => c != null && c.isNotEmpty, orElse: () => '') ?? '';

    final bgCandidates = <String?>[
      (r['backgroundImageUrl'] as String?)?.trim(),
      (r['background_image'] as String?)?.trim(),
      (r['background'] as String?)?.trim(),
    ];
    out['backgroundImageUrl'] = bgCandidates.firstWhere((c) => c != null && c.isNotEmpty, orElse: () => '') ?? '';

    out['jobTitle'] = (r['jobTitle'] as String?)?.trim() ?? (r['title'] as String?)?.trim() ?? (r['role'] as String?)?.trim() ?? '';
    out['displayId'] = (r['displayId'] as String?)?.trim() ?? (r['display_id'] as String?)?.trim() ?? out['uid'];

    out['email'] = (r['email'] as String?)?.trim() ?? '';
    out['phone'] = (r['phone'] as String?)?.trim() ?? '';
    out['bio'] = (r['bio'] as String?)?.trim() ?? (r['about'] as String?)?.trim() ?? '';

    // <<< NEW: City & Club normalization (support common alternate keys) >>>
    out['city'] = (r['city'] as String?)?.trim() ??
        (r['location'] as String?)?.trim() ??
        (r['hometown'] as String?)?.trim() ??
        (r['town'] as String?)?.trim() ??
        '';
    out['club'] = (r['club'] as String?)?.trim() ??
        (r['favorite_club'] as String?)?.trim() ??
        (r['favClub'] as String?)?.trim() ??
        (r['favourite_club'] as String?)?.trim() ??
        '';

    // skills
    final skillsRaw = r['skills'];
    List<String> skills = [];
    try {
      if (skillsRaw is List) {
        skills = skillsRaw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
      } else if (skillsRaw is String) {
        final s = skillsRaw.trim();
        if (s.startsWith('[') && s.endsWith(']')) {
          final decoded = jsonDecode(s);
          if (decoded is List) skills = decoded.map((e) => e?.toString() ?? '').where((x) => x.isNotEmpty).cast<String>().toList();
        } else if (s.contains(',')) {
          skills = s.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        } else if (s.isNotEmpty) {
          skills = [s];
        }
      }
    } catch (e, st) {
      debugPrint('⚠️ [UserService] skills normalization failed: $e');
      debugPrint(st.toString());
      skills = [];
    }
    out['skills'] = skills;

    // providerData
    try {
      if (r['providerData'] is List) {
        out['providerData'] = (r['providerData'] as List).map((e) => e is Map ? Map<String, dynamic>.from(e) : {'raw': e.toString()}).toList();
      } else if (r['providerData'] != null) {
        out['providerData'] = [r['providerData'].toString()];
      } else {
        out['providerData'] = [];
      }
    } catch (_) {
      out['providerData'] = [];
    }

    // createdAt/updatedAt: keep as Timestamp when possible
    dynamic created = r['createdAt'] ?? r['created_at'];
    dynamic updated = r['updatedAt'] ?? r['updated_at'];
    Timestamp? createdTs;
    Timestamp? updatedTs;

    if (created is Timestamp) {
      createdTs = created;
      out['_raw_createdAt'] = created;
    } else if (created is DateTime) {
      createdTs = Timestamp.fromDate(created);
      out['_raw_createdAt'] = created;
    } else if (created is String) {
      final dt = DateTime.tryParse(created);
      if (dt != null) {
        createdTs = Timestamp.fromDate(dt);
        out['_raw_createdAt'] = created;
      } else {
        out['_raw_createdAt'] = created;
      }
    } else {
      out['_raw_createdAt'] = created;
    }

    if (updated is Timestamp) {
      updatedTs = updated;
      out['_raw_updatedAt'] = updated;
    } else if (updated is DateTime) {
      updatedTs = Timestamp.fromDate(updated);
      out['_raw_updatedAt'] = updated;
    } else if (updated is String) {
      final dt = DateTime.tryParse(updated);
      if (dt != null) {
        updatedTs = Timestamp.fromDate(dt);
        out['_raw_updatedAt'] = updated;
      } else {
        out['_raw_updatedAt'] = updated;
      }
    } else {
      out['_raw_updatedAt'] = updated;
    }

    out['createdAt'] = createdTs;
    out['updatedAt'] = updatedTs;

    out['_raw'] = r;
    out['age'] = (r['age'] is String) ? r['age'] : (r['age']?.toString() ?? '');
    out['gender'] = (r['gender'] as String?)?.trim() ?? '';

    debugPrint('✅ [UserService] Normalization complete for doc $docId -> canonical keys: ${out.keys.toList()}');
    return out;
  }

  Stream<UserProfile?> streamUserProfile(String uid) {
    debugPrint('➡️ [UserService] streamUserProfile() - subscribe uid=$uid');
    final refs = _docRefsForUid(uid);
    final controller = StreamController<UserProfile?>.broadcast();

    controller.onListen = () {
      debugPrint('ℹ️ [UserService] streamUserProfile() - onListen: attaching listeners for uid=$uid');
      final latest = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final subs = <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

      void recomputeAndEmit() {
        try {
          DocumentSnapshot<Map<String, dynamic>>? chosen;
          if (latest.containsKey('users') && latest['users']!.exists) {
            chosen = latest['users'];
            debugPrint('ℹ️ [UserService] Chosen source: users (exists).');
          } else if (latest.containsKey('usersL') && latest['usersL']!.exists) {
            chosen = latest['usersL'];
            debugPrint('ℹ️ [UserService] Chosen source: usersL (exists).');
          } else {
            debugPrint('ℹ️ [UserService] No existing doc found in users or usersL for uid=$uid -> emitting null.');
            controller.add(null);
            return;
          }

          final raw = chosen!.data() ?? <String, dynamic>{};
          try {
            final rawJson = jsonEncode(raw);
            final truncated = rawJson.length > 800 ? rawJson.substring(0, 800) + '... (truncated)' : rawJson;
            debugPrint('🔔 snapshot raw (truncated) for uid=$uid: $truncated');
          } catch (_) {
            debugPrint('🔔 snapshot raw (non-json) for uid=$uid: ${raw.toString()}');
          }

          final normalized = _normalizeDocData(chosen.id, Map<String, dynamic>.from(raw));
          try {
            final profile = UserProfile.fromMap(normalized);
            debugPrint('✅ emitting profile uid=${profile.uid}');
            controller.add(profile);
          } catch (e, st) {
            debugPrint('❌ [UserService] UserProfile.fromMap failed for uid=$uid: $e');
            debugPrint(st.toString());
            controller.add(null);
          }
        } catch (e, st) {
          debugPrint('❌ [UserService] recomputeAndEmit() error: $e');
          debugPrint(st.toString());
          controller.add(null);
        }
      }

      refs.forEach((key, ref) {
        final sub = ref.snapshots().listen((snap) {
          debugPrint('🔔 update from $key for uid=$uid -> exists=${snap.exists}');
          latest[key] = snap;
          recomputeAndEmit();
        }, onError: (err, st) {
          debugPrint('⚠️ [UserService] snapshot error on $key for uid=$uid -> $err');
          debugPrint(st.toString());
        });
        subs.add(sub);
      });

      controller.onCancel = () async {
        debugPrint('ℹ️ [UserService] streamUserProfile() onCancel -> cancelling ${subs.length} subs for uid=$uid');
        for (final s in subs) await s.cancel();
      };
    };

    return controller.stream;
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    debugPrint('➡️ [UserService] getUserProfile() - uid=$uid (single-read)');
    final refs = _docRefsForUid(uid);

    for (final key in ['users', 'usersL']) {
      final ref = refs[key];
      if (ref == null) continue;
      try {
        debugPrint('ℹ️ [UserService] getUserProfile() - checking $key...');
        final snap = await ref.get();
        debugPrint('ℹ️ [UserService] Document $key/${snap.id} exists=${snap.exists}');
        if (snap.exists) {
          final raw = snap.data() ?? <String, dynamic>{};
          final normalized = _normalizeDocData(snap.id, Map<String, dynamic>.from(raw));
          try {
            final profile = UserProfile.fromMap(normalized);
            debugPrint('✅ [UserService] Found profile in $key uid=${profile.uid}');
            return profile;
          } catch (e, st) {
            debugPrint('❌ [UserService] fromMap failed for $key: $e');
            debugPrint(st.toString());
            return null;
          }
        }
      } catch (e, st) {
        debugPrint('⚠️ [UserService] getUserProfile() error reading $key: $e');
        debugPrint(st.toString());
      }
    }

    debugPrint('ℹ️ [UserService] getUserProfile() - not found in users or usersL for uid=$uid');
    return null;
  }

  Future<void> updateUserFields(String uid, Map<String, dynamic> fields) async {
    debugPrint('➡️ [UserService] updateUserFields() uid=$uid keys=${fields.keys.toList()}');
    final ref = _fs.collection('users').doc(uid);
    final updates = Map<String, dynamic>.from(fields);
    updates['updatedAt'] = FieldValue.serverTimestamp();
    try {
      await ref.set(updates, SetOptions(merge: true));
      debugPrint('✅ [UserService] updateUserFields() success -> users/$uid');
    } catch (e, st) {
      debugPrint('❌ [UserService] updateUserFields() failed: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  Future<String> uploadUserImage({
    required String uid,
    File? file,
    required String pathType,
    Uint8List? bytes,
    String? contentType,
  }) async {
    debugPrint('➡️ [UserService] uploadUserImage() uid=$uid pathType=$pathType');
    final ext = pathType.contains('.') ? '' : '.jpg';
    final storagePath = 'userProfiles/$uid/$pathType$ext';
    final ref = _storage.ref().child(storagePath);

    try {
      UploadTask uploadTask;
      final metadata = SettableMetadata(contentType: contentType ?? 'image/jpeg');
      if (file != null) {
        debugPrint('ℹ️ [UserService] uploadUserImage -> uploading File to $storagePath');
        uploadTask = ref.putFile(file, metadata);
      } else if (bytes != null) {
        debugPrint('ℹ️ [UserService] uploadUserImage -> uploading bytes (${bytes.length} bytes) to $storagePath');
        uploadTask = ref.putData(bytes, metadata);
      } else {
        throw ArgumentError('Either file or bytes must be provided for uploadUserImage.');
      }

      final snap = await uploadTask;
      final url = await snap.ref.getDownloadURL();
      debugPrint('✅ [UserService] uploadUserImage complete -> $url');
      return url;
    } catch (e, st) {
      debugPrint('❌ [UserService] uploadUserImage failed: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  Future<void> deleteUserImage(String uid, String pathType) async {
    final storagePath = 'userProfiles/$uid/$pathType.jpg';
    final ref = _storage.ref().child(storagePath);
    try {
      await ref.delete();
      debugPrint('✅ [UserService] deleteUserImage deleted $storagePath');
    } catch (e) {
      debugPrint('⚠️ [UserService] deleteUserImage failed (maybe missing): $e');
    }
  }

  Future<void> deleteAllUserImages(String uid) async {
    final dirRef = _storage.ref().child('userProfiles/$uid');
    try {
      final listResult = await dirRef.listAll();
      for (final item in listResult.items) {
        await item.delete();
        debugPrint('🗑️ [UserService] deleteAllUserImages deleted ${item.fullPath}');
      }
    } catch (e, st) {
      debugPrint('❌ [UserService] deleteAllUserImages failed: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> deleteUserProfile(String uid) async {
    debugPrint('➡️ [UserService] deleteUserProfile() uid=$uid');
    final ref = _fs.collection('users').doc(uid);
    try {
      await ref.delete();
      debugPrint('✅ [UserService] deleteUserProfile removed users/$uid');
    } catch (e, st) {
      debugPrint('⚠️ [UserService] deleteUserProfile failed deleting users/$uid: $e');
      debugPrint(st.toString());
    }
    await deleteAllUserImages(uid);
  }

  Future<void> saveProfileWithImages({
    required String uid,
    File? newProfileFile,
    File? newBackgroundFile,
    Map<String, dynamic>? fieldsToUpdate,
    Uint8List? profileBytes,
    Uint8List? backgroundBytes,
  }) async {
    debugPrint('➡️ [UserService] saveProfileWithImages() uid=$uid');
    final updates = <String, dynamic>{};
    if (fieldsToUpdate != null) updates.addAll(fieldsToUpdate);

    try {
      if (newProfileFile != null || profileBytes != null) {
        debugPrint('ℹ️ [UserService] saveProfileWithImages uploading profile image...');
        final url = await uploadUserImage(uid: uid, file: newProfileFile, pathType: 'profile', bytes: profileBytes);
        updates['profileImageUrl'] = url;
      }
      if (newBackgroundFile != null || backgroundBytes != null) {
        debugPrint('ℹ️ [UserService] saveProfileWithImages uploading background image...');
        final url = await uploadUserImage(uid: uid, file: newBackgroundFile, pathType: 'background', bytes: backgroundBytes);
        updates['backgroundImageUrl'] = url;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        final ref = _fs.collection('users').doc(uid);
        await ref.set(updates, SetOptions(merge: true));
        debugPrint('✅ [UserService] saveProfileWithImages wrote keys=${updates.keys.toList()} to users/$uid');
      } else {
        debugPrint('ℹ️ [UserService] saveProfileWithImages nothing to update.');
      }
    } catch (e, st) {
      debugPrint('❌ [UserService] saveProfileWithImages failed: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }
}
