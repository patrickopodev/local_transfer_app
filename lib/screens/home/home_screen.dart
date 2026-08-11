import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../config/ad_units.dart';
import '../../models/device.dart';
import '../../theme/theme.dart';
import '../../widgets/action_card.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/nearby_device_card.dart';
import '../../widgets/pairing_sheet.dart';
import '../send/send_files_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.devices,
  });

  final AppController controller;
  final List<TransferDevice> devices;

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner,
                  color: AppColors.primary),
              title: const Text('Pair with a device'),
              subtitle: const Text('Share or paste a pairing code'),
              onTap: () {
                Navigator.of(context).pop();
                showPairingSheet(context, controller);
              },
            ),
            ListTile(
              leading: Icon(
                controller.receiving
                    ? Icons.sensors_off
                    : Icons.sensors,
                color: AppColors.primary,
              ),
              title: Text(
                controller.receiving ? 'Stop receiving' : 'Start receiving',
              ),
              subtitle: const Text(
                'Open the TCP listener and advertise on LAN',
              ),
              onTap: () {
                Navigator.of(context).pop();
                if (controller.receiving) {
                  controller.stop();
                } else {
                  controller.start();
                }
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }

  /// Toggles receiving with visible feedback; failures surface via a snackbar
  /// instead of an unhandled exception crashing the app.
  Future<void> _toggleReceive(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (controller.receiving) {
      await controller.stop();
      messenger.showSnackBar(
        const SnackBar(content: Text('No longer receiving')),
      );
    } else {
      await controller.start();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            controller.receiveError != null
                ? 'Could not start receiving: ${controller.receiveError}'
                : 'Receiving — nearby devices can send you files',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth =
        (screenWidth - AppSpace.xl * 2).clamp(0.0, double.infinity);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl, AppSpace.lg, AppSpace.xl, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AppLogo(),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Scan QR',
                              onPressed: () =>
                                  showPairingSheet(context, controller),
                              icon: const Icon(Icons.qr_code_scanner,
                                  size: 24),
                              color: AppColors.text,
                            ),
                            IconButton(
                              tooltip: 'More',
                              onPressed: () => _showMore(context),
                              icon: const Icon(Icons.more_vert, size: 24),
                              color: AppColors.text,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Transfer files instantly\nNo internet required',
                      style: TextStyle(
                        fontSize: AppText.body,
                        color: AppColors.secondaryText,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    SizedBox(
                      width: cardWidth,
                      child: ActionCard(
                        title: 'SEND',
                        subtitle: 'Files to device',
                        icon: Icons.arrow_upward,
                        color: AppColors.primary,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SendFilesScreen(
                                controller: controller,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    SizedBox(
                      width: cardWidth,
                      child: ActionCard(
                        title: 'RECEIVE',
                        subtitle: 'Files from device',
                        icon: Icons.arrow_downward,
                        color: AppColors.receive,
                        onTap: () => _toggleReceive(context),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.smallCard),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const AdBanner(
                        adUnitId: AdConfig.homeMediumRectangle,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Nearby devices',
                      style: TextStyle(
                        fontSize: AppText.sectionHeading,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: controller.refresh,
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl, AppSpace.xs, AppSpace.xl, AppSpace.xxl),
              sliver: SliverList.builder(
                itemCount: devices.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _DevicesHint(
                      receiving: controller.receiving,
                      empty: devices.isEmpty,
                    );
                  }
                  final device = devices[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: NearbyDeviceCard(
                      device: device,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SendFilesScreen(
                              controller: controller,
                              initialDevice: device,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesHint extends StatelessWidget {
  const _DevicesHint({required this.receiving, required this.empty});

  final bool receiving;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.smallCard),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          !receiving
              ? 'Tap RECEIVE to start sharing and discover nearby devices.'
              : empty
                  ? 'No devices found yet — make sure LocalDrop is running on the other device.'
                  : 'Tap a device to send a file.',
          style: const TextStyle(
            fontSize: AppText.secondary,
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}