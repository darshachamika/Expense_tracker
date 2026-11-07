import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/flow_profile.dart';
import '../services/profile_service.dart';
import '../theme/flow_theme.dart';
import '../widgets/flow_visuals.dart';

const sectionNames = {
  'weekly': 'Weekly spending',
  'categories': 'Spending by category',
  'plans': 'Bills & goals',
  'recent': 'Recent activity',
  'insights': 'Ripple insights',
};

class ProfileAvatar extends StatelessWidget {
  final FlowProfile profile;
  final String? fallbackUrl;
  final double radius;
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.fallbackUrl,
    this.radius = 38,
  });
  @override
  Widget build(BuildContext context) {
    final name = profile.displayName.trim();
    final initials = name.isEmpty
        ? 'F'
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((s) => s[0])
              .join()
              .toUpperCase();
    final fallback = Text(
      initials,
      style: TextStyle(
        color: FlowTheme.ink,
        fontWeight: FontWeight.w800,
        fontSize: radius * .65,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFB7EFFF),
      child: ClipOval(
        child: profile.photo != null
            ? Image.memory(
                profile.photo!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => fallback,
              )
            : fallbackUrl != null
            ? Image.network(
                fallbackUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final User user;
  final FlowProfile profile;
  final VoidCallback? onEdit;
  final VoidCallback onCategories, onAdvisor, onSignOut;
  final String? loadError;
  const ProfileScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.onEdit,
    required this.onCategories,
    required this.onAdvisor,
    required this.onSignOut,
    this.loadError,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          if (loadError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(loadError!),
              ),
            ),
          ProfileCover(cover: profile.cover),
          const SizedBox(height: 12),
          Center(
            child: InkWell(
              onTap: onEdit,
              child: ProfileAvatar(
                profile: profile,
                fallbackUrl: user.photoURL,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.fullName.isEmpty
                ? user.displayName ?? 'Your Flow profile'
                : profile.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          Text(profile.displayName, textAlign: TextAlign.center),
          if (profile.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(profile.bio, textAlign: TextAlign.center),
            ),
          Text(profile.country, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Account & settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Personal details'),
                  subtitle: Text(user.email ?? 'Signed in'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onEdit,
                ),
                const ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('Currency'),
                  trailing: Text('LKR'),
                ),
                const ListTile(
                  leading: Icon(Icons.language),
                  title: Text('Language'),
                  trailing: Text('English'),
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  trailing: Text(profile.appearance),
                  onTap: onEdit,
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('Customize home'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onEdit,
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onCategories,
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome, color: FlowTheme.blue),
              title: const Text('Ripple'),
              subtitle: const Text('Explore your spending and take action'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onAdvisor,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    ),
  );
}

class ProfileCover extends StatelessWidget {
  final int cover;
  const ProfileCover({super.key, required this.cover});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: ColorFiltered(
      colorFilter: ColorFilter.mode(
        [
          Colors.transparent,
          const Color(0x3300DFFF),
          const Color(0x33051A72),
        ][cover.clamp(0, 2)],
        BlendMode.srcATop,
      ),
      child: const FlowLiquidCard(
        child: SizedBox(height: 74, width: double.infinity),
      ),
    ),
  );
}

class EditProfileScreen extends StatefulWidget {
  final User user;
  final FlowProfile profile;
  const EditProfileScreen({
    super.key,
    required this.user,
    required this.profile,
  });
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _full, _name, _bio, _country;
  late String _appearance;
  late int _cover;
  late Uint8List? _photo;
  late List<String> _order, _hidden;
  bool _saving = false, _picking = false;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _full = TextEditingController(
      text: p.fullName.isEmpty ? widget.user.displayName ?? '' : p.fullName,
    );
    _name = TextEditingController(
      text: p.displayName.isEmpty
          ? widget.user.displayName ?? ''
          : p.displayName,
    );
    _bio = TextEditingController(text: p.bio);
    _country = TextEditingController(text: p.country);
    _appearance = ['system', 'light', 'dark'].contains(p.appearance)
        ? p.appearance
        : 'system';
    _cover = p.cover;
    _photo = p.photo;
    _order = [...p.order];
    _hidden = [...p.hidden];
  }

  @override
  void dispose() {
    _full.dispose();
    _name.dispose();
    _bio.dispose();
    _country.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 480,
        maxHeight: 480,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 300000) {
        _message('Choose a smaller photo (under 300 KB).');
        return;
      }
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      _message('Could not open this photo. Try another image.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final p = FlowProfile(
        fullName: _full.text,
        displayName: _name.text,
        bio: _bio.text,
        country: _country.text,
        appearance: _appearance,
        cover: _cover,
        photo: _photo,
        order: _order,
        hidden: _hidden,
      );
      await ProfileService(widget.user.uid).save(p);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _message(
        'Could not save your profile. Check your connection and profile permissions, then retry.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int max, {
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      maxLength: max,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (v) =>
          required && (v == null || v.trim().isEmpty) ? 'Enter $label' : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving || _picking ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ProfileCover(cover: _cover),
                  const SizedBox(height: 16),
                  Center(
                    child: ProfileAvatar(
                      profile: FlowProfile(
                        displayName: _name.text,
                        photo: _photo,
                      ),
                      fallbackUrl: widget.user.photoURL,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _picking ? null : _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(_picking ? 'Opening…' : 'Change photo'),
                      ),
                      if (_photo != null)
                        TextButton(
                          onPressed: () => setState(() => _photo = null),
                          child: const Text('Use default'),
                        ),
                    ],
                  ),
                  _field(_full, 'Full name', 80),
                  _field(_name, 'Display name', 40),
                  _field(_bio, 'Bio', 180, required: false),
                  _field(_country, 'Country', 60),
                  const Text(
                    'Currency: LKR • Language: English',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Make it yours',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text('Appearance'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'light', label: Text('Light')),
                      ButtonSegment(value: 'dark', label: Text('Dark')),
                      ButtonSegment(value: 'system', label: Text('System')),
                    ],
                    selected: {_appearance},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) =>
                        setState(() => _appearance = v.single),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Home widgets',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'Drag to reorder. Switch off widgets to hide them.',
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _order.length,
                    onReorder: (old, next) => setState(() {
                      if (next > old) next--;
                      final item = _order.removeAt(old);
                      _order.insert(next, item);
                    }),
                    itemBuilder: (_, i) => Card(
                      key: ValueKey(_order[i]),
                      child: ListTile(
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_indicator),
                          ),
                        ),
                        title: Text(sectionNames[_order[i]]!),
                        trailing: Switch(
                          value: !_hidden.contains(_order[i]),
                          onChanged: (v) => setState(() {
                            if (v) {
                              _hidden.remove(_order[i]);
                            } else {
                              _hidden.add(_order[i]);
                            }
                          }),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving || _picking ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save changes'),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
