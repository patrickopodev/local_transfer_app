import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/theme.dart';

/// White card showing a discovered peer. Tapping sends a file to it.
class NearbyDeviceCard extends StatelessWidget {
  const NearbyDeviceCard({
    super.key,
    required this.device,
    required this.onTap,
  });

  final TransferDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAndroid = device.platform.toLowerCase().contains('android');
    final icon = isAndroid ? Icons.android : Icons.phone_iphone;
    final subtitle = [
      if (device.platform.isNotEmpty) device.platform,
      if (device.ip.isNotEmpty) device.ip,
    ].join(' • ');

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.smallCard),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.smallCard),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppText.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty ? 'Nearby' : subtitle,
                      style: const TextStyle(
                        fontSize: AppText.secondary - 1,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap to send',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 10,
                backgroundColor:
                    device.available ? AppColors.receive : AppColors.border,
                child: device.available
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}