import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/device.dart';
import '../../models/transfer_file.dart';
import '../../services/pairing_codec.dart';
import '../../theme/theme.dart';
import '../../widgets/nearby_device_card.dart';
import '../../widgets/qr_scanner.dart';
import '../transfer/transfer_screen.dart';

/// Choose which nearby device receives the selected files.
class SelectDeviceScreen extends StatefulWidget {
  const SelectDeviceScreen({
    super.key,
    required this.controller,
    required this.files,
    this.initialDevice,
  });

  final AppController controller;
  final List<TransferFile> files;
  final TransferDevice? initialDevice;

  @override
  State<SelectDeviceScreen> createState() => _SelectDeviceScreenState();
}

class _SelectDeviceScreenState extends State<SelectDeviceScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const BackButton(color: AppColors.text),
        title: const Text(
          'Select device',
          style: TextStyle(
            fontSize: AppText.button,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.md),
              child: Text(
                'Send to',
                style: TextStyle(
                  fontSize: AppText.sectionHeading,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<TransferDevice>>(
                valueListenable: widget.controller.devices,
                builder: (context, devices, _) {
                  final list = [...devices];
                  if (widget.initialDevice != null &&
                      !list.any((d) => d.ip == widget.initialDevice!.ip)) {
                    list.insert(0, widget.initialDevice!);
                  }
                  if (list.isEmpty) {
                    return const Center(
                      child: Text(
                        'Start RECEIVE on your device\nand nearby devices will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final device = list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: NearbyDeviceCard(
                          device: device,
                          onTap: () => _startTransfer(device),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Can't see your device?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => QrScanner(
                            onCodeScanned: (code) {
                              final decoded =
                                  PairingCodec.decode(code);
                              if (decoded != null) {
                                widget.controller
                                    .addPairedDevice(
                                      decoded.name,
                                      decoded.ip,
                                      decoded.port,
                                      pubkey: decoded.pubkey,
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Paired with ${decoded.name}'),
                                    ),
                                  );
                                }
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Invalid pairing code')),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner,
                        color: AppColors.primary),
                    label: const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startTransfer(TransferDevice device) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          controller: widget.controller,
          files: widget.files,
          device: device,
        ),
      ),
    );
  }
}