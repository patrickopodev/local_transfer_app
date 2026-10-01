import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_controller.dart';
import '../../models/transfer_record.dart';
import '../../theme/theme.dart';
import '../../utils/file_name.dart';
import '../../utils/format.dart';
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<List<TransferRecord>>(
          valueListenable: widget.controller.history,
          builder: (context, records, _) {
            final media = records
                .where(
                  (r) =>
                      r.direction == TransferDirection.received &&
                      r.status == TransferRecordStatus.completed &&
                      r.savePath != null,
                )
                .where((r) => isMediaFile(r.filename))
                .toList();

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _Header()),
                if (media.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: const _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl,
                      0,
                      AppSpace.xl,
                      AppSpace.xxl,
                    ),
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
                      AppSpace.xl,
                      AppSpace.xs,
                      AppSpace.xl,
                      AppSpace.xxl,
                    ),
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
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
      ),
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library,
              size: 48,
              color: AppColors.secondaryText,
            ),
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
    final isVideo = isVideoFile(record.filename);

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
                  '${record.peer} · ${record.sizeBytes > 0 ? Format.bytes(record.sizeBytes) : ''}',
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
                    builder: (_) =>
                        _MediaViewerScreen(filePath: record.savePath!),
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
}

class _MediaViewerScreen extends StatefulWidget {
  const _MediaViewerScreen({required this.filePath});

  final String filePath;

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late final VideoPlayerController _video;
  late final Future<void> _videoInit;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.file(File(widget.filePath));
    _videoInit = _video
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          // An unsupported codec or a file deleted since it was received — fall
          // back to the still-frame card instead of an endless spinner.
          if (mounted) setState(() => _videoFailed = true);
        });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = isVideoFile(widget.filePath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isVideo) _buildVideo() else _buildImage(),
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

  Widget _buildImage() => InteractiveViewer(
    child: Image.file(
      File(widget.filePath),
      fit: BoxFit.contain,
      // A file deleted since it was received should show a message rather
      // than throw from the image decoder.
      errorBuilder: (_, _, _) => const _ViewerMessage(
        icon: Icons.broken_image_outlined,
        label: 'Image unavailable',
      ),
    ),
  );

  Widget _buildVideo() {
    if (_videoFailed) {
      return const _ViewerMessage(
        icon: Icons.videocam_off_outlined,
        label: 'Video cannot be played here',
      );
    }
    return FutureBuilder<void>(
      future: _videoInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !_video.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return Center(
          child: AspectRatio(
            aspectRatio: _video.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_video),
                VideoProgressIndicator(
                  _video,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
                IconButton(
                  iconSize: 64,
                  onPressed: () => setState(() {
                    _video.value.isPlaying ? _video.pause() : _video.play();
                  }),
                  icon: Icon(
                    _video.value.isPlaying
                        ? Icons.pause_circle
                        : Icons.play_circle_fill,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 48),
          const SizedBox(height: AppSpace.md),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
