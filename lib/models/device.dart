/// A device discovered on the local network that can receive files.
class TransferDevice {
  final String name;
  final String ip;
  final int port;

  /// 'Android', 'iOS', 'Windows', etc. Empty when unknown.
  final String platform;

  /// Whether the peer is currently reachable/accepting transfers.
  final bool available;

  const TransferDevice({
    required this.name,
    required this.ip,
    required this.port,
    this.platform = '',
    this.available = true,
  });
}
