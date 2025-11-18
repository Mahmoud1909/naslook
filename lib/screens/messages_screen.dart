// lib/screens/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:naslook/screens/discover_users_screen.dart';

class MessagesScreen extends StatelessWidget {
  final VoidCallback? onDiscover;

  const MessagesScreen({Key? key, this.onDiscover}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLarge = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.textTheme.bodyLarge?.color,
        centerTitle: true,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decorative circular card with large icon
                Container(
                  width: isLarge ? 220 : 160,
                  height: isLarge ? 220 : 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withOpacity(0.14),
                        theme.colorScheme.secondary.withOpacity(0.12),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // subtle rings
                        Container(
                          width: isLarge ? 160 : 120,
                          height: isLarge ? 160 : 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.dividerColor.withOpacity(0.06),
                              width: 10,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: isLarge ? 84 : 64,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // Title
                Text(
                  'No conversations',
                  style: TextStyle(
                    fontSize: isLarge ? 24 : 20,
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'You don\'t have any chats yet. Start connecting with other users.',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodySmall?.color,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 26),

                // Fancy discover button
                _DiscoverButton(
                  onTap:
                      onDiscover ??
                      () {
                        // default navigation to DiscoverUsersScreen
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DiscoverUsersScreen(),
                          ),
                        );
                      },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverButton extends StatefulWidget {
  final VoidCallback onTap;

  const _DiscoverButton({Key? key, required this.onTap}) : super(key: key);

  @override
  State<_DiscoverButton> createState() => _DiscoverButtonState();
}

class _DiscoverButtonState extends State<_DiscoverButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ani;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ani = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _ani, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ani.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails d) {
    setState(() => _pressed = true);
    _ani.forward();
  }

  void _onTapUp(TapUpDetails d) {
    _ani.reverse();
    setState(() => _pressed = false);
    widget.onTap();
  }

  void _onTapCancel() {
    _ani.reverse();
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Semantics(
          button: true,
          label: 'Discover users',
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _pressed
                    ? [
                        theme.colorScheme.primary.withOpacity(0.95),
                        theme.colorScheme.secondary.withOpacity(0.95),
                      ]
                    : [theme.colorScheme.secondary, theme.colorScheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.secondary.withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // small decorative icon circle
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.16),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  child: const Icon(
                    Icons.explore,
                    color: Colors.white,
                    size: 20,
                  ),
                ),

                // label
                const Text(
                  'Discover users',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
