import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../services/pairing_codec.dart';
import '../services/transfer_service.dart';
import '../theme/theme.dart';
import 'qr_scanner.dart';

/// Pairing sheet behind the "Scan QR" buttons: shows this device's pairing
/// code (copyable) and lets you paste a peer's code to add them directly,
/// without depending on UDP broadcast discovery.
Future<void> showPairingSheet(
  BuildContext context,
  AppController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PairingSheet(controller: controller),
  );
}

class _PairingSheet extends StatefulWidget {
  const _PairingSheet({required this.controller});

  final AppController controller;

  @override
  State<_PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<_PairingSheet> {
  final TextEditingController _codeController = TextEditingController();
  String _myCode = '';
  String? _localIp;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMyCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadMyCode() async {
    String? ip;
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254')) {
            ip = addr.address;
            break;
          }
        }
        if (ip != null) break;
      }
    } catch (_) {
      ip = null;
    }
    final code = PairingCodec.encode(
      widget.controller.selfName,
      ip ?? '255.255.255.255',
      TransferService.defaultPort,
      pubkey: widget.controller.selfPubkey,
    );
    if (mounted) {
      setState(() {
        _localIp = ip;
        _myCode = code;
      });
    }
  }

  void _addPeer() {
    final decoded = PairingCodec.decode(_codeController.text);
    if (decoded == null) {
      setState(() => _error = 'Not a valid pairing code.');
      return;
    }
    widget.controller.addPairedDevice(
      decoded.name,
      decoded.ip,
      decoded.port,
      pubkey: decoded.pubkey,
    );
    Navigator.of(context).pop();
  }

  void _onCodeScanned(String code) {
    final decoded = PairingCodec.decode(code);
    if (decoded != null) {
      widget.controller.addPairedDevice(
        decoded.name,
        decoded.ip,
        decoded.port,
        pubkey: decoded.pubkey,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paired with ${decoded.name}'),
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid pairing code')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.xl + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner, color: AppColors.primary),
              const SizedBox(width: AppSpace.sm),
              const Text(
                'Pair with a device',
                style: TextStyle(
                  fontSize: AppText.sectionHeading,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Text(
            'Show this code on the other device, or paste theirs to add it.',
            style: TextStyle(
              fontSize: AppText.secondary,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.smallCard),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _myCode.isEmpty ? 'Resolving IP…' : _myCode,
                  style: const TextStyle(
                    fontSize: AppText.secondary,
                    fontFamily: 'monospace',
                  ),
                ),
                if (_localIp == null)
                  const Text(
                    'Local IP not found — the code above is not reachable.',
                    style: TextStyle(
                      fontSize: AppText.secondary - 1,
                      color: AppColors.error,
                    ),
                  ),
                const SizedBox(height: AppSpace.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _myCode),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pairing code copied'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy my code'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text(
            'Paste a peer\'s code',
            style: TextStyle(
              fontSize: AppText.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              hintText: 'localdrop://192.168.1.5:5678/…',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _addPeer(),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _addPeer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add device'),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QrScanner(
                      onCodeScanned: _onCodeScanned,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}