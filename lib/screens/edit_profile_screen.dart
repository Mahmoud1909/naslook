// lib/screens/edit_profile_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/user_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String uid;
  final UserProfile initialProfile;

  const EditProfileScreen({
    required this.uid,
    required this.initialProfile,
    Key? key,
  }) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> with SingleTickerProviderStateMixin {
  final UserService _service = UserService();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _jobCtrl;
  late final TextEditingController _clubCtrl;
  late final TextEditingController _bioCtrl;

  // skills internal handling
  late List<String> _skills; // canonical list (max 7)
  late TextEditingController _newSkillCtrl; // used for adding
  int _editingIndex = -1; // -1 = none; otherwise index of skill being edited
  TextEditingController? _editingCtrl; // created when editing

  // images
  File? _newProfileFile;
  File? _newBackgroundFile;
  Uint8List? _newProfileBytes;
  Uint8List? _newBackgroundBytes;

  bool _saving = false;

  // animation for header/save button
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  static const int kMaxSkills = 7;
  static const int kMaxSkillLength = 30;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl = TextEditingController(text: p.name);
    _cityCtrl = TextEditingController(text: p.city);
    _jobCtrl = TextEditingController(text: p.jobTitle);
    _clubCtrl = TextEditingController(text: p.club);
    _bioCtrl = TextEditingController(text: p.bio);

    _skills = List<String>.from(p.skills ?? <String>[]);
    _newSkillCtrl = TextEditingController();

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.04).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _jobCtrl.dispose();
    _clubCtrl.dispose();
    _bioCtrl.dispose();
    _newSkillCtrl.dispose();
    _editingCtrl?.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool forProfile}) async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        setState(() {
          if (forProfile) {
            _newProfileBytes = bytes;
            _newProfileFile = null;
          } else {
            _newBackgroundBytes = bytes;
            _newBackgroundFile = null;
          }
        });
      } else {
        final file = File(picked.path);
        setState(() {
          if (forProfile) {
            _newProfileFile = file;
            _newProfileBytes = null;
          } else {
            _newBackgroundFile = file;
            _newBackgroundBytes = null;
          }
        });
      }
    } catch (e) {
      debugPrint('[EditProfile] pickImage error: $e');
    }
  }

  Widget _previewImage({required String currentUrl, File? file, Uint8List? bytes, double height = 160}) {
    if (bytes != null) return Image.memory(bytes, height: height, width: double.infinity, fit: BoxFit.cover);
    if (file != null) return Image.file(file, height: height, width: double.infinity, fit: BoxFit.cover);
    if (currentUrl.isNotEmpty) {
      return FadeInImage.assetNetwork(
        placeholder: 'assets/images/placeholder.png',
        image: currentUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        imageErrorBuilder: (_, __, ___) => Container(height: height, color: Colors.grey.shade200, child: const Icon(Icons.broken_image)),
      );
    }
    return Container(height: height, color: Colors.grey.shade200, child: const Icon(Icons.photo));
  }

  // utility: sanitize skill string
  String _normalizeSkill(String s) => s.trim();

  // add new skill (returns whether added)
  bool _addSkill(String raw) {
    final n = _normalizeSkill(raw);
    if (n.isEmpty) return false;
    if (n.length > kMaxSkillLength) return false;
    if (_skills.length >= kMaxSkills) return false;
    if (_skills.any((e) => e.toLowerCase() == n.toLowerCase())) return false;
    setState(() {
      _skills.add(n);
      _newSkillCtrl.clear();
    });
    return true;
  }

  // update existing skill
  bool _updateSkill(int index, String raw) {
    final n = _normalizeSkill(raw);
    if (n.isEmpty) return false;
    if (n.length > kMaxSkillLength) return false;
    if (_skills.any((e) => e.toLowerCase() == n.toLowerCase() && _skills.indexOf(e) != index)) return false;
    setState(() {
      _skills[index] = n;
      _editingIndex = -1;
      _editingCtrl?.dispose();
      _editingCtrl = null;
    });
    return true;
  }

  // remove skill
  void _removeSkill(int index) {
    setState(() {
      _skills.removeAt(index);
      if (_editingIndex == index) {
        _editingIndex = -1;
        _editingCtrl?.dispose();
        _editingCtrl = null;
      } else if (_editingIndex > index) {
        _editingIndex--; // shift
      }
    });
  }

  Future<void> _onSave() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    _animController.repeat(reverse: true);

    final fields = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'jobTitle': _jobCtrl.text.trim(),
      'club': _clubCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      // enforce max 7
      'skills': _skills.take(kMaxSkills).toList(),
      'email': widget.initialProfile.email,
    };

    try {
      await _service.saveProfileWithImages(
        uid: widget.uid,
        fieldsToUpdate: fields,
        newProfileFile: _newProfileFile,
        newBackgroundFile: _newBackgroundFile,
        profileBytes: _newProfileBytes,
        backgroundBytes: _newBackgroundBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully')));
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      debugPrint('[EditProfile] save error: $e');
      debugPrint(st.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save profile. Check logs.')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _animController.reset();
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon != null ? Icon(icon) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Widget _buildSkillChip(String text, int index) {
    // professional-looking chip with gradient and two tiny action icons
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.purple.shade500]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          // small edit icon
          GestureDetector(
            onTap: () {
              setState(() {
                _editingIndex = index;
                _editingCtrl?.dispose();
                _editingCtrl = TextEditingController(text: _skills[index]);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.edit, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          // small delete icon
          GestureDetector(
            onTap: () => _removeSkill(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSkillPill() {
    final enabled = _skills.length < kMaxSkills;
    return GestureDetector(
      onTap: enabled
          ? () {
        // focus the add field
        FocusScope.of(context).requestFocus(FocusNode());
        // show the inline add row by focusing _newSkillCtrl via setState to draw it
        setState(() {});
      }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: enabled ? Colors.indigo.shade200 : Colors.grey.shade300),
          boxShadow: enabled ? [BoxShadow(color: Colors.indigo.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: enabled ? Colors.indigo.shade700 : Colors.grey),
            const SizedBox(width: 8),
            Text(enabled ? 'Add skill' : 'Max reached', style: TextStyle(color: enabled ? Colors.indigo.shade700 : Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.initialProfile;
    final isLarge = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Column(
          children: [
            // Modern header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.purple.shade400]),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(padding: const EdgeInsets.all(8), child: const Icon(Icons.arrow_back, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Make it yours — professional and modern', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),

                  // Fancy save button (same as before)
                  AnimatedBuilder(
                    animation: _scaleAnim,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _saving ? _scaleAnim.value : 1.0,
                        child: child,
                      );
                    },
                    child: _FancyActionButton(
                      isLoading: _saving,
                      onPressed: _onSave,
                      icon: Icons.cloud_upload,
                      label: 'Save',
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // cover with glass overlay
                      GestureDetector(
                        onTap: () => _pickImage(forProfile: false),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              _previewImage(currentUrl: p.backgroundImageUrl, file: _newBackgroundFile, bytes: _newBackgroundBytes, height: isLarge ? 220 : 150),
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [Colors.black.withOpacity(0.08), Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Change cover', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // profile row (avatar + name/job) inside card
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => _pickImage(forProfile: true),
                                child: Stack(
                                  children: [
                                    Hero(
                                      tag: 'profile-avatar-${p.uid}',
                                      child: CircleAvatar(
                                        radius: isLarge ? 56 : 44,
                                        backgroundColor: Colors.grey.shade100,
                                        backgroundImage: p.profileImageUrl.isNotEmpty ? NetworkImage(p.profileImageUrl) : null,
                                        child: p.profileImageUrl.isEmpty ? const Icon(Icons.person, size: 36, color: Colors.grey) : null,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)]),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () => _pickImage(forProfile: true),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(Icons.edit, size: 18),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFormField(controller: _nameCtrl, decoration: _fieldDecoration('Name', icon: Icons.badge), validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null),
                                    const SizedBox(height: 10),
                                    TextFormField(controller: _jobCtrl, decoration: _fieldDecoration('Job title', icon: Icons.work)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // details card with two fields and inline skills UI
                      Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: TextFormField(controller: _cityCtrl, decoration: _fieldDecoration('City', icon: Icons.location_city))),
                                  const SizedBox(width: 12),
                                  Expanded(child: TextFormField(controller: _clubCtrl, decoration: _fieldDecoration('Favorite club', icon: Icons.sports_soccer))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(controller: _bioCtrl, decoration: _fieldDecoration('Bio', icon: Icons.info), maxLines: 3),
                              const SizedBox(height: 16),

                              // Skills title + help
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Skills', style: TextStyle(fontWeight: FontWeight.w700)),
                                  Text('${_skills.length}/$kMaxSkills', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // chips / inline editors
                              Wrap(
                                children: [
                                  // existing skills or editing field for index
                                  for (var i = 0; i < _skills.length; i++)
                                    _editingIndex == i
                                        ? _buildInlineEditRow(i)
                                        : _buildSkillChip(_skills[i], i),
                                  // add pill
                                  if (_skills.length < kMaxSkills) ...[
                                    const SizedBox(width: 6),
                                    _buildAddSkillInline(),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('Tip: tap edit icon to modify a skill. Add up to 7 skills.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // actions row with modern buttons
                      Row(
                        children: [
                          Expanded(
                            child: _FancyActionButton(
                              onPressed: _onSave,
                              icon: Icons.save_rounded,
                              label: 'Save Changes',
                              isLoading: _saving,
                              big: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _GhostButton(
                              onPressed: _saving
                                  ? null
                                  : () {
                                Navigator.of(context).pop(false);
                              },
                              label: 'Discard',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Inline edit row for a specific skill index
  Widget _buildInlineEditRow(int index) {
    _editingCtrl ??= TextEditingController(text: _skills[index]);
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 3))]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,
            child: TextField(
              controller: _editingCtrl,
              autofocus: true,
              maxLength: kMaxSkillLength,
              decoration: const InputDecoration(counterText: '', isDense: true, border: InputBorder.none, hintText: 'Edit skill'),
              onSubmitted: (v) => _updateSkill(index, v),
            ),
          ),
          const SizedBox(width: 8),
          // Save
          GestureDetector(
            onTap: () {
              final ok = _updateSkill(index, _editingCtrl?.text ?? '');
              if (!ok) {
                // show simple feedback
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid or duplicate skill')));
              }
            },
            child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.check, size: 18, color: Colors.white)),
          ),
          const SizedBox(width: 6),
          // Cancel
          GestureDetector(
            onTap: () {
              setState(() {
                _editingIndex = -1;
                _editingCtrl?.dispose();
                _editingCtrl = null;
              });
            },
            child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.close, size: 18, color: Colors.red.shade700)),
          ),
        ],
      ),
    );
  }

  // Inline add widget
  Widget _buildAddSkillInline() {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.indigo.shade100),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 4))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: _newSkillCtrl,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'New skill'),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) {
              final ok = _addSkill(v);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing/duplicate/too long or max reached')));
              } else {
                // success visual feedback
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skill added')));
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            final ok = _addSkill(_newSkillCtrl.text);
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing/duplicate/too long or max reached')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skill added')));
            }
          },
          child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple.shade400, Colors.indigo.shade600]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.add, color: Colors.white, size: 18)),
        ),
      ]),
    );
  }
}

// A modern, reusable fancy button with gradient, subtle animation and loading state.
class _FancyActionButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;
  final bool isLoading;
  final bool big;

  const _FancyActionButton({Key? key, this.onPressed, required this.label, required this.icon, this.isLoading = false, this.big = false}) : super(key: key);

  @override
  State<_FancyActionButton> createState() => _FancyActionButtonState();
}

class _FancyActionButtonState extends State<_FancyActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.98, end: 1.02).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final height = widget.big ? 54.0 : 44.0;

    return ScaleTransition(
      scale: _pulse,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: enabled ? 1.0 : 0.6,
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: enabled
                  ? LinearGradient(colors: [Colors.purple.shade500, Colors.indigo.shade500])
                  : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400]),
              boxShadow: enabled
                  ? [BoxShadow(color: Colors.purple.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 8))]
                  : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading) ...[
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white))),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(widget.icon, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const _GhostButton({Key? key, this.onPressed, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: enabled ? Colors.grey.shade400 : Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(child: Text(label, style: TextStyle(color: enabled ? Colors.black87 : Colors.grey.shade500, fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }
}
