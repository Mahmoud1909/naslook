// lib/widgets/profile_app_bar.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Map<String, dynamic> userData;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onSettingsTap;

  const ProfileAppBar({
    required this.userData,
    this.onProfileTap,
    this.onNotificationsTap,
    this.onSettingsTap,
    Key? key,
  }) : super(key: key);

  String _getInitials(String first, String display) {
    final source = first.isNotEmpty ? first : (display.isNotEmpty ? display : '');
    if (source.isEmpty) return 'U';
    final len = math.min(2, source.trim().length);
    return source.trim().substring(0, len).toUpperCase();
  }

  String _getFullName(String first, String last, String display, String email) {
    if (first.isNotEmpty || last.isNotEmpty) return '$first $last'.trim();
    if (display.isNotEmpty) return display;
    if (email.isNotEmpty) return email;
    return 'No name';
  }

  @override
  Widget build(BuildContext context) {
    final first = (userData['first_name'] ?? '').toString();
    final last = (userData['last_name'] ?? '').toString();
    final email = (userData['email'] ?? '').toString();
    final photo = (userData['photo_url'] ?? '').toString();
    final display = (userData['displayName'] ?? '').toString();

    Widget buildAvatar(double radius) {
      final initials = _getInitials(first, display);
      const fallbackAvatar = 'https://img.icons8.com/color/1200/person-male.jpg';
      if (photo.isEmpty) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.45)),
        );
      }

      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.network(
            photo,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Image.network(fallbackAvatar, width: radius * 2, height: radius * 2, fit: BoxFit.cover,
              errorBuilder: (c2, e2, s2) => Container(
                width: radius * 2,
                height: radius * 2,
                color: Theme.of(context).primaryColor,
                alignment: Alignment.center,
                child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.45)),
              ),
            ),
          ),
        ),
      );
    }

    final fullName = _getFullName(first, last, display, email);

    return PreferredSize(
      preferredSize: const Size.fromHeight(88),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 6))],
            border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onProfileTap ??
                        () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open profile (placeholder)')));
                    },
                child: buildAvatar(28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome back', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: onNotificationsTap ??
                            () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications pressed (placeholder)')));
                        },
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.notifications_none, size: 26),
                        Positioned(
                          right: -1,
                          top: -2,
                          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: onSettingsTap ??
                            () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings pressed (placeholder)')));
                        },
                    icon: const Icon(Icons.settings_outlined, size: 26),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(88);
}
