/// A device discovered on the local network that can receive files.
class TransferDevice {
  final String name;
  final String ip;
  final int port;

  /// 'Android', 'iOS', 'Windows', etc. Empty when unknown.
  final String platform;

  /// Base64 X25519 public key advertised by the peer, used to negotiate an
  /// encrypted transfer. Empty when the peer doesn't support encryption
  /// (transfers then fall back to plaintext).
  final String pubkey;

  /// Whether the peer is currently reachable/accepting transfers.
  final bool available;

  const TransferDevice({
    required this.name,
    required this.ip,
    required this.port,
    this.platform = '',
    this.pubkey = '',
    this.available = true,
  });
}
