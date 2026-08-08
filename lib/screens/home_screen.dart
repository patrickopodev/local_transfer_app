import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController(text: 'My Device');
  final _transferService = TransferService();
  late final DiscoveryService _discovery;

  final List<_TransferView> _transfers = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _discovery = DiscoveryService(
      selfName: _nameController.text,
      transferPort: TransferService.defaultPort,
    );

    _transferService.onIncoming.listen(_handleReceiveEvent);
    _discovery.onChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _transferService.stop();
    _discovery.stop();
    _nameController.dispose();
    super.dispose();
  }

  void _handleReceiveEvent(ReceiveEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ReceiveStarted():
          _upsert(
            _TransferView(
              id: event.id,
              filename: event.meta.filename,
              total: event.meta.size,
              incoming: true,
              status: 'Receiving',
              savePath: event.savePath,
            ),
          );
        case ReceiveProgress():
          _upsert(
            _TransferView(
              id: event.id,
              filename: '',
              total: event.total,
              received: event.received,
              incoming: true,
            ),
          );
        case ReceiveCompleted():
          _upsert(
            _TransferView(
              id: event.id,
              filename: event.meta.filename,
              total: event.meta.size,
              received: event.meta.size,
              incoming: true,
              status: event.verified ? 'Verified ✓' : 'Checksum mismatch!',
              savePath: event.savePath,
              done: true,
            ),
          );
        case ReceiveError():
          _transfers.add(
            _TransferView.error(message: event.error),
          );
      }
    });
  }

  void _upsert(_TransferView view) {
    final index = _transfers.indexWhere((t) => t.id == view.id);
    if (index == -1) {
      _transfers.insert(0, view);
      return;
    }
    final existing = _transfers[index];
    existing.mergeFrom(view);
  }

  Future<void> _toggleListening() async {
    if (_running) {
      await _transferService.stop();
      await _discovery.stop();
      if (mounted) {
        setState(() => _running = false);
      }
      return;
    }

    try {
      await _transferService.start();
    } on SocketException catch (e) {
      _showSnack('Cannot listen on port ${TransferService.defaultPort}: ${e.message}');
      return;
    }
    await _discovery.start();
    if (mounted) {
      setState(() => _running = true);
    }
  }

  Future<void> _sendTo(TransferDevice device) async {
    final picked = await FilePicker.pickFiles();
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;
    final file = File(path);

    final view = _TransferView(
      id: DateTime.now().microsecondsSinceEpoch,
      filename: file.uri.pathSegments.last,
      total: await file.length(),
      incoming: false,
      status: 'Sending to ${device.name}…',
    );
    if (!mounted) return;
    setState(() => _transfers.insert(0, view));

    try {
      await _transferService.send(
        device.ip,
        device.port,
        file,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            view
              ..received = (view.total * p).round()
              ..status = 'Sending to ${device.name}';
          });
        },
      );
      if (mounted) {
        setState(() {
          view
            ..received = view.total
            ..done = true
            ..status = 'Sent ✓';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          view
            ..done = true
            ..status = 'Failed: $e';
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Transfer'),
        actions: [
          IconButton(
            icon: Icon(_running ? Icons.sensors : Icons.sensors_off),
            tooltip: _running ? 'Stop receiving' : 'Start receiving',
            onPressed: _toggleListening,
          ),
        ],
      ),
      body: Column(
        children: [
          _SelfCard(
            controller: _nameController,
            running: _running,
            port: TransferService.defaultPort,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Nearby devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          _DeviceList(
            running: _running,
            devices: _discovery.peers,
            onSend: _sendTo,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Transfers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Expanded(child: _TransferList(transfers: _transfers)),
        ],
      ),
    );
  }
}

class _SelfCard extends StatelessWidget {
  const _SelfCard({
    required this.controller,
    required this.running,
    required this.port,
  });

  final TextEditingController controller;
  final bool running;
  final int port;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Your device name',
                prefixIcon: Icon(Icons.phone_android),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  running ? Icons.sensors : Icons.sensors_off,
                  color: running ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    running
                        ? 'Listening on port $port — tap a device below to send a file.'
                        : 'Tap the sensor icon to start receiving files over this WiFi.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.running,
    required this.devices,
    required this.onSend,
  });

  final bool running;
  final List<TransferDevice> devices;
  final void Function(TransferDevice) onSend;

  @override
  Widget build(BuildContext context) {
    if (!running) return const SizedBox.shrink();
    if (devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No devices found yet — make sure the peer app is running on the same WiFi.',
        ),
      );
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final device = devices[index];
          return _DeviceCard(device: device, onTap: () => onSend(device));
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final TransferDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.devices, size: 32),
            const SizedBox(height: 8),
            Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              device.ip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferList extends StatelessWidget {
  const _TransferList({required this.transfers});

  final List<_TransferView> transfers;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return const Center(child: Text('No transfers yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: transfers.length,
      itemBuilder: (context, index) => _TransferTile(transfer: transfers[index]),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.transfer});

  final _TransferView transfer;

  @override
  Widget build(BuildContext context) {
    final progress = transfer.total == 0 ? 0.0 : transfer.received / transfer.total;
    return ListTile(
      leading: Icon(
        transfer.incoming ? Icons.south_west : Icons.north_east,
        color: transfer.done ? Colors.green : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        transfer.filename.isEmpty ? 'Transfer ${transfer.id}' : transfer.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: transfer.done
          ? Text(transfer.status)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text('${transfer.status} · ${_formatBytes(transfer.received)} / ${_formatBytes(transfer.total)}'),
              ],
            ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _TransferView {
  final int id;
  final bool incoming;
  String filename;
  int total;
  int received;
  String status;
  String savePath;
  bool done;

  _TransferView({
    required this.id,
    required this.filename,
    required this.total,
    this.received = 0,
    required this.incoming,
    this.status = '',
    this.savePath = '',
    this.done = false,
  });

  _TransferView.error({required String message})
      : id = -1,
        filename = 'Error',
        total = 0,
        received = 0,
        incoming = true,
        status = message,
        savePath = '',
        done = true;

  void mergeFrom(_TransferView other) {
    if (other.filename.isNotEmpty) filename = other.filename;
    total = other.total;
    received = other.received;
    if (other.status.isNotEmpty) status = other.status;
    if (other.savePath.isNotEmpty) savePath = other.savePath;
    done = other.done;
  }
}
