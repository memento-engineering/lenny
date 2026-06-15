import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../state/profile_provider.dart';

class ChangeProfileScreen extends ConsumerStatefulWidget {
  const ChangeProfileScreen({super.key});

  @override
  ConsumerState<ChangeProfileScreen> createState() =>
      _ChangeProfileScreenState();
}

class _ChangeProfileScreenState extends ConsumerState<ChangeProfileScreen> {
  final TextEditingController _name = TextEditingController();
  bool _bound = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).updateProfile(name: _name.text.trim());
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (Profile p) {
            if (!_bound) {
              _name.text = p.name;
              _bound = true;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Email: ${p.email}'),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
