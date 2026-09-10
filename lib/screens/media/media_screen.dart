import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app/app_controller.dart';
import '../../models/transfer_record.dart';
import '../../theme/theme.dart';
import '../../widgets/ad_banner.dart';
import '../../config/ad_units.dart';

/// View received media files (photos/videos).
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  static const _mediaExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
    'mp4', 'mov', 'mkv', 'avi', 'webm',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<List<TransferRecord>>(
          valueListenable: widget.controller.history,
          builder: (context, records, _) {
            final media = records
                .where((r) =>
                    r.direction == TransferDirection.received &&
                    r.status == TransferRecordStatus.completed &&
                    r.savePath != null)
                .where((r) {
              final ext = r.filename.split('.').last.toLowerCase();
              return _mediaExtensions.contains(ext);
            }).toList();

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: _Header(),
                ),
                if (media.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
                    sliver: SliverList.builder(
                      itemCount: media.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: _MediaRow(record: media[i]),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        AppSpace.xl, AppSpace.xs, AppSpace.xl, AppSpace.xxl),
                    child: AdBanner(
                      adUnitId: AdConfig.transfersBanner,
                      size: AdSize.banner,
                      align: Alignment.center,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Media',
            style: TextStyle(
              fontSize: AppText.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Received photos and videos',
            style: TextStyle(
              fontSize: AppText.body,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library, size: 48, color: AppColors.secondaryText),
            const SizedBox(height: AppSpace.md),
            const Text(
              'No media yet',
              style: TextStyle(
                fontSize: AppText.sectionHeading,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            const Text(
              'Receive photos or videos and they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.body,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final isVideo = record.filename
        .split('.')
        .last
        .toLowerCase()
        .contains('mp4') ||
        record.filename.split('.').last.toLowerCase().contains('mov');

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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isVideo
                  ? AppColors.purple.withValues(alpha: 0.12)
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(
              isVideo ? Icons.video_call : Icons.photo,
              color: isVideo ? AppColors.purple : AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.peer} · ${record.sizeBytes > 0 ? _formatSize(record.sizeBytes) : ''}',
                  style: const TextStyle(
                    fontSize: AppText.secondary - 1,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              if (record.savePath != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _MediaViewerScreen(filePath: record.savePath!),
                  ),
                );
              }
            },
            icon: const Icon(Icons.open_in_new),
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _MediaViewerScreen extends StatelessWidget {
  const _MediaViewerScreen({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final ext = filePath.split('.').last.toLowerCase();
    final isVideo = ext.contains('mp4') ||
        ext.contains('mov') ||
        ext.contains('mkv') ||
        ext.contains('avi') ||
        ext.contains('webm');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isVideo)
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_fill,
                    color: Colors.white, size: 64),
              ),
            )
          else
            InteractiveViewer(
              child: Image.file(File(filePath), fit: BoxFit.contain),
            ),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
