import 'package:flutter/material.dart';

import '../models/transfer_file.dart';
import '../theme/theme.dart';
import '../utils/format.dart';

/// Card for one selected file. Icon color/symbol depends on category.
class SelectedFileCard extends StatelessWidget {
  const SelectedFileCard({
    super.key,
    required this.file,
    required this.onRemove,
  });

  final TransferFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.smallCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(categoryIcon, color: categoryColor, size: 22),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Format.bytes(file.size),
                  style: const TextStyle(
                    fontSize: AppText.secondary - 1,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            color: AppColors.secondaryText,
          ),
        ],
      ),
    );
  }

  Color get categoryColor => switch (file.type) {
        'Photos' => AppColors.primary,
        'Videos' => AppColors.purple,
        'Documents' => AppColors.orange,
        _ => AppColors.receive,
      };

  IconData get categoryIcon => switch (file.type) {
        'Photos' => Icons.image,
        'Videos' => Icons.play_arrow,
        'Documents' => Icons.description,
        _ => Icons.folder,
      };
}