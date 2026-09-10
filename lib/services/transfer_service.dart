import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/transfer_models.dart';
import 'transfer_receiver.dart';

class TransferService {
  static const int defaultPort = 5678;
  static const int chunkSize = 64 * 1024;

  static final Chacha20 _cipher = Chacha20(macAlgorithm: MacAlgorithm.empty);

  ServerSocket? _server;
  KeyPair? _keyPair;
  bool _cancelRequested = false;
  bool _sending = false;

  bool _paused = false;

  Stream<ReceiveEvent> get onIncoming => _receiver.onIncoming;
  final TransferReceiver _receiver = TransferReceiver();

  void setKeyPair(KeyPair keyPair) => _keyPair = keyPair;

  Future<List<int>> _deriveKey(String peerPubkeyB64) async {
    final algorithm = X25519();
    final shared = await algorithm.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey:
          SimplePublicKey(base64Decode(peerPubkeyB64), type: KeyPairType.x25519),
    );
    return await shared.extractBytes();
  }

  String? get saveDirOverride => _receiver.saveDirOverride;
  void setSaveDir(String? path) => _receiver.setSaveDir(path);

  Future<void> start({int port = defaultPort, KeyPair? keyPair}) async {
    if (keyPair != null) _keyPair = keyPair;
    _receiver.setKeyPair(keyPair);
    await _receiver.start(port: port);
  }

  Future<void> stop() async {
    await _receiver.stop();
    _server?.close();
    _server = null;
  }

  void cancelCurrent() => _cancelRequested = true;

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  bool get isPaused => _paused;

  Completer<void>? _pauseCompleter;

  Future<void> send(
    String ip,
    int port,
    File file, {
    String? peerPubkey,
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function()? onCancelled,
  }) async {
    if (_sending) {
      throw StateError('A transfer is already in progress');
    }
    _sending = true;
    _cancelRequested = false;
    _paused = false;
    _pauseCompleter = null;
    try {
      final useEncryption = peerPubkey != null &&
          peerPubkey.isNotEmpty &&
          _keyPair != null;

      List<int>? keyBytes;
      List<int>? nonceBytes;
      String? selfPubkeyB64;
      if (useEncryption) {
        keyBytes = await _deriveKey(peerPubkey);
        nonceBytes = _cipher.newNonce();
        final pub = await _keyPair!.extractPublicKey();
        selfPubkeyB64 = base64Encode((pub as SimplePublicKey).bytes);
      }

      final meta = TransferMeta(
        filename: file.uri.pathSegments.last,
        size: await file.length(),
        checksum: await _checksum(file),
        encrypted: useEncryption,
        nonce: useEncryption ? base64Encode(nonceBytes!) : null,
        pubkey: useEncryption ? selfPubkeyB64 : null,
      );

      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 15));
      var cancelled = false;
      try {
        final header = '${jsonEncode(meta.toJson())}\n';
        socket.add(utf8.encode(header));
        await socket.flush();

        final plain = file.openRead();
        final body = useEncryption
            ? _cipher.encryptStream(
                plain,
                secretKey: SecretKey(keyBytes!),
                nonce: nonceBytes!,
                onMac: (_) {},
              )
            : plain;
        var sent = 0;
        await for (final chunk in body) {
          while (_paused) {
            _pauseCompleter = Completer<void>();
            await _pauseCompleter!.future;
            _pauseCompleter = null;
          }
          if (_cancelRequested) {
            cancelled = true;
            break;
          }
          socket.add(chunk);
          sent += chunk.length;
          onProgress?.call(meta.size == 0 ? 1.0 : sent / meta.size);
          await socket.flush();
        }

        await socket.flush();

        if (cancelled) {
          onCancelled?.call();
          return;
        }

        await socket.close();
        final ack = await _readAck(socket);
        if (ack.isOk) {
          onDone?.call();
        } else {
          throw Exception(
              'Receiver rejected transfer: ${ack.message ?? "unknown reason"}');
        }
      } finally {
        _sending = false;
        try { socket.destroy(); } catch (_) {}
      }
    } catch (_) {
      _sending = false;
      rethrow;
    }
  }

  Future<TransferAck> _readAck(Socket socket) async {
    try {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      return _parseAck(line);
    } on TimeoutException {
      return const TransferAck(status: 'error', message: 'ack timeout');
    } catch (_) {
      return const TransferAck(
          status: 'error', message: 'connection closed before ack');
    }
  }

  TransferAck _parseAck(String line) {
    try {
      final decoded = jsonDecode(line) as Map<String, Object?>;
      return TransferAck(
        status: decoded['status'] as String? ?? 'error',
        message: decoded['message'] as String?,
      );
    } catch (_) {
      return const TransferAck(status: 'error', message: 'malformed ack');
    }
  }

  Future<String> _checksum(File file) async {
    final raf = await file.open();
    final sink = _DigestAccumulator();
    final conv = sha256.startChunkedConversion(sink);
    try {
      while (true) {
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) break;
        conv.add(chunk);
      }
    } finally {
      await raf.close();
    }
    conv.close();
    return sink.digest.toString();
  }
}

class _DigestAccumulator implements Sink<Digest> {
  Digest? _digest;
  Digest get digest => _digest ?? Digest(Uint8List(0));
  @override
  void add(Digest data) => _digest = data;
  @override
  void close() {}
}
