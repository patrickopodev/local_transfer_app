
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/format.dart';

/// Large centered circular progress indicator with percentage + bytes inside.
class TransferProgress extends StatelessWidget {
  const TransferProgress({
    super.key,
    required this.progress,
    required this.received,
    required this.total,
  });

  final double progress;
  final int received;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: AppText.percentage,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${Format.bytes(received)} / ${Format.bytes(total)}',
                style: const TextStyle(
                  fontSize: AppText.secondary,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: Icon(
              progress >= 1 ? Icons.check_circle : Icons.arrow_upward,
              color: AppColors.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}