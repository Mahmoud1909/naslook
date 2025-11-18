// lib/screens/home_screen.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:naslook/screens/messages_screen.dart';

import 'package:naslook/widgets/profile_app_bar.dart';
import 'package:naslook/widgets/custom_bottom_nav.dart';

import 'package:naslook/screens/my_space_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int initialIndex; // NEW: allow opening HomeScreen on a specific tab

  const HomeScreen({required this.userData, this.initialIndex = 0, Key? key})
    : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;

  // Helper getters for user data
  String get first => (widget.userData['first_name'] ?? '').toString();

  String get last => (widget.userData['last_name'] ?? '').toString();

  String get email => (widget.userData['email'] ?? 'No email').toString();

  String get photo => (widget.userData['photo_url'] ?? '').toString();

  String get displayName => (widget.userData['displayName'] ?? '').toString();

  String get uid => (widget.userData['uid'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    // use passed initialIndex so callers can open HomeScreen with a given tab active (e.g., messages)
    _selectedIndex = widget.initialIndex;
  }

  String _getPrettyJson(Map m) {
    try {
      return const JsonEncoder.withIndent('  ').convert(m);
    } catch (_) {
      return m.toString();
    }
  }

  // Helpers for name/initials
  String _getInitials() {
    final source = first.isNotEmpty
        ? first
        : (displayName.isNotEmpty ? displayName : '');
    if (source.isEmpty) return 'U';
    final len = math.min(2, source.trim().length);
    return source.trim().substring(0, len).toUpperCase();
  }

  String _getFullName() {
    if (first.isNotEmpty || last.isNotEmpty) return '$first $last'.trim();
    if (displayName.isNotEmpty) return displayName;
    if (email.isNotEmpty) return email;
    return 'No name';
  }

  Widget _buildHomeTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.home_outlined,
              size: 56,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _getFullName(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMySpaceTab() {
    debugPrint("ℹ️ [HomeScreen] Building MySpaceTab (embedded) for uid=$uid");
    return MySpaceScreen(uid: uid);
  }

  Widget _buildCirclesTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.groups_outlined,
              size: 56,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Circles',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.map_outlined,
              size: 56,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Map',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesTab() {
    return const MessagesScreen();
  }

  Widget _buildOrdersTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Orders',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildCirclesTab();
      case 2:
        return _buildMapTab();
      case 3:
        return _buildMessagesTab();
      case 4:
        return _buildOrdersTab();
      case 5:
        return _buildMySpaceTab();
      default:
        return _buildHomeTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ProfileAppBar(
        userData: widget.userData,
        onProfileTap: () {
          debugPrint("➡️ [HomeScreen] onProfileTap -> show My Space (index=5)");
          setState(() => _selectedIndex = 5);
        },
        onNotificationsTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications (placeholder)')),
          );
        },
        onSettingsTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings (placeholder)')),
          );
        },
      ),
      bottomNavigationBar: CustomBottomNav(
        initialIndex: _selectedIndex,
        onTap: (index) {
          debugPrint("ℹ️ [HomeScreen] bottom nav tapped -> index=$index");
          setState(() => _selectedIndex = index);
        },
      ),
      backgroundColor: Colors.grey.shade50,
      body: _buildBody(),
    );
  }
}
