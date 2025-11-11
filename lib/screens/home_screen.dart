// lib/screens/home_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  const HomeScreen({required this.userData, Key? key}) : super(key: key);

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(child: Text((value == null || value.isEmpty) ? 'Not provided' : value)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = (userData['first_name'] ?? '').toString();
    final last = (userData['last_name'] ?? '').toString();
    final email = (userData['email'] ?? 'No email').toString();
    final photo = (userData['photo_url'] ?? '').toString();
    final phone = (userData['phone'] ?? '').toString();
    final age = (userData['age'] ?? '').toString();
    final gender = (userData['gender'] ?? '').toString();
    final displayName = (userData['displayName'] ?? '').toString();
    final uid = (userData['uid'] ?? '').toString();
    debugPrint("ℹ️ [HOME] Building Home screen for $uid");

    // Show a compact JSON of the safe userData for debugging but avoid huge raw objects.
    String getPrettyJson(Map m) {
      try {
        return const JsonEncoder.withIndent('  ').convert(m);
      } catch (e) {
        return m.toString();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: () async {
              debugPrint("➡️ [HOME] Sign out pressed");
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.of(context).pop(); // go back to login
            },
            child: const Text('Sign out', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // avatar
            CircleAvatar(
              radius: 44,
              backgroundImage: (photo.isNotEmpty) ? NetworkImage(photo) : null,
              child: (photo.isEmpty) ? const Icon(Icons.person, size: 44) : null,
            ),
            const SizedBox(height: 16),
            Text(
              (first.isNotEmpty || last.isNotEmpty) ? '$first $last' : (displayName.isNotEmpty ? displayName : 'No name'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(email, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 18),

            // details
            _row('UID', uid),
            _row('Email', email),
            _row('Phone', phone),
            _row('First name', first),
            _row('Last name', last),
            _row('Age', age),
            _row('Gender', gender),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Safe user data (JSON):', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SelectableText(getPrettyJson(userData), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
