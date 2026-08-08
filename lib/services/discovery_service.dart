import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';

/// Cross-platform peer discovery over the shared WiFi (dart:io only).
///
/// Each device binds a UDP socket on [broadcastPort], advertises itself with a
/// small JSON hello every 3s, and listens for peers' hellos. Expired peers are
/// pruned after [peerTtl]. This is the Tier-2 fallback from the guide's
/// two-tier discovery strategy, implemented without native mDNS advertising.
class DiscoveryService {
  static const int broadcastPort = 9260;
  static const Duration peerTtl = Duration(seconds: 12);

  final String selfName;
  final int transferPort;

  RawDatagramSocket? _socket;
  Timer? _heartbeat;
  final Map<String, _Peer> _peers = {};
  final Set<int> _sentNonces = {};
  final StreamController<void> _changes = StreamController.broadcast();

  Stream<void> get onChanges => _changes.stream;

  DiscoveryService({required this.selfName, required this.transferPort});

  List<TransferDevice> get peers =>
      List.unmodifiable(_peers.values.map((p) => p.toDevice()));

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      broadcastPort,
      reuseAddress: true,
      reusePort: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.listen(_onData);
    _announce();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        _prune();
        _announce();
      },
    );
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
  }

  void _announce() {
    final socket = _socket;
    if (socket == null) return;
    final nonce = DateTime.now().microsecondsSinceEpoch;
    _sentNonces.add(nonce);
    if (_sentNonces.length > 32) {
      _sentNonces.remove(_sentNonces.first);
    }
    final payload = jsonEncode({
      'type': 'transfer_app_hello',
      'name': selfName,
      'port': transferPort,
      'nonce': nonce,
    });
    try {
      socket.send(
        utf8.encode(payload),
        InternetAddress(broadcastAddress),
        broadcastPort,
      );
    } catch (_) {
      // Broadcasts can be dropped on isolated networks; that is expected.
    }
  }

  void _onData(RawSocketEvent event) {
    final socket = _socket;
    if (socket == null || event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    _handleDatagram(datagram);
  }

  void _handleDatagram(Datagram datagram) {
    final String body;
    try {
      body = utf8.decode(datagram.data);
    } catch (_) {
      return;
    }
    _Message? msg = _Message.tryParse(body);
    if (msg == null || msg.type != 'transfer_app_hello') return;
    if (_sentNonces.contains(msg.nonce)) return;

    final key = '${datagram.address.address}:${msg.port}';
    final now = DateTime.now();
    final changed = !_peers.containsKey(key) ||
        _peers[key]!.name != msg.name ||
        _peers[key]!.ip.address != datagram.address.address;

    _peers[key] = _Peer(
      name: msg.name,
      ip: datagram.address,
      port: msg.port,
      seenAt: now,
    );
    if (changed) {
      _changes.add(null);
    }
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(peerTtl);
    final before = _peers.length;
    _peers.removeWhere((_, p) => p.seenAt.isBefore(cutoff));
    if (_peers.length != before) {
      _changes.add(null);
    }
  }

  static String get broadcastAddress => '255.255.255.255';
}

class _Peer {
  final String name;
  final InternetAddress ip;
  final int port;
  final DateTime seenAt;

  _Peer({
    required this.name,
    required this.ip,
    required this.port,
    required this.seenAt,
  });

  TransferDevice toDevice() => TransferDevice(name: name, ip: ip.address, port: port);
}

class _Message {
  final String type;
  final String name;
  final int port;
  final int nonce;

  _Message({
    required this.type,
    required this.name,
    required this.port,
    required this.nonce,
  });

  static _Message? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return _Message(
        type: json['type'] as String? ?? '',
        name: json['name'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        nonce: json['nonce'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}