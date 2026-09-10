# LocalDrop

A Flutter app for transferring files between devices on the same local network —
no internet, no cloud, no account. Inspired by SHAREit / Blip.

## How it works

- **Discovery** — each device joins the UDP multicast group `239.255.255.250`
  on port `9260` and announces a small JSON "hello" every 3s. Peers that stop
  responding are pruned after a 12s TTL. Multicast (not limited broadcast) is
  used because `255.255.255.255` is blocked on most Android/iOS Wi-Fi stacks.
  A QR / pairing code (`localdrop://<ip>:<port>/<name>`) lets you add a peer
  manually when broadcast discovery can't reach it.
- **Transfer** — raw TCP on port `5678`. The sender writes one line of JSON
  metadata (`filename`, `size`, `checksum`, …) followed by the raw file bytes.
  The receiver streams to disk, verifies the SHA-256 checksum, and replies with
  a one-line `{"status":"ok"}` / `{"status":"error",...}` ack. The sender only
  reports success once the receiver has confirmed the checksum.
- **Encryption (optional)** — when both peers advertise support, the payload is
  encrypted with ChaCha20. Keys are negotiated per peer with X25519 (ECDH) using
  the public keys exchanged in discovery / the pairing code; the file metadata
  header stays plaintext. Transfers to peers that don't share a public key fall
  back to plaintext.
- **State** — `AppController` (`ChangeNotifier`) owns the networking services and
  the transfer history, keeping the UI decoupled from sockets. The history
  persists to disk (`transfer_history.json`) and survives restarts.

## Architecture

```
lib/
  app/         AppController (state) + AppShell (navigation)
  services/    DiscoveryService (multicast UDP) · TransferService (TCP)
  models/      TransferDevice · TransferFile · TransferRecord · TransferState
  screens/     Home · Send · SelectDevice · Transfer · Transfers · Settings
  widgets/     Cards, progress, pairing sheet, ad banner
  theme/       Colors, spacing, typography
  utils/       Byte/format helpers
```

## Getting started

```bash
flutter pub get
flutter run          # device must be on the same Wi-Fi as the receiver
```

Tap **RECEIVE** on one device, then **SEND** on the other and pick a peer from
the nearby list. Received files land in the platform Downloads folder (or the
app's documents directory where Downloads isn't available).

## Tests

```bash
flutter test
```

Covers the transfer protocol (checksum verification, rejection ack, malformed
header), the pairing codec, and the main UI flows.

## Limitations

- Plaintext fallback means transfers are not confidential when a peer doesn't
  support encryption.
- History is stored unencrypted on device.
- Discovery relies on multicast being permitted by the Wi-Fi network.
