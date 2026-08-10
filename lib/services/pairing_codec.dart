/// Encodes/decodes a manual pairing code so devices can connect without
/// broadcast discovery (the QR-button flow's actual payload).
///
/// Format: `localdrop://<ip>:<port>/<url-encoded name>`
abstract final class PairingCodec {
  static String encode(String name, String ip, int port) {
    final encoded = Uri.encodeComponent(name);
    return 'localdrop://$ip:$port/$encoded';
  }

  static ({String name, String ip, int port})? decode(String raw) {
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
    return (name: name, ip: ip, port: port);
  }
}