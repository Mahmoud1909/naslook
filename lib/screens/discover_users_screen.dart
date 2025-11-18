// lib/screens/discover_users_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';

typedef OnUserSelected = void Function(UserProfile profile);

const String fallbackAvatar =
    'https://img.icons8.com/color/1200/person-male.jpg';

class DiscoverUsersScreen extends StatefulWidget {
  final OnUserSelected? onUserSelected;
  const DiscoverUsersScreen({Key? key, this.onUserSelected}) : super(key: key);

  @override
  State<DiscoverUsersScreen> createState() => _DiscoverUsersScreenState();
}

class _DiscoverUsersScreenState extends State<DiscoverUsersScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Controls
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _idCtrl = TextEditingController();
  String? _cityFilter = '';

  // Pagination
  static const int _pageSize = 10;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  final List<UserProfile> _items = [];

  // UI state
  bool _initialLoadDone = false;
  String _errorMsg = '';

  // copy-id state per id
  final Map<String, bool> _copied = {};
  final Map<String, Timer?> _copyTimers = {};

  @override
  void initState() {
    super.initState();
    _performInitialLoad();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    for (final t in _copyTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  Future<void> _performInitialLoad({bool refresh = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMsg = '';
      if (refresh) {
        _lastDoc = null;
        _items.clear();
        _hasMore = true;
        _initialLoadDone = false;
      }
    });

    try {
      final q = _buildQuery(limit: _pageSize, startAfter: _lastDoc);
      final snap = await q.get();
      final docs = snap.docs;
      if (refresh) _items.clear();

      for (final d in docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['uid'] = data['uid'] ?? d.id;
        final profile = UserProfile.fromMap(data);
        _items.add(profile);
      }

      _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
      if (docs.length < _pageSize) _hasMore = false;
      setState(() {
        _initialLoadDone = true;
      });
    } catch (e, st) {
      debugPrint('DiscoverUsers load error: $e\n$st');
      setState(() {
        _errorMsg = 'Failed to load users.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Query<Map<String, dynamic>> _buildQuery(
      {int limit = _pageSize,
        DocumentSnapshot<Map<String, dynamic>>? startAfter}) {
    Query<Map<String, dynamic>> q = _fs
        .collection('users')
        .withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => Map<String, dynamic>.from(snap.data() ?? {}),
      toFirestore: (m, _) => m,
    );

    // city filter server-side if selected
    if (_cityFilter != null && _cityFilter!.isNotEmpty) {
      q = q.where('city', isEqualTo: _cityFilter);
    }

    // combine name / id filters client-friendly:
    final nameText = _nameCtrl.text.trim();
    final idText = _idCtrl.text.trim();

    if (idText.isNotEmpty) {
      // try doc id exact match (best for precise search)
      q = q.where(FieldPath.documentId, isEqualTo: idText);
    } else if (nameText.isNotEmpty) {
      // prefix search on name
      q = q.orderBy('name').startAt([nameText]).endAt([nameText + '\uf8ff']);
    } else {
      q = q.orderBy('name');
    }

    q = q.limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q;
  }

  Future<void> _onSearchPressed() async {
    // refresh results
    _lastDoc = null;
    _hasMore = true;
    _items.clear();
    FocusScope.of(context).unfocus();
    await _performInitialLoad(refresh: true);
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final q = _buildQuery(limit: _pageSize, startAfter: _lastDoc);
      final snap = await q.get();
      final docs = snap.docs;
      for (final d in docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['uid'] = data['uid'] ?? d.id;
        final profile = UserProfile.fromMap(data);
        _items.add(profile);
      }
      _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
      if (docs.length < _pageSize) _hasMore = false;
    } catch (e, st) {
      debugPrint('DiscoverUsers loadMore error: $e\n$st');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to load more users')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _fetchUniqueCities({int limit = 50}) async {
    try {
      final snap = await _fs
          .collection('users')
          .where('city', isNotEqualTo: '')
          .limit(limit)
          .get();
      final cities = <String>{};
      for (final d in snap.docs) {
        final c = (d.data()['city'] ?? '').toString().trim();
        if (c.isNotEmpty) cities.add(c);
      }
      final list = cities.toList()..sort();
      return list;
    } catch (e) {
      debugPrint('fetchUniqueCities failed: $e');
      return [];
    }
  }

  Future<void> _handleCopyId(String id) async {
    try {
      await Clipboard.setData(ClipboardData(text: id));
      // cancel existing timer
      _copyTimers[id]?.cancel();
      if (mounted) {
        setState(() => _copied[id] = true);
      }

      // short non-blocking feedback (no layout shift)
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID copied to clipboard'),
          duration: Duration(milliseconds: 900),
        ),
      );

      _copyTimers[id] = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied[id] = false);
      });
      debugPrint('[DiscoverUsers] copied id=$id');
    } catch (e, st) {
      debugPrint('[DiscoverUsers] copy error: $e');
      debugPrint(st.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Unable to copy ID')));
    }
  }

  Widget _buildAvatar(String url, String displayId) {
    final imageUrl = (url.isNotEmpty) ? url : fallbackAvatar;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 12, offset: const Offset(0, 6)),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          width: 72,
          height: 72,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 72,
              height: 72,
              color: Colors.grey.shade200,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Image.network(
              fallbackAvatar,
              fit: BoxFit.cover,
              width: 72,
              height: 72,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary.withOpacity(0.06), theme.colorScheme.secondary.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: theme.colorScheme.primary.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // top row: Name + ID fields (stylish)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. John Doe',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _idCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _onSearchPressed(),
                  decoration: InputDecoration(
                    labelText: 'ID',
                    hintText: 'user id',
                    prefixIcon: const Icon(Icons.perm_identity),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // city dropdown + fancy search button
          Row(
            children: [
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _fetchUniqueCities(limit: 50),
                  builder: (context, snap) {
                    final cities = snap.data ?? [];

                    return DropdownButtonFormField<String>(
                      value: (_cityFilter != null && _cityFilter!.isNotEmpty) ? _cityFilter : '',
                      hint: const Text('City'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Cities')),
                        ...cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      ],
                      onChanged: (v) => setState(() => _cityFilter = v),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              // fancy search button
              GestureDetector(
                onTap: _onSearchPressed,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.colorScheme.secondary, theme.colorScheme.primary]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 8)),
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.search, size: 16, color: Colors.black87)),
                      SizedBox(width: 10),
                      Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkillChip(String skill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade100]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Text(skill, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildUserCard(UserProfile p) {
    final id = p.displayId;
    final copied = _copied[id] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // open preview
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ProfilePreviewPage(profile: p)));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: LayoutBuilder(builder: (context, constraints) {
                // if there is little horizontal space, use stacked layout to avoid overflow
                final isNarrow = constraints.maxWidth < 360;

                if (isNarrow) {
                  // Vertical layout for very narrow screens
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildAvatar(p.profileImageUrl, p.displayId),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name.isNotEmpty ? p.name : p.displayId,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Flexible(child: Text(p.jobTitle.isNotEmpty ? p.jobTitle : '—', style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Flexible(child: Text(p.city.isNotEmpty ? p.city : 'Unknown', style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (p.skills.isNotEmpty)
                        Wrap(
                          children: p.skills.take(6).map((s) => _buildSkillChip(s)).toList(),
                        ),
                      const SizedBox(height: 10),
                      // actions row (full width, buttons wrap)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _contactButton(p),
                          _viewButton(p),
                          _copyIdButton(id, copied),
                        ],
                      ),
                    ],
                  );
                }

                // Default horizontal layout for wider screens
                return Row(
                  children: [
                    _buildAvatar(p.profileImageUrl, p.displayId),
                    const SizedBox(width: 12),
                    // main info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name.isNotEmpty ? p.name : p.displayId,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(child: Text(p.jobTitle.isNotEmpty ? p.jobTitle : '—', style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              const Icon(Icons.location_on, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Flexible(child: Text(p.city.isNotEmpty ? p.city : 'Unknown', style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (p.skills.isNotEmpty)
                            Wrap(
                              children: p.skills.take(6).map((s) => _buildSkillChip(s)).toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // actions column with constrained width so it never forces overflow
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _contactButton(p),
                          const SizedBox(height: 8),
                          _viewButton(p),
                          const SizedBox(height: 8),
                          _copyIdButton(id, copied, center: true),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactButton(UserProfile p) {
    return GestureDetector(
      onTap: () {
        if (widget.onUserSelected != null) {
          widget.onUserSelected!(p);
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contact ${p.name}')));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.pink.shade400, Colors.orange.shade400]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 8))],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_1_outlined, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _viewButton(UserProfile p) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ProfilePreviewPage(profile: p))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: const Text('View', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _copyIdButton(String id, bool copied, {bool center = false}) {
    final widget = Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _handleCopyId(id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: copied
                    ? Icon(Icons.check, key: ValueKey('check-$id'), size: 16, color: Colors.green.shade700)
                    : const Icon(Icons.copy, key: ValueKey('copy'), size: 16, color: Colors.black87),
              ),
              const SizedBox(width: 8),
              DefaultTextStyle(
                style: TextStyle(
                    color: copied ? Colors.green.shade700 : Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600),
                child: Text(copied ? 'Copied' : 'Copy ID'),
              ),
            ],
          ),
        ),
      ),
    );

    if (center) {
      return Center(child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 80, maxWidth: 120), child: widget));
    }
    return ConstrainedBox(constraints: const BoxConstraints(minWidth: 80, maxWidth: 140), child: widget);
  }

  PreferredSizeWidget _buildCustomAppBar(BuildContext context) {
    final theme = Theme.of(context);

    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade100, width: 1),
            ),
          ),
          child: Row(
            children: [
              /// BACK BUTTON
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),

              const SizedBox(width: 10),

              /// TITLE ONLY
              const Expanded(
                child: Text(
                  'Find people to chat with',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _buildCustomAppBar(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _buildSearchCard(context),
              const SizedBox(height: 6),
              Expanded(
                child: _errorMsg.isNotEmpty
                    ? Center(child: Text(_errorMsg))
                    : _initialLoadDone && _items.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.people_outline, size: 56),
                      SizedBox(height: 8),
                      Text('No users found'),
                    ],
                  ),
                )
                    : ListView(
                  children: [
                    ..._items.map(_buildUserCard),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_isLoading && _hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: GestureDetector(
                            onTap: _loadMore,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [theme.colorScheme.secondary, theme.colorScheme.primary]),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 8))],
                              ),
                              child: const Text('Show more', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePreviewPage extends StatelessWidget {
  final UserProfile profile;
  const _ProfilePreviewPage({Key? key, required this.profile}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // minimal profile preview — you can expand this
    return Scaffold(
      appBar: AppBar(title: Text(profile.name.isNotEmpty ? profile.name : profile.displayId)),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            // larger avatar with fallback
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
              ),
              child: ClipOval(
                child: Image.network(
                  profile.profileImageUrl.isNotEmpty ? profile.profileImageUrl : fallbackAvatar,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Image.network(fallbackAvatar, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(profile.jobTitle.isNotEmpty ? profile.jobTitle : '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(profile.city.isNotEmpty ? profile.city : 'Unknown'),
            const SizedBox(height: 12),
            if (profile.bio.isNotEmpty) Text(profile.bio),
          ],
        ),
      ),
    );
  }
}
