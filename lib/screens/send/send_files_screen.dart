import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/device.dart';
import '../../models/transfer_file.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/file_category_card.dart';
import '../../widgets/selected_file_card.dart';
import 'select_device_screen.dart';

class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({
    super.key,
    required this.controller,
    this.initialDevice,
  });

  final AppController controller;
  final TransferDevice? initialDevice;

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final List<TransferFile> _files = [];

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null) return;
    final picked = result.files.map((f) => f.path).whereType<String>().toList();
    final files = picked
        .map((p) => TransferFile.fromFile(File(p)))
        .where((f) => f.size > 0)
        .toList();
    setState(() => _files.addAll(files));
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    final dir = Directory(path);
    if (!(await dir.exists())) return;
    final entities = await dir.list(recursive: true).toList();
    final files = entities
        .whereType<File>()
        .map((f) => TransferFile.fromFile(f))
        .where((f) => f.size > 0)
        .toList();
    if (files.isEmpty) return;
    setState(() => _files.addAll(files));
  }

  void _goNext() {
    final device = widget.initialDevice;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectDeviceScreen(
          controller: widget.controller,
          files: _files,
          initialDevice: device,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = _files.fold<int>(0, (sum, f) => sum + f.size);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const BackButton(color: AppColors.text),
        title: const Text(
          'Send files',
          style: TextStyle(
            fontSize: AppText.button,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.xl),
                children: [
Row(
                     children: [
                       _category('Photos', Icons.image, AppColors.primary,
                           onTap: _pickFiles),
                       const SizedBox(width: AppSpace.sm),
                       _category('Videos', Icons.play_arrow,
                           AppColors.purple, onTap: _pickFiles),
                       const SizedBox(width: AppSpace.sm),
                       _category('Documents', Icons.description,
                           AppColors.orange, onTap: _pickFiles),
                       const SizedBox(width: AppSpace.sm),
                       _category('Files', Icons.folder, AppColors.receive,
                           onTap: _pickFiles),
                       const SizedBox(width: AppSpace.sm),
                       _category('Folder', Icons.folder_open, AppColors.orange,
                           onTap: _pickFolder),
                     ],
                   ),
                  const SizedBox(height: AppSpace.xl),
                  if (_files.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selected files (${_files.length})',
                          style: const TextStyle(
                            fontSize: AppText.sectionHeading,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Format.bytes(totalBytes),
                          style: const TextStyle(
                            fontSize: AppText.secondary,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    for (final (i, file) in _files.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: SelectedFileCard(
                          file: file,
                          onRemove: () => setState(() => _files.removeAt(i)),
                        ),
                      ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpace.xxl),
                      child: Center(
                        child: Text(
                          'Tap a category to pick files',
                          style: TextStyle(
                            fontSize: AppText.secondary,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl, 0, AppSpace.xl, AppSpace.lg),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _files.isEmpty ? null : _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Next',
                        style: TextStyle(
                          fontSize: AppText.button,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 20),
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

  Widget _category(
    String label,
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: FileCategoryCard(label: label, icon: icon, color: color),
      ),
    );
  }
}