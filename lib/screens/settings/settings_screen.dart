import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../theme/theme.dart';

/// Device + receive-location settings (`/graphify` wiring: replaces the
/// Settings placeholder tab).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  String? _saveDir;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.controller.selfName);
    _saveDir = widget.controller.saveDirOverride;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickSaveDir() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() {
      _saveDir = path;
      widget.controller.setSaveDir(path);
    });
  }

  void _resetSaveDir() {
    setState(() {
      _saveDir = null;
      widget.controller.setSaveDir(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: AppText.title,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How LocalDrop presents itself and where files land.',
              style: TextStyle(
                fontSize: AppText.body,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            _card(
              title: 'Device name',
              subtitle: 'Shown to nearby devices during discovery.',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'My Device',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  ElevatedButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      widget.controller.setDeviceName(name);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Device name updated')),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            _card(
              title: 'Receive location',
              subtitle: _saveDir == null
                  ? 'Platform default (Downloads).'
                  : _saveDir!,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickSaveDir,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose folder'),
                    ),
                  ),
                  if (_saveDir != null) ...[
                    const SizedBox(width: AppSpace.sm),
                    IconButton(
                      tooltip: 'Reset to default',
                      onPressed: _resetSaveDir,
                      icon: const Icon(Icons.restore),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.smallCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppText.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: AppText.secondary,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
  }
}