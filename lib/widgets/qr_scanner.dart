import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanner extends StatefulWidget {
  const QrScanner({super.key, required this.onCodeScanned});

  final void Function(String code) onCodeScanned;

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> {
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(facing: CameraFacing.back);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Scan QR Code',
            style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null && raw.startsWith('localdrop://')) {
              widget.onCodeScanned(raw);
              return;
            }
          }
        },
        errorBuilder: (BuildContext context, MobileScannerException exception, Widget? child) {
          return Center(
            child: Text('Camera error: ${exception.toString()}',
                style: const TextStyle(color: Colors.white)),
          );
        },
      ),
    );
  }
}
