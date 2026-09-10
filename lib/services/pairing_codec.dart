/// Encodes/decodes a manual pairing code so devices can connect without
/// broadcast discovery (the QR-button flow's actual payload).
///
/// Format: `localdrop://<ip>:<port>/<url-encoded name>?k=<base64 pubkey>`
/// The optional `k` query parameter carries the peer's X25519 public key so a
/// manually paired device can still negotiate an encrypted transfer.
abstract final class PairingCodec {
  static String encode(String name, String ip, int port, {String? pubkey}) {
    final encoded = Uri.encodeComponent(name);
    final query = pubkey != null && pubkey.isNotEmpty ? '?k=$pubkey' : '';
    return 'localdrop://$ip:$port/$encoded$query';
  }

  static ({String name, String ip, int port, String pubkey})? decode(
    String raw,
  ) {
    final value = raw.trim();
    if (!value.startsWith('localdrop://')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final ip = uri.host;
    final port = uri.port;
    if (ip.isEmpty || port == 0) return null;
    // pathSegments are already decoded: `/My%20Phone` → ['My Phone'].
    final name = uri.pathSegments.firstWhere(
      (s) => s.isNotEmpty,
      orElse: () => ip,
    );
    if (name.isEmpty) return null;
    final pubkey = uri.queryParameters['k'] ?? '';
    return (name: name, ip: ip, port: port, pubkey: pubkey);
  }
}