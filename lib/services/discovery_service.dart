import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';

/// Cross-platform peer discovery over the shared WiFi (dart:io only).
///
/// Each device binds a UDP socket on [broadcastPort], joins the [multicastGroup]
/// multicast group, advertises itself with a small JSON hello every 3s, and
/// listens for peers' hellos. Multicast (not directed broadcast) is used because
/// limited broadcast (255.255.255.255) is blocked on most Android/iOS WiFi
/// stacks, so a pure-broadcast implementation silently fails to discover peers
/// on phones. Expired peers are pruned after [peerTtl].
class DiscoveryService {
  static const int broadcastPort = 9260;
  static const String multicastGroup = '239.255.255.250';
  static const Duration peerTtl = Duration(seconds: 12);

  String selfName;
  final int transferPort;
  final String selfPlatform;
  String selfPubkey;

  RawDatagramSocket? _socket;
  Timer? _heartbeat;
  final Map<String, _Peer> _peers = {};
  final Set<int> _sentNonces = {};
  final StreamController<void> _changes = StreamController.broadcast();

  /// Addresses we announce to: the multicast group first, then a best-effort
  /// limited broadcast so the occasional network that forwards it still works.
  List<InternetAddress> _targets = [InternetAddress(multicastGroup)];

  Stream<void> get onChanges => _changes.stream;

  DiscoveryService({
    required this.selfName,
    required this.transferPort,
    this.selfPlatform = '',
    this.selfPubkey = '',
  });

  /// Updates the advertised name and announces it immediately so peers see the
  /// change without waiting for the next heartbeat tick.
  void setSelfName(String name) {
    if (name.isEmpty || name == selfName) return;
    selfName = name;
    _announce();
    _changes.add(null);
  }

  /// Updates the advertised public key (e.g. after it is generated late in
  /// startup) and re-announces so peers learn it without waiting for the next
  /// heartbeat.
  void setSelfPubkey(String pubkey) {
    if (pubkey == selfPubkey) return;
    selfPubkey = pubkey;
    _announce();
    _changes.add(null);
  }
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
    try {
      _socket!.joinMulticast(InternetAddress(multicastGroup));
    } catch (_) {
      // Multicast may be unsupported on some interfaces; the socket still
      // receives unicast/broadcast hellos, so discovery degrades gracefully.
    }
    _targets = [
      InternetAddress(multicastGroup),
      InternetAddress(broadcastAddress),
    ];
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

  /// Re-announces this device and drops stale peers immediately, without
  /// rebinding the socket (the Home refresh affordance).
  void refresh() {
    _prune();
    _announce();
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
      'platform': selfPlatform,
      'pubkey': selfPubkey,
      'nonce': nonce,
    });
    for (final target in _targets) {
      try {
        socket.send(utf8.encode(payload), target, broadcastPort);
      } catch (_) {
        // A target may be unreachable on some networks; keep trying the rest.
      }
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
      platform: msg.platform,
      pubkey: msg.pubkey,
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
  final String platform;
  final String pubkey;
  final DateTime seenAt;

  _Peer({
    required this.name,
    required this.ip,
    required this.port,
    required this.platform,
    required this.pubkey,
    required this.seenAt,
  });

  TransferDevice toDevice() => TransferDevice(
        name: name,
        ip: ip.address,
        port: port,
        platform: platform,
        pubkey: pubkey,
      );
}

class _Message {
  final String type;
  final String name;
  final int port;
  final String platform;
  final String pubkey;
  final int nonce;

  _Message({
    required this.type,
    required this.name,
    required this.port,
    required this.platform,
    required this.pubkey,
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
        platform: json['platform'] as String? ?? '',
        pubkey: json['pubkey'] as String? ?? '',
        nonce: json['nonce'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}