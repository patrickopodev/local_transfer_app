import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Small stat card: icon + value + label (e.g. Speed / Remaining).
class TransferStatCard extends StatelessWidget {
  const TransferStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.smallCard),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: AppSpace.sm),
            Text(
              value,
              style: const TextStyle(
                fontSize: AppText.body,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: AppText.secondary - 1,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}