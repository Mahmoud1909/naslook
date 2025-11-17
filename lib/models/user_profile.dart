// lib/models/user_profile.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String city;
  final String jobTitle;
  final String club;
  final String bio;
  final List<String> skills;
  final String walletNumber;
  final String profileImageUrl;
  final String backgroundImageUrl;
  final String displayId;
  final bool isPublic;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const UserProfile({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.city = '',
    this.jobTitle = '',
    this.club = '',
    this.bio = '',
    this.skills = const [],
    this.walletNumber = '',
    this.profileImageUrl = '',
    this.backgroundImageUrl = '',
    this.displayId = '',
    this.isPublic = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Robust conversion helper that accepts many timestamp forms.
  static Timestamp? _toTimestamp(dynamic v) {
    if (v == null) return null;
    try {
      if (v is Timestamp) return v;
      if (v is DateTime) return Timestamp.fromDate(v);
      if (v is int) return Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(v));
      if (v is double) return Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(v.toInt()));
      if (v is String) {
        final dt = DateTime.tryParse(v);
        if (dt != null) return Timestamp.fromDate(dt);
        final numVal = int.tryParse(v);
        if (numVal != null) return Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(numVal));
        return null;
      }
      if (v is Map) {
        final seconds = v['seconds'] ?? v['secs'] ?? v['s'];
        final nanos = v['nanoseconds'] ?? v['nanos'] ?? v['ns'] ?? 0;
        final secInt = (seconds is int) ? seconds : (int.tryParse(seconds?.toString() ?? '') ?? null);
        final nanoInt = (nanos is int) ? nanos : (int.tryParse(nanos?.toString() ?? '') ?? 0);
        if (secInt != null) return Timestamp(secInt, nanoInt);
      }
    } catch (_) {}
    return null;
  }

  static List<String> _parseSkills(dynamic sRaw) {
    try {
      if (sRaw == null) return <String>[];
      if (sRaw is List) return sRaw.map((e) => e?.toString() ?? '').where((x) => x.isNotEmpty).cast<String>().toList();
      if (sRaw is String) {
        final s = sRaw.trim();
        if (s.startsWith('[') && s.endsWith(']')) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is List) return decoded.map((e) => e?.toString() ?? '').where((x) => x.isNotEmpty).cast<String>().toList();
          } catch (_) {}
        }
        if (s.contains(',')) return s.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        if (s.isNotEmpty) return [s];
      }
    } catch (_) {}
    return <String>[];
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final uid = (map['uid'] ?? map['id'] ?? '')?.toString() ?? '';
    final name = (map['name'] ?? map['displayName'] ?? map['display_name'] ?? '')?.toString() ?? '';
    final email = (map['email'] ?? '')?.toString() ?? '';
    final phone = (map['phone'] ?? '')?.toString() ?? '';
    final city = (map['city'] ?? '')?.toString() ?? '';
    final jobTitle = (map['jobTitle'] ?? map['title'] ?? map['role'] ?? '')?.toString() ?? '';
    final club = (map['club'] ?? '')?.toString() ?? '';
    final bio = (map['bio'] ?? map['about'] ?? '')?.toString() ?? '';
    final skills = _parseSkills(map['skills']);
    final walletNumber = (map['walletNumber'] ?? map['wallet'] ?? '')?.toString() ?? '';

    final profileImageUrl = (map['profileImageUrl'] ??
        map['profile_image_url'] ??
        map['photo_url'] ??
        map['photoUrl'] ??
        map['photo'] ??
        '')
        .toString();
    final backgroundImageUrl = (map['backgroundImageUrl'] ?? map['background_image'] ?? map['background'] ?? '').toString();

    final displayId = (map['displayId'] ?? map['display_id'] ?? uid)?.toString() ?? '';
    final isPublic = (map['isPublic'] is bool) ? map['isPublic'] as bool : (map['public'] is bool ? map['public'] as bool : true);

    final createdAt = _toTimestamp(map['createdAt'] ?? map['created_at'] ?? map['_raw_createdAt']);
    final updatedAt = _toTimestamp(map['updatedAt'] ?? map['updated_at'] ?? map['_raw_updatedAt']);

    return UserProfile(
      uid: uid,
      name: name,
      email: email,
      phone: phone,
      city: city,
      jobTitle: jobTitle,
      club: club,
      bio: bio,
      skills: skills,
      walletNumber: walletNumber,
      profileImageUrl: profileImageUrl,
      backgroundImageUrl: backgroundImageUrl,
      displayId: displayId.isNotEmpty ? displayId : uid,
      isPublic: isPublic,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final m = <String, dynamic>{
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'city': city,
      'jobTitle': jobTitle,
      'club': club,
      'bio': bio,
      'skills': skills,
      'walletNumber': walletNumber,
      'profileImageUrl': profileImageUrl,
      'backgroundImageUrl': backgroundImageUrl,
      'displayId': displayId,
      'isPublic': isPublic,
    };
    if (includeTimestamps) {
      m['updatedAt'] = FieldValue.serverTimestamp();
    }
    return m;
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, name: $name, email: $email, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}
