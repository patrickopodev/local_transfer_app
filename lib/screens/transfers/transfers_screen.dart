import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/transfer_record.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';

/// History of completed transfers (design doc §3, Transfers tab).
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<List<TransferRecord>>(
          valueListenable: controller.history,
          builder: (context, records, _) {
            if (records.isEmpty) return const _EmptyState();
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: _Header(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
                  sliver: SliverList.builder(
                    itemCount: records.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _TransferRow(record: records[i]),
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
            'Transfers',
            style: TextStyle(
              fontSize: AppText.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Files sent and received on this device',
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: AppColors.secondaryText),
            SizedBox(height: AppSpace.md),
            Text(
              'No transfers yet',
              style: TextStyle(
                fontSize: AppText.sectionHeading,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppSpace.xs),
            Text(
              'Send or receive a file and it will show up here.',
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

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final outgoing = record.direction == TransferDirection.sent;
    final accent = outgoing ? AppColors.primary : AppColors.receive;
    final statusColor = switch (record.status) {
      TransferRecordStatus.active => accent,
      TransferRecordStatus.completed => AppColors.receive,
      TransferRecordStatus.failed => AppColors.error,
      TransferRecordStatus.cancelled => AppColors.orange,
    };

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
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(
              outgoing ? Icons.arrow_upward : Icons.arrow_downward,
              color: accent,
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
                  '${outgoing ? 'To' : 'From'} ${record.peer} · '
                  '${Format.bytes(record.sizeBytes)} · '
                  '${_time(record.timestamp)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.secondary - 1,
                    color: AppColors.secondaryText,
                  ),
                ),
                if (record.status == TransferRecordStatus.active) ...[
                  const SizedBox(height: AppSpace.sm),
                  LinearProgressIndicator(
                    value: record.progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    backgroundColor: AppColors.border,
                    color: accent,
                  ),
                ],
              ],
            ),
          ),
          Icon(
            switch (record.status) {
              TransferRecordStatus.active =>
                Icons.hourglass_top,
              TransferRecordStatus.completed => Icons.check_circle,
              TransferRecordStatus.failed => Icons.cancel,
              TransferRecordStatus.cancelled => Icons.close,
            },
            color: statusColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  String _time(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}