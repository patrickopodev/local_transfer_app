import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app/app_controller.dart';
import '../../config/ad_units.dart';
import '../../models/transfer_record.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/ad_banner.dart';

/// History of transfers (design doc §3, Transfers tab) with a status filter.
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

enum _TransferFilter { all, active, completed, failed }

class _TransfersScreenState extends State<TransfersScreen> {
  _TransferFilter _filter = _TransferFilter.all;

  bool _matches(TransferRecord record) => switch (_filter) {
        _TransferFilter.all => true,
        _TransferFilter.active =>
          record.status == TransferRecordStatus.active ||
              record.status == TransferRecordStatus.paused,
        _TransferFilter.completed =>
          record.status == TransferRecordStatus.completed,
        _TransferFilter.failed =>
          record.status == TransferRecordStatus.failed ||
              record.status == TransferRecordStatus.cancelled,
      };

  String _label(_TransferFilter f) => switch (f) {
        _TransferFilter.all => 'All',
        _TransferFilter.active => 'Active',
        _TransferFilter.completed => 'Completed',
        _TransferFilter.failed => 'Failed',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<List<TransferRecord>>(
          valueListenable: widget.controller.history,
          builder: (context, records, _) {
            final filtered = records.where(_matches).toList();
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: _Header(),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl, 0, AppSpace.xl, AppSpace.lg),
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _TransferFilter.values.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpace.sm),
                        itemBuilder: (context, i) {
                          final f = _TransferFilter.values[i];
                          return ChoiceChip(
                            label: Text(_label(f)),
                            visualDensity: VisualDensity.compact,
                            selected: _filter == f,
                            onSelected: (_) =>
                                setState(() => _filter = f),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      title: _filter == _TransferFilter.all && records.isEmpty
                          ? 'No transfers yet'
                          : 'No ${_filter.name} transfers',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: _TransferRow(record: filtered[i]),
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
  const _EmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 48, color: AppColors.secondaryText),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: AppText.sectionHeading,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            const Text(
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
      TransferRecordStatus.paused => AppColors.orange,
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
               TransferRecordStatus.paused => Icons.pause_circle_filled,
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