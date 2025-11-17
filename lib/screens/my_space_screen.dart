// lib/screens/my_space_screen.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/user_service.dart';
import 'edit_profile_screen.dart';

/// Professional, defensive MySpaceScreen:
/// - robust initials extraction (no RangeError)
/// - dynamic: live Stream from UserService
/// - polished UI that follows Theme.of(context)
/// - no layout shifts when copying ID
class MySpaceScreen extends StatefulWidget {
  final String? uid; // optional: shows another user's profile if provided
  const MySpaceScreen({this.uid, Key? key}) : super(key: key);

  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen> with SingleTickerProviderStateMixin {
  final UserService _service = UserService();

  String get _uid => widget.uid ?? (_service.currentUid ?? '');

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  bool _copied = false;
  Timer? _copyTimer;

  late Stream<UserProfile?> _profileStream;

  @override
  void initState() {
    super.initState();
    debugPrint('[MySpace] initState -> uid=$_uid');

    // Initialize stream once
    _profileStream = _service.streamUserProfile(_uid);

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _pulseController.repeat(reverse: true);

    if (kDebugMode) {
      Future.delayed(const Duration(seconds: 2), () => debugPrint('[MySpace] mounted and listening to profile stream'));
    }
  }

  @override
  void didUpdateWidget(covariant MySpaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // update stream only if uid changed (e.g., showing different profile)
    final newUid = widget.uid ?? (_service.currentUid ?? '');
    final oldUid = oldWidget.uid ?? (_service.currentUid ?? '');
    if (newUid != oldUid) {
      debugPrint('[MySpace] didUpdateWidget -> uid changed from $oldUid to $newUid. Recreating profile stream.');
      _profileStream = _service.streamUserProfile(newUid);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _copyTimer?.cancel();
    super.dispose();
  }

  /// Safe initials extractor:
  /// - accepts null or empty input
  /// - trims, splits on whitespace and ignores extra spaces
  /// - returns '?' for totally empty input
  /// - returns first letter for single-word names, or first+last initials for multi-word names
  String _initials(String? name) {
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return '?';

    final parts = raw.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      final w = parts.first;
      return w.isNotEmpty ? w[0].toUpperCase() : '?';
    }

    final first = parts.first;
    final last = parts.last;
    final a = first.isNotEmpty ? first[0].toUpperCase() : '';
    final b = last.isNotEmpty ? last[0].toUpperCase() : '';
    final result = '$a$b';
    return result.isNotEmpty ? result : '?';
  }

  Future<void> _handleCopyId(String id) async {
    try {
      await Clipboard.setData(ClipboardData(text: id));
      _copyTimer?.cancel();
      if (mounted) setState(() => _copied = true);

      // short non-blocking feedback (no layout shift)
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copied to clipboard'), duration: Duration(milliseconds: 900)));

      _copyTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
      debugPrint('[MySpace] copied id=$id');
    } catch (e, st) {
      debugPrint('[MySpace] copy error: $e');
      debugPrint(st.toString());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to copy ID')));
    }
  }

  Widget _fancyActionButton({
    required VoidCallback onTap,
    required Widget child,
    required String semanticLabel,
    double height = 44,
    double radius = 12,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.colorScheme.primary.withOpacity(0.95), theme.colorScheme.secondary.withOpacity(0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.09), blurRadius: 10, offset: const Offset(0, 6))],
          ),
          child: Center(child: DefaultTextStyle(style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), child: child)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      debugPrint('[MySpace] no uid -> show signed-out placeholder');
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent, automaticallyImplyLeading: false, title: const Text('Profile')),
        body: Center(child: Text('User not signed in', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)))) ,
      );
    }

    return StreamBuilder<UserProfile?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        // show loading indicator while waiting for first event
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final profile = snapshot.data;
        if (profile == null) {
          // show friendly empty state but keep app scaffold so navigation/things remain consistent
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              title: const Text('Profile'),
            ),
            body: Center(
              child: Text('Profile not found', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7))),
            ),
          );
        }

        final width = MediaQuery.of(context).size.width;
        final isLarge = width > 760;
        final coverHeight = isLarge ? 420.0 : 300.0;
        final avatarSize = isLarge ? 140.0 : 110.0;

        // key so changing background URL animates nicely
        final bgKey = ValueKey(profile.backgroundImageUrl.isNotEmpty ? profile.backgroundImageUrl : 'no-bg');

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                automaticallyImplyLeading: false,
                expandedHeight: coverHeight,
                pinned: true,
                elevation: 0,
                backgroundColor: Colors.transparent,
                flexibleSpace: LayoutBuilder(builder: (context, constraints) {
                  final top = constraints.biggest.height;
                  final collapseRatio = (top - kToolbarHeight) / (coverHeight - kToolbarHeight);
                  final titleOpacity = (1.0 - collapseRatio.clamp(0.0, 1.0)).clamp(0.0, 1.0);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // background (image or gradient)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: profile.backgroundImageUrl.isNotEmpty
                            ? Image.network(
                          profile.backgroundImageUrl,
                          key: bgKey,
                          fit: BoxFit.cover,
                          loadingBuilder: (c, child, progress) {
                            if (progress == null) return child;
                            return Container(color: Theme.of(context).colorScheme.primary.withOpacity(0.24));
                          },
                          errorBuilder: (_, __, ___) {
                            return Container(
                              key: const ValueKey('bg-fallback'),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.7)]),
                              ),
                            );
                          },
                        )
                            : Container(
                          key: bgKey,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.7)]),
                          ),
                        ),
                      ),

                      // overlay to improve contrast
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withOpacity(0.14), Colors.black.withOpacity(0.06), Colors.transparent],
                          ),
                        ),
                      ),

                      // top row seen when collapsed
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Opacity(
                            opacity: titleOpacity,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundImage: profile.profileImageUrl.isNotEmpty ? NetworkImage(profile.profileImageUrl) : null,
                                  backgroundColor: Colors.grey.shade200,
                                  child: profile.profileImageUrl.isEmpty ? Text(_initials(profile.name), style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    profile.name.isNotEmpty ? profile.name : 'No name',
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Material(
                                  color: Colors.white.withOpacity(0.10),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings (placeholder)'))),
                                    icon: const Icon(Icons.more_vert, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // floating glass card (avatar, name, jobTitle, actions)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Transform.translate(
                          offset: Offset(0, (1 - collapseRatio) * 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 10))],
                            ),
                            child: Row(
                              children: [
                                // avatar (Hero + AnimatedSwitcher)
                                Hero(
                                  tag: 'profile-avatar-${profile.uid}',
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 360),
                                    child: profile.profileImageUrl.isNotEmpty
                                        ? CircleAvatar(
                                      key: ValueKey(profile.profileImageUrl),
                                      radius: avatarSize / 3.2,
                                      backgroundImage: NetworkImage(profile.profileImageUrl),
                                      backgroundColor: Colors.grey.shade100,
                                    )
                                        : CircleAvatar(
                                      key: const ValueKey('initials'),
                                      radius: avatarSize / 3.2,
                                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                      child: Text(_initials(profile.name), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 14),

                                // name + jobTitle (city/club removed per request)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(profile.name.isNotEmpty ? profile.name : 'No name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(
                                        profile.jobTitle.isNotEmpty ? profile.jobTitle : '—',
                                        style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8)),
                                      ),
                                    ],
                                  ),
                                ),

                                // actions: edit + copy (fixed widths to avoid layout jumps)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ScaleTransition(
                                      scale: _pulseAnim,
                                      child: SizedBox(
                                        width: 120,
                                        child: _fancyActionButton(
                                          onTap: () async {
                                            final changed = await Navigator.of(context).push<bool>(
                                              PageRouteBuilder(
                                                pageBuilder: (_, __, ___) => EditProfileScreen(uid: profile.uid, initialProfile: profile),
                                                transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                                              ),
                                            );
                                            if (changed == true && mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
                                            }
                                          },
                                          semanticLabel: 'Edit profile',
                                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                                            Icon(Icons.edit, size: 16, color: Colors.white),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ]),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    // copy id control (fixed size)
                                    SizedBox(
                                      width: 120,
                                      child: Material(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(10),
                                        child: InkWell(
                                          onTap: () => _handleCopyId(profile.displayId),
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                AnimatedSwitcher(
                                                  duration: const Duration(milliseconds: 220),
                                                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                                  child: _copied
                                                      ? const Icon(Icons.check, key: ValueKey('check'), size: 16, color: Colors.green)
                                                      : const Icon(Icons.copy, key: ValueKey('copy'), size: 16, color: Colors.black87),
                                                ),
                                                const SizedBox(width: 8),
                                                DefaultTextStyle(
                                                  style: TextStyle(color: _copied ? Colors.green.shade700 : Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.w600),
                                                  child: Text(_copied ? 'Copied' : 'Copy ID'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),

              // content
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // About
                      if (profile.bio.isNotEmpty)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 6))],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(profile.bio, style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),

                      const SizedBox(height: 14),

                      // NEW: Club & City professional card (distinctive)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 10))],
                          // subtle glass-like background: light gradient + slight border
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).cardColor.withOpacity(0.98),
                              Theme.of(context).cardColor.withOpacity(0.9),
                            ],
                          ),
                          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.06)),
                        ),
                        child: Row(
                          children: [
                            // vertical accent bar with gradient
                            Container(
                              width: 8,
                              height: 120,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                                gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 6))],
                              ),
                            ),

                            // content
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    // Club block
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.9)]),
                                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                                                ),
                                                child: const Icon(Icons.sports_soccer, color: Colors.white, size: 20),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(child: Text('Club', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            profile.club.isNotEmpty ? profile.club : 'Not specified',
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color),
                                          ),
                                          const SizedBox(height: 6),
                                          Text('Your favourite team or organization', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                                        ],
                                      ),
                                    ),

                                    // vertical divider
                                    Container(width: 1, height: 80, color: Theme.of(context).dividerColor.withOpacity(0.08)),

                                    const SizedBox(width: 12),

                                    // City block
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.secondary.withOpacity(0.9)]),
                                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                                                ),
                                                child: const Icon(Icons.location_city, color: Colors.white, size: 20),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(child: Text('City', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            profile.city.isNotEmpty ? profile.city : 'Not specified',
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color),
                                          ),
                                          const SizedBox(height: 6),
                                          Text('Where you are based', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Skills
                      if (profile.skills.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: profile.skills
                              .map((s) => Chip(
                            label: Text(s),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ))
                              .toList(),
                        ),

                      const SizedBox(height: 22),

                      // Contact information
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 6))],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.email_outlined),
                              title: const Text('Email'),
                              subtitle: Text(profile.email.isNotEmpty ? profile.email : 'Not provided'),
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.phone_outlined),
                              title: const Text('Phone'),
                              subtitle: Text(profile.phone.isNotEmpty ? profile.phone : 'Not provided'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
