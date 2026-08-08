# Building a Local File Transfer App in Flutter
### (Blip + SHAREit Lite style — WiFi Direct + Local Network transfer)

---

## Table of Contents

- [Quick Start: MVP Build Order](#quick-start-mvp-build-order)
- [Feature Roadmap](#feature-roadmap)
- [1. Transfer Method Comparison](#1-transfer-method-comparison)
- [2. High-Level Architecture](#2-high-level-architecture)
- [3. Recommended Packages](#3-recommended-packages-all-free-open-source)
- [4. Step-by-Step Build Guide](#4-step-by-step-build-guide)
- [5. Known Limitations to Design Around](#5-known-limitations-to-design-around)
- [6. Suggested MVP Scope](#6-suggested-mvp-scope-zero-cost-fast-validation)
- [7. Phase 2 Roadmap](#7-phase-2-roadmap)
- [8. Monetization Notes](#8-monetization-notes)
- [9. Optional: Internet Transfer (Phase 3)](#9-optional-internet-transfer-phase-3)
- [10. Optional: FTP Transfer](#10-optional-ftp-transfer-pc--browser-access)
- [11. Performance & Reliability](#11-performance--reliability-production-hardening)
- [12. Testing & Benchmarking](#12-testing--benchmarking)
- [13. Security Checklist](#13-security-checklist)
- [14. Platform-Specific Notes](#14-platform-specific-notes)
- [Appendix: Common Pitfalls](#appendix-common-pitfalls)

---

## Quick Start: MVP Build Order

This guide covers many sections, but **you don't need all of them to ship a usable app.** If you only read one part of this document before writing code, read this.

**Build these, in order, then stop and release v1:**

- [ ] Project setup (Section 4, Step 1)
- [ ] LAN sockets — basic send/receive over local WiFi (Section 4, Step 4)
- [ ] File picker (Section 3, package list; Section 4, Step 6)
- [ ] Progress UI (Section 4, Step 6)
- [ ] Checksum / metadata handshake (Section 4, Step 5)
- [ ] Testing on two real devices (Section 4, Step 7)

**Stop here and release v1.** This alone is a complete, working Snapdrop-style transfer app — same-WiFi, single file, cross-platform (Android + iOS via mDNS/sockets).

Everything else in this guide — WiFi Direct speed boost, QR pairing, encryption, resume, folders, internet transfer, FTP, hardening, benchmarking, security checklist — is **Phase 2 and beyond**. Add it based on what real users actually ask for, not because the guide includes it. Later sections are ordered roughly by cost-to-benefit, so if you do go further, working top-to-bottom is a reasonable default — but none of it is required to have a real, shippable app.

| If a user asks for... | Go to |
|---|---|
| Faster Android-to-Android transfer | `nearby_connections` WiFi Direct (Section 4, Tier 1) |
| Not wanting to wait for discovery | Section 7.1 (QR pairing) |
| "Is this safe on public WiFi?" | Section 7.3 (TLS) |
| Large file support | Section 11.1, plus Section 7.4 (resume) |
| Sending whole folders | Section 7.5 |
| Transfers across different WiFi networks | Section 9 (optional, adds a server) |
| Grabbing files from a PC without an app | Section 10 (optional FTP) |
| "Users report failed transfers" | Section 11.3 (retry) and 11.5 (integrity) |

---

## Feature Roadmap

```
                    MVP (Sections 1–6)
                         │
                         ▼
                    QR Pairing (7.1)
                         │
                         ▼
                TLS Encryption (7.3)
                         │
                         ▼
              Resumable Transfer (7.4)
                         │
                         ▼
               Folder Transfer (7.5)
                         │
                         ▼
             Background Service (7.6)
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
   Internet Transfer (9)      FTP Transfer (10)
        [optional]              [optional]
              │                     │
              └──────────┬──────────┘
                         ▼
          Production Hardening (11–13)
```

Internet Transfer (9) and FTP (10) branch off in parallel because they solve different problems — cross-network discovery vs. app-free PC access — and neither depends on the other. Both are optional add-ons to the same core MVP, not a required continuation of it.

---

## 1. Transfer Method Comparison

| Method | Speed | Setup Friction | Cross-Platform | Internet Required | Best For |
|---|---|---|---|---|---|
| **WiFi Direct** | Very fast (up to ~40+ MB/s claimed by some apps) | Medium — device pairing dialog | Android only (iOS has no public WiFi Direct API) | No | Large files, Android-to-Android |
| **Local WiFi (same router/hotspot)** | Fast (depends on router, often 10–30 MB/s) | Low — both devices just join same network | Yes (Android, iOS, desktop) | No (LAN only, no WAN) | Cross-platform transfers, web-based apps like Snapdrop |
| **Bluetooth (Classic/BLE)** | Slow (~1–3 MB/s Classic, much less on BLE) | Low — pairing required first time | Yes, but APIs differ per platform | No | Small files, low-power discovery/handshake only |
| **Bluetooth for discovery + WiFi for transfer (hybrid, SHAREit-style)** | Fast (WiFi speed) | Low-Medium | Mostly Android; iOS limited | No | Best of both — Bluetooth to discover, WiFi Direct/hotspot to move data |
| **Web-based (Snapdrop-style, WebRTC over LAN)** | Fast (near WiFi Direct speeds on same network) | Very low — just open a browser tab | Yes, all platforms including iOS | No (once page is loaded) | Cross-platform, zero-install use cases |

**Practical takeaway for your app:**
- WiFi Direct = fastest on Android, but shuts iOS out entirely.
- Bluetooth = universal but too slow for big files; good only for the discovery/handshake step.
- Local WiFi + WebRTC/socket transfer = the only approach that's genuinely fast **and** cross-platform, which is why Snapdrop and most modern "AirDrop clones" use it.

**Recommended architecture for your Flutter app:** Local WiFi network as the primary transfer layer (like Snapdrop), with WiFi Direct as an Android-only speed boost when both devices support it, and Bluetooth used only for device discovery/handshake fallback when devices aren't on the same network yet.

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────┐
│                  UI Layer                    │
│  (Device list, transfer progress, file picker)│
└───────────────────┬───────────────────────────┘
                     │
┌────────────────────▼──────────────────────────┐
│           Discovery & Connection Layer         │
│  - mDNS/NSD broadcast (like Snapdrop)          │
│  - nearby_connections plugin (Android WiFi     │
│    Direct + Bluetooth, Google Nearby API)      │
└────────────────────┬──────────────────────────┘
                      │
┌─────────────────────▼─────────────────────────┐
│              Transfer Layer                    │
│  - Socket-based file streaming (dart:io)       │
│  - Chunked transfer with progress callbacks    │
│  - Resume/retry logic                          │
└─────────────────────┬─────────────────────────┘
                       │
┌──────────────────────▼────────────────────────┐
│              Storage Layer                     │
│  - path_provider for save location             │
│  - Metadata (filename, size, checksum)          │
└─────────────────────────────────────────────────┘
```

---

## 3. Recommended Packages (all free/open-source)

| Package | Purpose |
|---|---|
| `nearby_connections` | Google Nearby Connections API — handles WiFi Direct + Bluetooth discovery/connection on Android in one API |
| `network_info_plus` | Get local IP, WiFi name, check connectivity |
| `multicast_dns` | mDNS discovery for the Snapdrop-style cross-platform fallback (works on Android + iOS) |
| `path_provider` | Access device storage paths |
| `file_picker` | Let users pick files to send |
| `permission_handler` | Request storage/location permissions (location is required for WiFi/BLE scanning on Android) |
| `dart:io` (built-in) | Raw TCP sockets for the actual byte transfer — fastest, zero dependency |
| `crypto` | Checksums to verify file integrity after transfer |

> **Note on iOS:** `nearby_connections` is Android-only under the hood (it wraps Google's Nearby API). For iOS, you'll rely on the mDNS + socket approach exclusively. This is normal — it's exactly why SHAREit and Xender have historically been weaker/absent on iOS.

---

## 4. Step-by-Step Build Guide

### Step 1 — Project Setup
```bash
flutter create local_transfer_app
cd local_transfer_app
flutter pub add nearby_connections network_info_plus multicast_dns \
  path_provider file_picker permission_handler crypto
```

### Step 2 — Android Permissions
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

### Step 3 — Device Discovery (two-tier strategy)

**Tier 1: Android-to-Android fast path** — use `nearby_connections` to advertise/discover nearby devices via WiFi Direct/Bluetooth combo:
```dart
import 'package:nearby_connections/nearby_connections.dart';

final nearby = Nearby();

void startAdvertising(String userName) {
  nearby.startAdvertising(
    userName,
    Strategy.P2P_STAR,
    onConnectionInitiated: onConnectionInitiated,
    onConnectionResult: (id, status) {},
    onDisconnected: (id) {},
  );
}

void startDiscovery() {
  nearby.startDiscovery(
    'com.yourapp.transfer',
    Strategy.P2P_STAR,
    onEndpointFound: (id, userName, serviceId) {
      // show in device list
    },
    onEndpointLost: (id) {},
  );
}
```

**Tier 2: Cross-platform fallback (Snapdrop-style)** — broadcast presence via mDNS on the shared WiFi network, then connect over raw sockets. This is what makes the app work with iOS devices too.

### Step 4 — File Transfer over Socket (cross-platform core)

**Receiver (listens for incoming connections):**
```dart
import 'dart:io';

Future<void> startServer(int port, Function(double) onProgress) async {
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
  server.listen((client) async {
    final file = File('/path/to/save/received_file');
    final sink = file.openWrite();
    int received = 0;
    await for (var data in client) {
      sink.add(data);
      received += data.length;
      onProgress(received.toDouble());
    }
    await sink.close();
  });
}
```

**Sender:**
```dart
Future<void> sendFile(String ip, int port, File file, Function(double) onProgress) async {
  final socket = await Socket.connect(ip, port);
  final stream = file.openRead();
  int sent = 0;
  final total = await file.length();
  await for (var chunk in stream) {
    socket.add(chunk);
    sent += chunk.length;
    onProgress(sent / total);
  }
  await socket.flush();
  await socket.close();
}
```

### Step 5 — Metadata Handshake
Before sending raw bytes, send a small JSON header (filename, size, checksum) so the receiver knows what to expect:
```dart
final metadata = jsonEncode({
  'filename': file.uri.pathSegments.last,
  'size': await file.length(),
  'checksum': await computeChecksum(file), // use crypto package
});
socket.write('$metadata\n'); // send header line before binary stream
```

### Step 6 — UI Layer
- Device list screen (shows discovered peers with signal/connection type icon)
- File picker → queue → progress bar per file
- Transfer history screen
- Simple "Send" / "Receive" toggle like Snapdrop's send-to-device flow

### Step 7 — Testing
- Test WiFi Direct path on two real Android devices (emulators don't support WiFi Direct/Bluetooth properly)
- Test the mDNS/socket fallback between an Android device and an iOS device (or two Android devices with WiFi Direct disabled) to confirm cross-platform path works
- Test on public/guest WiFi networks where client isolation may block device-to-device LAN traffic — have a fallback message explaining this limitation to users

---

## 5. Known Limitations to Design Around

- **Client isolation on public WiFi:** many cafes/offices block device-to-device traffic even on the same WiFi. Your app should detect connection failures gracefully and suggest creating a personal hotspot instead.
- **iOS background restrictions:** iOS aggressively kills background network activity — keep transfer UI in foreground.
- **No true WiFi Direct on iOS:** don't try to fake it; lean fully on the mDNS/socket path for any iOS involvement.
- **Location permission requirement:** Android requires location permission for BLE/WiFi scanning even though you're not using GPS — explain this clearly in your permission rationale dialog to avoid Play Store rejection or user confusion (you've dealt with this kind of permission-declaration friction before with FastEdit's `READ_MEDIA_IMAGES`).

---

## 6. Suggested MVP Scope (Zero-Cost, Fast Validation)

1. Cross-platform mDNS + socket transfer only (skip `nearby_connections`/WiFi Direct for v1)
2. Single file send/receive between two devices on the same WiFi
3. Basic progress bar + success/fail state
4. Add WiFi Direct as a v2 "speed boost" for Android-to-Android once the core cross-platform flow is proven

This mirrors your PWA-first validation approach — get the simplest cross-platform path (LAN + sockets) working before layering in the more complex, Android-only WiFi Direct optimization.

---

## 7. Phase 2 Roadmap

Once the MVP (single-file LAN transfer) is validated, build in this order — each item is sequenced so it doesn't force a rewrite of earlier work.

### 7.1 QR Code Pairing (do this first — cheap, high impact)

Skip the discovery wait entirely by encoding the receiver's connection info in a QR code.

```bash
flutter pub add qr_flutter mobile_scanner
```

**Receiver side** — generate a QR containing IP, port, and a short session token:
```dart
import 'package:qr_flutter/qr_flutter.dart';

final payload = jsonEncode({
  'ip': await getLocalIp(), // from network_info_plus
  'port': 5678,
  'token': generateSessionToken(), // random 6-digit or UUID
});

QrImageView(data: payload, size: 200);
```

**Sender side** — scan and connect directly, bypassing mDNS discovery:
```dart
import 'package:mobile_scanner/mobile_scanner.dart';

MobileScanner(
  onDetect: (capture) {
    final raw = capture.barcodes.first.rawValue;
    final data = jsonDecode(raw!);
    connectToPeer(data['ip'], data['port'], data['token']);
  },
);
```

The session token matters — without it, anyone who screenshots or glimpses the QR code could connect. Have the receiver verify the token on the first handshake packet and reject mismatches.

### 7.2 Transfer Speed + ETA Display (cheap, do alongside 7.1)

No new dependency — derive it from your existing progress callback:
```dart
class TransferStats {
  DateTime lastUpdate = DateTime.now();
  int lastBytes = 0;

  (double speedMBps, Duration eta) update(int bytesNow, int totalBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(lastUpdate).inMilliseconds / 1000;
    final deltaBytes = bytesNow - lastBytes;
    final speedMBps = elapsed > 0 ? (deltaBytes / 1048576) / elapsed : 0.0;

    final remainingBytes = totalBytes - bytesNow;
    final eta = speedMBps > 0
        ? Duration(seconds: (remainingBytes / 1048576 / speedMBps).round())
        : Duration.zero;

    lastUpdate = now;
    lastBytes = bytesNow;
    return (speedMBps, eta);
  }
}
```
Sample every ~500ms rather than on every chunk, or the number will jitter too much to read.

### 7.3 TLS Encryption for the Socket Layer

Threat model: someone else on the same WiFi (café, office, campus) sniffing traffic — not a remote attacker, since this never leaves the LAN. `SecureSocket` with a self-signed cert generated per-session covers this without needing a CA or internet access.

```dart
import 'dart:io';

// Receiver: generate a self-signed cert at app startup (once, cache it)
// Use the `basic_utils` package to generate cert+key programmatically,
// or ship a generation step via openssl in a build script.

final server = await SecureServerSocket.bind(
  InternetAddress.anyIPv4,
  port,
  SecurityContext()
    ..useCertificateChain('path/to/cert.pem')
    ..usePrivateKey('path/to/key.pem'),
);
```

```dart
// Sender: trust the specific cert fingerprint received via the QR payload
// (add a 'certFingerprint' field to the QR JSON in 7.1) rather than
// trusting any CA — this is "pinning" and is what makes a self-signed
// cert safe to use here.
final socket = await SecureSocket.connect(
  ip, port,
  onBadCertificate: (cert) => cert.sha256 == expectedFingerprint,
);
```

Do this after QR pairing (7.1) because the QR payload is the natural place to carry the cert fingerprint for pinning.

### 7.4 Pause / Resume Transfers

This is the one that changes your core transfer code, so plan it before you have too much built on top of the raw-streaming approach in Step 4.

Switch from a continuous stream to **chunked transfer with acknowledgment**:
```dart
const chunkSize = 64 * 1024; // 64KB chunks

Future<void> sendFileResumable(File file, Socket socket, int startOffset) async {
  final raf = await file.open();
  await raf.setPosition(startOffset);
  int offset = startOffset;
  final total = await file.length();

  while (offset < total) {
    final chunk = await raf.read(chunkSize);
    socket.add(chunk);
    offset += chunk.length;
    // write offset to local state (e.g. shared_preferences or a small
    // json file) so a crash/pause can resume from here
    await saveResumeState(file.path, offset);
  }
  await raf.close();
}
```
On reconnect, the sender reads the last saved offset for that file+peer and calls `setPosition()` to continue instead of restarting. The receiver needs matching logic: write to a `.part` file, track received bytes, and only rename to the final filename once the checksum (from Step 5's metadata) matches.

### 7.5 Multiple Files / Folder Transfer

Once pause/resume exists, folders are mostly a queueing problem:
- Walk the folder recursively, build a manifest (relative paths + sizes + checksums)
- Send the manifest first as JSON, then stream each file in sequence using the same resumable transfer from 7.4
- Recreate the folder structure on the receiver from the manifest's relative paths

### 7.6 Background Transfer (Android)

```bash
flutter pub add flutter_foreground_task
```
Wrap the transfer in a foreground service with a persistent notification showing progress — without this, Android's Doze/App Standby will suspend the isolate mid-transfer once the app is backgrounded. This is the most OS-fragile piece of the roadmap, so budget extra testing time across different Android OEM battery-management quirks (Samsung, Xiaomi, and Huawei are the usual troublemakers).

### 7.7 Media Viewer (nice-to-have, lowest priority)

Use `photo_view` or `video_player` to preview images/videos in the file picker queue before sending. Low technical risk, mostly UI work — good candidate for a slower week.

---

## 8. Monetization Notes

Given this app's core promise is "fast, gets out of your way," ads are highest-risk on the transfer/progress screen itself — that's the moment users are most likely to bounce if interrupted.

**Suggested structure:**
- Free tier: small banner on the history/home screen only, never during an active transfer
- One-time premium unlock: no ads, folder sync, transfer history backup, background transfer (7.6) — this is the stronger long-term revenue path since it rewards trust rather than tolerance for interruption
- Avoid rewarded ads gating core transfer features (e.g. speed, file size limits) — this is the pattern that erodes trust fastest in utility apps and drives uninstalls

Sequencing suggestion: ship 7.1–7.3 (QR pairing, speed display, encryption) as your v1.5 update — these are cheap, high-trust wins. Save 7.4–7.6 (resume, folders, background) for v2 once you have real usage data on which feature users actually ask for first.

---

## 9. Optional: Internet Transfer (Phase 3)

> **This section is explicitly optional and not part of the core architecture.** Everything in Sections 1–7 works with zero servers and zero ongoing cost — that's the guide's core strength, and this section should not be read as a requirement to build a backend. Only build this if you validate that users are actually hitting the "different network" wall often enough to justify it.
>
> **For 95% of users, the LAN/WiFi Direct version is enough.** Internet transfer is an advanced feature for the minority of users who specifically need to send files across different networks (e.g. cellular data on one end, home WiFi on the other).

### 9.1 Why a Signaling Server Is Needed

Three distinct pieces are easy to conflate — worth separating clearly:

- **Signaling**: the process of two devices that don't yet have a connection exchanging just enough information (network addresses, session descriptions) to *start* a WebRTC connection. This requires some always-reachable meeting point, since the two devices have no way to find each other directly if they're on different networks. This is the only piece that needs a server you run.
- **STUN**: a public, free service that tells a device its own public IP/port as seen from outside its router — needed because most devices are behind NAT and don't know their own externally-visible address. STUN does not touch file data at all.
- **TURN**: a relay server that forwards actual traffic between two devices when a direct peer-to-peer connection can't be established (strict NATs, symmetric NATs, some corporate firewalls). This is the only piece that costs meaningful bandwidth, because unlike signaling/STUN, file bytes actually flow through it.
- **The file transfer itself**: once signaling completes and a connection path is found (direct or via TURN), file bytes flow over a WebRTC `DataChannel` — the same peer-to-peer mechanism used in Sections 1–7, just no longer restricted to the same LAN.

### 9.2 Architecture Diagram

```
   Device A                                      Device B
      │                                              │
      ▼                                              ▼
      └──────────► WebSocket Signaling Server ◄──────┘
                    (exchanges SDP + ICE only,
                     never touches file data)

                            │
                            ▼
              WebRTC P2P Data Channel established
                            │
                            ▼
                  Direct file transfer
            (or via TURN relay if direct fails)
```

### 9.3 `flutter_webrtc` Integration

```bash
flutter pub add flutter_webrtc web_socket_channel
```

**Creating the peer connection:**
```dart
import 'package:flutter_webrtc/flutter_webrtc.dart';

final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    // TURN added conditionally — see 9.6
  ]
};

final pc = await createPeerConnection(config);
```

**DataChannel setup (sender side creates it, receiver listens for it):**
```dart
// Sender
final dc = await pc.createDataChannel(
  'fileTransfer',
  RTCDataChannelInit()..ordered = true,
);

// Receiver
pc.onDataChannel = (channel) {
  channel.onMessage = (RTCDataChannelMessage message) {
    // handle incoming chunk (message.binary)
  };
};
```

**Sending file chunks over the DataChannel** (same 64KB chunking pattern as Section 7.4's resumable transfer, reused here):
```dart
const chunkSize = 16 * 1024; // WebRTC DataChannels prefer smaller chunks than raw TCP

Future<void> sendFileOverWebRTC(File file, RTCDataChannel dc) async {
  final raf = await file.open();
  final total = await file.length();
  int sent = 0;

  while (sent < total) {
    final chunk = await raf.read(chunkSize);
    await dc.send(RTCDataChannelMessage.fromBinary(chunk));
    sent += chunk.length;
    // Optional: throttle here if dc.bufferedAmount grows too large,
    // to avoid overwhelming the channel on slower connections
  }
  await raf.close();
}
```

### 9.4 WebSocket Signaling Server (minimal, Node.js)

This server only relays small JSON messages — it never sees file content, so it can run comfortably on a free tier.

```javascript
// server.js
const { WebSocketServer } = require('ws');
const wss = new WebSocketServer({ port: process.env.PORT || 8080 });

const sessions = new Map(); // sessionId -> [socketA, socketB]

wss.on('connection', (ws) => {
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw);

    if (msg.type === 'join') {
      // Session creation and peer matching
      const peers = sessions.get(msg.sessionId) || [];
      peers.push(ws);
      sessions.set(msg.sessionId, peers);
      ws.sessionId = msg.sessionId;
      return;
    }

    // Offer/answer + ICE candidate exchange — just forward to the other peer
    if (['offer', 'answer', 'ice-candidate'].includes(msg.type)) {
      const peers = sessions.get(ws.sessionId) || [];
      peers.forEach((peer) => {
        if (peer !== ws && peer.readyState === peer.OPEN) {
          peer.send(raw);
        }
      });
    }
  });

  ws.on('close', () => {
    const peers = sessions.get(ws.sessionId) || [];
    sessions.set(ws.sessionId, peers.filter((p) => p !== ws));
  });
});
```

**Flutter side — connecting and exchanging SDP/ICE:**
```dart
final channel = WebSocketChannel.connect(Uri.parse('wss://your-server.com'));

channel.sink.add(jsonEncode({'type': 'join', 'sessionId': sessionId}));

pc.onIceCandidate = (candidate) {
  channel.sink.add(jsonEncode({
    'type': 'ice-candidate',
    'candidate': candidate.toMap(),
  }));
};

channel.stream.listen((raw) async {
  final msg = jsonDecode(raw);
  if (msg['type'] == 'offer') {
    await pc.setRemoteDescription(RTCSessionDescription(msg['sdp'], 'offer'));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    channel.sink.add(jsonEncode({'type': 'answer', 'sdp': answer.sdp}));
  } else if (msg['type'] == 'answer') {
    await pc.setRemoteDescription(RTCSessionDescription(msg['sdp'], 'answer'));
  } else if (msg['type'] == 'ice-candidate') {
    await pc.addCandidate(RTCIceCandidate(
      msg['candidate']['candidate'],
      msg['candidate']['sdpMid'],
      msg['candidate']['sdpMLineIndex'],
    ));
  }
});
```

*(A Dart-based signaling server using `shelf_web_socket` follows the identical message-relay logic if you'd rather keep the whole stack in Dart — same session-map pattern, just Dart syntax instead of Node.)*

### 9.5 STUN Configuration

```dart
'iceServers': [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
]
```

Google's public STUN servers are free, require no signup, and are reliable enough for production use — they're widely used by real-world WebRTC apps, not just prototypes. STUN alone is sufficient whenever at least one device is behind a "normal" (non-symmetric) NAT, which covers the large majority of home WiFi and mobile carrier connections. It only fails under stricter NAT types (common on some corporate/university networks), which is exactly the case TURN exists for.

### 9.6 TURN Support (Optional, Off by Default)

Only needed when both devices are behind NATs strict enough that direct peer-to-peer connection fails even with STUN's help — in practice, a minority of connections.

```dart
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    if (turnEnabled) {
      'urls': 'turn:your-turn-server.com:3478',
      'username': turnUsername,
      'credential': turnCredential,
    },
  ]
};
```

Keep `turnEnabled` a deliberate flag, not a default — gate it behind a "premium" or "advanced" setting, since every byte relayed through TURN is a byte you're paying to move. A free tier like Metered's (~50GB/month free) is fine for light usage, but should never be the assumed path for every internet transfer.

### 9.7 Connection Flow

```
Connect
   │
   ▼
Signaling Server (exchange SDP)
   │
   ▼
Exchange ICE candidates
   │
   ▼
Direct P2P connection possible?
   │
   ├── Yes → Transfer directly (free, fast)
   │
   └── No  → TURN relay (if enabled) → Transfer via relay (costs bandwidth)
```

### 9.8 Cost Considerations

| Component | Cost | Notes |
|---|---|---|
| Signaling server | Very low | Only relays small JSON messages; free-tier hosting (Render, Fly.io) is sufficient even at moderate scale |
| STUN | Free | Google's public servers, no signup, no usage limit for reasonable use |
| TURN | Potentially expensive | Actual file bytes flow through it — cost scales directly with how often direct P2P fails and how large the relayed files are. Gate behind opt-in/premium rather than enabling by default |

**Bottom line:** signaling + STUN keep this feature close to free. TURN is the only piece that can meaningfully cost money, and it's the one piece you control via a feature flag — so there's no scenario where shipping Section 9 forces you into unpredictable server bills, as long as TURN stays opt-in.

---

## 10. Optional: FTP Transfer (PC / Browser Access)

> Like Section 9, this is optional and additive — it doesn't replace anything in the core architecture. It solves a different problem: letting a **PC** pull files off the phone without installing any app, using tools already built into every operating system (Windows Explorer, macOS Finder, Linux file managers all support `ftp://` addresses natively).

### 10.1 Why FTP

This is the same pattern apps like "WiFi File Transfer" and ES File Explorer's FTP mode use: the phone runs a small FTP server, and the PC connects to it with an address like `ftp://192.168.1.42:2121` typed directly into its file manager — no app install, no account, no internet. It's a good complement to Sections 1–7 rather than a replacement: use WebRTC/socket transfer for phone-to-phone, and this for phone-to-PC.

**Alternative worth knowing about:** a simple built-in HTTP server (phone serves a file-listing webpage, PC opens it in any browser) accomplishes almost the same thing with far less protocol complexity, and doesn't require the PC's file manager to support FTP specifically. If your main goal is "let a PC grab a file quickly," HTTP is usually the simpler build. FTP is worth the extra complexity mainly if you want PCs to *upload* into a real mounted network-drive experience (drag-and-drop into a Explorer/Finder window), which native FTP support gives you for free and HTTP doesn't.

### 10.2 Architecture

```
   PC (Explorer / Finder / any FTP client)
              │
              │  ftp://192.168.1.42:2121
              ▼
   Phone: Lightweight FTP Server (dart:io sockets)
              │
              ▼
   Local file storage (same storage layer as Section 1's architecture)
```

This slots in as a new module alongside the existing Discovery/Transfer/Storage layers — it reuses the same Storage Layer from Section 2, just exposes it over FTP instead of (or in addition to) the app's own protocol.

### 10.3 Minimal FTP Server (Dart, `dart:io`)

There isn't a mature, actively-maintained FTP *server* package for Flutter, so this is implemented directly on raw sockets — it's more reliable than depending on an unmaintained package, and the protocol subset you actually need (login, list, download, upload) is small.

```dart
import 'dart:io';
import 'dart:convert';

class SimpleFtpServer {
  final int controlPort;
  final Directory rootDir;
  final String username;
  final String password;

  SimpleFtpServer({
    required this.controlPort,
    required this.rootDir,
    required this.username,
    required this.password,
  });

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, controlPort);
    server.listen(_handleClient);
  }

  void _handleClient(Socket client) {
    bool authenticated = false;
    String? pendingUser;
    Directory currentDir = rootDir;
    ServerSocket? dataServer;

    client.write('220 Ready\r\n');

    client.listen((data) async {
      final line = utf8.decode(data).trim();
      final parts = line.split(' ');
      final cmd = parts[0].toUpperCase();
      final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      switch (cmd) {
        case 'USER':
          pendingUser = arg;
          client.write('331 Password required\r\n');
          break;

        case 'PASS':
          if (pendingUser == username && arg == password) {
            authenticated = true;
            client.write('230 Logged in\r\n');
          } else {
            client.write('530 Login incorrect\r\n');
          }
          break;

        case 'PASV':
          if (!authenticated) return client.write('530 Not logged in\r\n');
          dataServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
          final ip = (client.address as InternetAddress).address.replaceAll('.', ',');
          final port = dataServer!.port;
          final p1 = port ~/ 256, p2 = port % 256;
          client.write('227 Entering Passive Mode ($ip,$p1,$p2)\r\n');
          break;

        case 'LIST':
          if (!authenticated || dataServer == null) return;
          client.write('150 Opening data connection\r\n');
          final dataSocket = await dataServer!.first;
          for (var entity in currentDir.listSync()) {
            final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final isDir = entity is Directory;
            dataSocket.write('${isDir ? "d" : "-"}rw-r--r-- 1 owner group 0 Jan 1 00:00 $name\r\n');
          }
          await dataSocket.close();
          client.write('226 Transfer complete\r\n');
          break;

        case 'RETR': // download from phone
          if (!authenticated || dataServer == null) return;
          final file = File('${currentDir.path}/$arg');
          if (!file.existsSync()) return client.write('550 File not found\r\n');
          client.write('150 Opening data connection\r\n');
          final dataSocket = await dataServer!.first;
          await dataSocket.addStream(file.openRead());
          await dataSocket.close();
          client.write('226 Transfer complete\r\n');
          break;

        case 'STOR': // upload to phone
          if (!authenticated || dataServer == null) return;
          client.write('150 Opening data connection\r\n');
          final dataSocket = await dataServer!.first;
          final sink = File('${currentDir.path}/$arg').openWrite();
          await sink.addStream(dataSocket);
          await sink.close();
          client.write('226 Transfer complete\r\n');
          break;

        case 'PWD':
          client.write('257 "${currentDir.path}"\r\n');
          break;

        case 'QUIT':
          client.write('221 Goodbye\r\n');
          client.close();
          break;

        default:
          client.write('502 Command not implemented\r\n');
      }
    });
  }
}
```

**Starting the server** (e.g. from a "PC Access" toggle in Settings):
```dart
final ftp = SimpleFtpServer(
  controlPort: 2121,
  rootDir: await getApplicationDocumentsDirectory(),
  username: 'transfer',
  password: generateSessionPassword(), // show this + IP on-screen as a QR/text
);
await ftp.start();
```

This covers the commands needed for basic browsing, download, and upload (`USER`/`PASS`, `PASV`, `LIST`, `RETR`, `STOR`, `PWD`, `QUIT`). A production version should also handle `CWD` (change directory), `TYPE` (binary/ASCII mode — always accept and treat as binary), and `SIZE`, but the above is enough for Explorer/Finder to connect, list, and transfer files.

### 10.4 Security Note

Standard FTP is unencrypted — credentials and file contents are sent in plaintext. This is generally an acceptable tradeoff *only* because this is LAN-only, session-scoped (random password shown per-session, like the QR flow in 9.1), and never exposed to the internet. Do not port-forward this server or expose it beyond the local network. If you want encryption, FTPS (FTP-over-TLS) is possible with `SecureServerSocket` following the same pattern as Section 7.3, but adds meaningful complexity for a feature whose main value is convenience — most users' home/office WiFi is an acceptable trust boundary for this use case, the same assumption Sections 1–7 already make.

### 10.5 Where This Fits

Treat this as a toggle-on module ("Enable PC Access" in Settings) rather than always-running — an FTP server listening on a phone by default is both a battery drain and a larger attack surface than necessary. Start it only while the settings screen showing the connection details is open, and stop it when the user backs out or after an idle timeout.

---

## 11. Performance & Reliability (Production Hardening)

> These aren't MVP requirements — everything in Sections 1–10 works without this section. This is what separates "works in a demo" from "works reliably for a stranger's random 40GB video file on a flaky connection." Build this after you have real usage data showing where transfers actually fail, rather than guessing upfront.

### 11.1 Memory-Efficient Streaming for Large Files (10–100 GB)

The chunked patterns in Sections 4 and 7.4 already avoid loading whole files into memory, but a few details matter more as file size grows:

- **Never call `file.readAsBytes()`** on anything above a few MB — it loads the entire file into memory at once. Always use `file.openRead()` / `RandomAccessFile.read()` as shown in earlier sections.
- **Watch `Socket`/`DataChannel` buffering.** If you write chunks faster than the network can send them, Dart buffers them in memory internally, which can balloon usage on a slow link. Check `socket.bufferedAmount` (or the WebRTC equivalent) periodically and pause reading from disk when it's high:
```dart
Future<void> sendWithBackpressure(File file, Socket socket) async {
  final raf = await file.open();
  int offset = 0;
  final total = await file.length();

  while (offset < total) {
    // simple backpressure: if socket's internal buffer is large, wait
    while (socket.bufferedAmount != null && socket.bufferedAmount! > 2 * 1024 * 1024) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final chunk = await raf.read(64 * 1024);
    socket.add(chunk);
    offset += chunk.length;
  }
  await raf.close();
}
```
- **Checksum incrementally, not all at once.** For 10GB+ files, don't hash the whole file in one call after the fact — feed it through the hash function chunk-by-chunk as you read it, using `crypto`'s streaming API (`AccumulatorSink` + `Hash.startChunkedConversion`), so verification doesn't require a second full pass over the file.

### 11.2 Adaptive Chunk Sizes

A fixed chunk size (Sections 4/7/9 use 64KB or 16KB) is fine as a starting point, but a production version benefits from adjusting based on measured throughput — larger chunks reduce per-chunk overhead on fast/stable links, smaller chunks reduce wasted retransmission on flaky ones.

```dart
class AdaptiveChunker {
  int chunkSize = 64 * 1024; // start at 64KB
  static const int minChunk = 16 * 1024;
  static const int maxChunk = 1024 * 1024;

  void onChunkResult({required bool succeeded, required Duration transferTime}) {
    if (!succeeded) {
      chunkSize = (chunkSize ~/ 2).clamp(minChunk, maxChunk);
      return;
    }
    // if a chunk transferred quickly relative to size, grow; if slow, shrink
    final mbps = (chunkSize / 1048576) / (transferTime.inMilliseconds / 1000);
    if (mbps > 8) {
      chunkSize = (chunkSize * 2).clamp(minChunk, maxChunk);
    } else if (mbps < 1) {
      chunkSize = (chunkSize ~/ 2).clamp(minChunk, maxChunk);
    }
  }
}
```
Reassess every N chunks (e.g. every 20) rather than every single one, so the size doesn't oscillate on normal jitter.

### 11.3 Automatic Retry After Network Interruption

Layer this on top of the resumable transfer from Section 7.4 — retries are really just "resume, but triggered automatically instead of by user action."

```dart
Future<void> transferWithRetry(
  Future<void> Function(int startOffset) attemptTransfer,
  int startOffset, {
  int maxRetries = 5,
}) async {
  int attempt = 0;
  int offset = startOffset;

  while (attempt < maxRetries) {
    try {
      await attemptTransfer(offset);
      return; // success
    } catch (e) {
      attempt++;
      offset = await loadLastSavedOffset(); // from Section 7.4's saved state
      final backoff = Duration(seconds: (1 << attempt).clamp(1, 30)); // exponential backoff, capped
      await Future.delayed(backoff);
    }
  }
  throw Exception('Transfer failed after $maxRetries attempts');
}
```
Exponential backoff (capped, as above) avoids hammering a connection that's still recovering — this matters especially on mobile networks where a brief handoff between towers or a WiFi-to-cellular switch is common and usually self-resolves within a few seconds.

### 11.4 Battery Optimization During Transfer

- **Avoid polling loops.** Anywhere you're tempted to `Timer.periodic` and check status every 100ms, prefer stream-based/event-driven callbacks (as used throughout this guide) — polling keeps the CPU awake even when nothing has changed.
- **Batch UI updates.** Updating a progress bar on every single chunk (potentially thousands of times per second on fast links) causes excessive rebuilds. Throttle UI updates to ~4–10 times per second regardless of how often chunks actually arrive.
- **Respect Doze/App Standby intentionally.** Section 7.6's foreground service is the correct way to stay alive during an active transfer — but make sure the service stops immediately when the transfer completes or is cancelled. A foreground service left running is one of the most common causes of battery complaints in file-transfer apps' Play Store reviews.
- **Screen wake lock, scoped tightly.** If you keep the screen on during transfer (common in similar apps so users can see progress), use `wakelock_plus` and release it the moment the transfer ends or the app backgrounds — never hold it as a blanket app-wide setting.

### 11.5 File Integrity Verification & Recovery

Building on the checksum metadata from Section 5 (single-file) and the manifest from Section 7.5 (folders):

- **Verify per-file, not just per-transfer.** For folder transfers, check each file's checksum independently as it completes, rather than waiting until the whole folder finishes — this lets you flag and re-request just the one corrupted file instead of restarting everything.
- **On mismatch, don't silently discard.** Keep the `.part` file (from 7.4) and re-request only the byte range that's actually suspect if your protocol supports range requests, or the whole file if not — but always tell the user which file failed rather than failing silently.
- **Corruption vs. incomplete are different failures.** An incomplete transfer (connection dropped) should resume from the saved offset. A checksum *mismatch* on a file that reports as "complete" suggests actual corruption (rare, but possible on unreliable WiFi hardware) — this should trigger a full re-transfer of that file, not a resume, since you can't trust the offset data is bit-accurate.

```dart
enum TransferFailureType { incomplete, corrupted, networkLost }

Future<TransferFailureType> diagnoseFailed(File partFile, int expectedSize, String expectedChecksum) async {
  final actualSize = await partFile.length();
  if (actualSize < expectedSize) return TransferFailureType.incomplete;

  final actualChecksum = await computeChecksumStreaming(partFile); // from 11.1
  if (actualChecksum != expectedChecksum) return TransferFailureType.corrupted;

  return TransferFailureType.networkLost; // sized correctly but never confirmed complete
}
```

### 11.6 Suggested Build Order for This Section

Not all of 11.1–11.5 carry equal weight — if prioritizing:
1. **11.3 (retry logic)** — highest impact relative to effort, directly reduces support complaints about failed transfers
2. **11.5 (integrity verification)** — builds on checksums you already have from Section 5, mostly wiring rather than new concepts
3. **11.1 (memory efficiency)** — only urgent once users start sending genuinely large files (multi-GB video, backups)
4. **11.4 (battery)** — mostly small, cheap fixes throughout the codebase rather than one feature to build
5. **11.2 (adaptive chunking)** — the most "nice to have" of the five; fixed chunk sizes work acceptably for most real-world connections

---

## 12. Testing & Benchmarking

> As with Section 11, this is a reference guide's version of "eat your vegetables" — not required for v1, but valuable once you're deciding whether performance work (Section 11) is actually paying off.

### 12.1 What to Measure

| Metric | Why it matters |
|---|---|
| Throughput (MB/s) | The headline number users compare against SHAREit/Xender |
| Time-to-first-byte | How long discovery + handshake takes before transfer even starts — often the bigger complaint than raw speed |
| Memory usage over time | Should stay flat regardless of file size if Section 11.1's streaming approach is implemented correctly — a rising memory graph across a transfer signals a buffering bug |
| CPU usage | Encryption (7.3) and checksumming (Section 5) are the likely CPU spikes — worth confirming they don't cause visible UI jank |
| Battery drain per GB transferred | Best measured via Android Studio's Energy Profiler across a fixed, repeatable transfer |

### 12.2 Suggested Test Matrix

| Network | Expected result |
|---|---|
| WiFi 5 (802.11ac), both devices on same router | Baseline — should approach the 10–30 MB/s range from Section 1's table |
| WiFi 6 (802.11ax), same router | Modest improvement over WiFi 5 on file transfer specifically — WiFi 6's biggest gains are in dense multi-device environments, not single-transfer throughput, so don't expect a dramatic jump |
| Mobile hotspot (one device sharing cellular) | Meaningfully slower and less consistent — good test for Section 11.3's retry logic and 11.2's adaptive chunking |
| Public WiFi with client isolation enabled | Should fail gracefully with a clear error (see Section 4's known limitations) rather than hanging silently |

**File size tiers:** test at minimum 10MB (typical photo batch), 1GB (video), 10GB (large video/backup), and 50GB (edge case) — the jump from "works at 1GB" to "works at 50GB" is exactly where Section 11.1's memory-efficiency work either pays off or reveals itself as necessary.

### 12.3 How to Measure

- **Throughput/time-to-first-byte**: timestamp logging around the existing `TransferStats` class from Section 7.2 — no new tooling needed, just log to a file during test runs instead of only displaying live.
- **Memory/CPU**: Android Studio's **Profiler** tab (free, built into the IDE) — attach to the running app during a transfer and watch the memory graph specifically for a rising baseline rather than expected sawtooth GC patterns.
- **Battery**: Android Studio's **Energy Profiler**, or `adb shell dumpsys batterystats` for a coarser before/after comparison across a fixed transfer.
- **iOS-side measurement**: Xcode's Instruments (Allocations + Energy Log templates) — necessary since Android Studio's profiler only covers the Android side of a cross-platform transfer.

### 12.4 Regression Testing

Once you have a baseline from the matrix above, keep a simple log (spreadsheet or even a markdown table in your repo) of throughput per network type per app version — this is what tells you whether a "performance improvement" in Section 11 actually improved anything, versus just adding complexity. This matters more than it sounds: adaptive chunking (11.2) in particular is easy to implement in a way that helps on some networks and hurts on others, and you won't know which without before/after numbers.

---

## 13. Security Checklist

> A consolidated checklist pulling together security-relevant details scattered across earlier sections, plus a few additions worth deciding on deliberately rather than by default.

| Item | Covered in | Status to aim for |
|---|---|---|
| Transfer encryption (LAN) | Section 7.3 | TLS with cert pinning via QR payload |
| Session-scoped credentials | Sections 7.1, 10.3 | Random per-session token/password, never hardcoded or reused |
| FTP server default state | Section 10.5 | Off by default, toggle-on only |
| TURN relay default state | Section 9.6 | Off by default, opt-in only |

**Additional items worth deliberate decisions:**

- **Session expiration.** QR pairing tokens (7.1) and FTP session passwords (10.3) should expire — a reasonable default is invalidating them after first successful connection, or after a short timeout (e.g. 5 minutes) if unused. An indefinitely-valid token defeats the purpose of generating one per session.
- **Device trust list.** For repeat transfers between the same two devices, consider letting users mark a device as "trusted" after a successful transfer, storing its identifier (not just IP, since IPs change across sessions) so future connections can skip re-pairing. Keep this opt-in and make the list visible/editable in Settings — silent auto-trust is a bad default for anything accepting incoming connections.
- **Protection against repeated connection attempts.** Both the FTP server (Section 10.3) and the signaling-based flow (Section 9) currently have no attempt limiting — add a simple counter that temporarily blocks an IP after a handful of failed auth attempts (e.g. 5 failures → 60 second lockout) to blunt basic brute-forcing of the session password/token.
- **Rate limiting.** Mostly relevant if you build the signaling server from Section 9.4 — since it's a shared always-on service (even on a free tier), add basic per-IP request rate limiting at the WebSocket layer to prevent one misbehaving client from degrading the server for others. Not needed for the LAN-only pieces (Sections 1–7, 10), since there's no shared server to protect there.

None of these are complex to add individually, but they're the kind of details that are easy to skip under deadline pressure — worth a deliberate pass before considering the app "production security reviewed," particularly if the FTP server (10) or signaling server (9) modules are enabled.

---

## 14. Platform-Specific Notes

### 14.1 Android

- **Android 13 (API 33)+**: Photo/video picker changes mean `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` replace the old blanket `READ_EXTERNAL_STORAGE` for media access — you've already navigated this exact permission split with FastEdit, and the same granular-permission pattern applies here for any file picker/gallery access this app needs.
- **Android 12 (API 31)+**: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, and `BLUETOOTH_CONNECT` (already listed in Section 3, Step 2) replaced the old blanket `BLUETOOTH`/`BLUETOOTH_ADMIN` permissions for apps targeting this API level or higher — both old and new permissions are listed in the manifest for backward compatibility, but runtime request logic should target the new granular set.
- **Android 13+**: `NEARBY_WIFI_DEVICES` (also in Section 3, Step 2) is the newer permission specifically for WiFi-based nearby device discovery — using it (with the `neverForLocation` manifest flag, if your discovery genuinely doesn't derive physical location) lets you avoid requesting `ACCESS_FINE_LOCATION` on newer OS versions, which is a meaningfully better permissions story for Play Store review and user trust than the older location-based scanning requirement Section 3 lists as the baseline.
- **Android 14 (API 34)+**: Foreground service types are mandatory to declare (relevant to Section 7.6's background transfer) — you must declare `dataSync` or a similarly appropriate foreground service type in the manifest, or the service will be rejected at runtime.

### 14.2 iOS

- **Local Network permission**: iOS 14+ requires an explicit user-facing permission prompt (triggered automatically the first time the app performs local network discovery, e.g. the mDNS approach from Section 3) — add a clear `NSLocalNetworkUsageDescription` string in `Info.plist` explaining why (e.g. "Used to discover nearby devices for file transfer on the same WiFi network"), since a vague or missing description is a common App Store review rejection reason.
- **Bonjour services**: if using mDNS/NSD (Section 3's cross-platform discovery tier), iOS also requires declaring the specific Bonjour service type in `NSBonjourServices` in `Info.plist` — without this, discovery will silently fail on iOS even with Local Network permission granted.
- **Background execution**: iOS's background execution model is significantly stricter than Android's foreground-service approach (Section 7.6) — there's no direct iOS equivalent that keeps an arbitrary socket transfer alive indefinitely in the background. Realistically, plan for iOS transfers to require the app to stay in the foreground, and communicate this clearly in-app rather than attempting to replicate Android's background behavior.
- **No WiFi Direct equivalent**: reiterating from Section 1 — iOS has no public API for WiFi Direct, so the `nearby_connections` fast-path (Section 3, Tier 1) is Android-only by platform limitation, not a gap in this guide.

### 14.3 Desktop (Windows/macOS) — If Extending Later

If a future version adds Flutter desktop targets rather than only mobile:

- **Windows**: local network discovery (mDNS) generally works without special entitlements, but Windows Firewall will prompt on first run for any app opening a listening socket (Sections 3–4, 9, 10) — this is expected and not something to suppress, since silently bypassing it would be a red flag to security-conscious users.
- **macOS**: similar to iOS, macOS (particularly 10.15+) requires Local Network permission for LAN discovery, and sandboxed Mac App Store builds need the `com.apple.security.network.client`/`server` entitlements declared explicitly, or socket operations will fail silently.
- **FTP server (Section 10) is most useful here**: desktop platforms are exactly where Section 10's "no app needed on the receiving end" value proposition is strongest, since Windows Explorer and macOS Finder both support `ftp://` natively — worth prioritizing if desktop support is added, since it's a smaller lift than porting the full app UI.

---

## Appendix: Common Pitfalls

Mistakes that are easy to make even when following this guide section-by-section — worth a final pass before shipping.

| Pitfall | Why it hurts | Where the fix lives |
|---|---|---|
| Calling `file.readAsBytes()` on large files | Loads the entire file into memory at once — fine at a few MB, fatal at multi-GB, causing crashes or severe jank on lower-end devices | Section 11.1 — always stream via `openRead()`/`RandomAccessFile.read()` |
| Updating the UI on every chunk | Thousands of `setState()` calls per second on a fast link causes excessive rebuilds and visible jank, even though the transfer itself is fine | Section 11.4 — throttle UI updates to ~4–10 times per second |
| Forgetting to close sockets | Leaks file descriptors and keeps ports bound, which surfaces as mysterious "address already in use" errors on the next transfer attempt, especially during development when you're restarting frequently | Always pair `Socket.connect`/`ServerSocket.bind` with a `finally` block that calls `.close()`, even on the error paths in Sections 4 and 7.4 |
| Assuming WiFi Direct works on iOS | It doesn't — there's no public API — so any code path assuming `nearby_connections`-style discovery will silently fail or never trigger on iOS if this isn't branched on explicitly | Section 1's comparison table and Section 14.2 — always route iOS through the mDNS/socket path from Section 3, Tier 2 |
| Forgetting to verify checksums | A transfer that "completes" isn't the same as a transfer that's byte-correct — silent corruption is rare but real on flaky WiFi hardware, and skipping verification means you'll only find out from a confused user with a broken file | Section 5 (metadata handshake) and Section 11.5 (distinguishing incomplete vs. corrupted) |
| Requesting `ACCESS_FINE_LOCATION` when `NEARBY_WIFI_DEVICES` would do | Broader permission than necessary invites both user distrust and closer Play Store review scrutiny, for no functional benefit if your discovery doesn't need actual location | Section 14.1 — use `NEARBY_WIFI_DEVICES` with `neverForLocation` where the OS version supports it |
| Running the FTP server or signaling connection by default | Unnecessary battery drain and larger attack surface than the feature's actual usage justifies | Sections 10.5 and 13 — both should be toggle-on, off by default |
| Treating TURN as the default connection path | Every byte relayed through TURN costs you bandwidth — if it's not gated behind opt-in, a handful of users on strict NATs can generate outsized server costs | Section 9.6 — TURN stays behind an explicit flag, never the default |
| Skipping real-device testing for WiFi Direct/Bluetooth | Emulators don't support WiFi Direct or Bluetooth properly, so bugs here only surface on physical hardware, often late | Section 4, Step 7 |
