import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/device.dart';
import '../../models/transfer_file.dart';
import '../../models/transfer_state.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/transfer_progress.dart';
import '../../widgets/transfer_stat_card.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({
    super.key,
    required this.controller,
    required this.files,
    required this.device,
  });

  final AppController controller;
  final List<TransferFile> files;
  final TransferDevice device;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  TransferState _state = const TransferState();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _state = TransferState(
      filename: widget.files.first.name,
      totalBytes: widget.files.first.size,
      destination: widget.device.name,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await widget.controller.send(
      widget.device,
      widget.files,
      onState: (s) {
        if (mounted) setState(() => _state = s);
      },
    );
  }

  void _cancel() {
    widget.controller.cancelTransfer();
    setState(() => _state = _state.copyWith(status: TransferStatus.cancelled));
  }

  @override
  Widget build(BuildContext context) {
    final completed = _state.status == TransferStatus.completed;
    final failed = _state.status == TransferStatus.failed;
    final cancelled = _state.status == TransferStatus.cancelled;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const BackButton(color: AppColors.text),
        title: const Text(
          'Transfer in progress',
          style: TextStyle(
            fontSize: AppText.button,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              const Spacer(),
              Center(
                child: TransferProgress(
                  progress: _state.progress,
                  received: _state.bytesTransferred,
                  total: _state.totalBytes,
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                completed
                    ? 'Transfer Complete'
                    : failed
                        ? 'Transfer Failed'
                        : cancelled
                            ? 'Transfer Cancelled'
                            : _state.filename,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppText.sectionHeading,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                failed
                    ? 'Something went wrong. Try again.'
                    : cancelled
                        ? ''
                        : 'Sending to ${_state.destination}',
                style: const TextStyle(
                  fontSize: AppText.body,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Row(
                children: [
                  TransferStatCard(
                    icon: Icons.bolt,
                    value: Format.speed(_state.speed),
                    label: 'Speed',
                  ),
                  const SizedBox(width: AppSpace.md),
                  TransferStatCard(
                    icon: Icons.access_time,
                    value: _state.remaining.inSeconds >= 0
                        ? '${_state.remaining.inSeconds} sec'
                        : '—',
                    label: 'Remaining',
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              _DestinationCard(device: widget.device),
              const Spacer(),
              if (!completed && !failed && !cancelled)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text(
                      'Cancel transfer',
                      style: TextStyle(
                        fontSize: AppText.button,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: AppText.button,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.device});

  final TransferDevice device;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.smallCard),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_android, color: AppColors.primary),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: const TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                device.ip,
                style: const TextStyle(
                  fontSize: AppText.secondary - 1,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}