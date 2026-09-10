import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../models/transfer_models.dart';

class TransferReceiver {
  static const int defaultPort = 5678;
  static const int chunkSize = 64 * 1024;
  static int _nextJobId = 0;
  static int _nextJobIdSync() => _nextJobId++;

  final StreamController<ReceiveEvent> _incoming =
      StreamController<ReceiveEvent>.broadcast();
  ServerSocket? _server;
  String? _saveDirOverride;
  KeyPair? _keyPair;

  Stream<ReceiveEvent> get onIncoming => _incoming.stream;

  String? get saveDirOverride => _saveDirOverride;

  void setKeyPair(KeyPair? keyPair) => _keyPair = keyPair;

  void setSaveDir(String? path) {
    _saveDirOverride = path;
  }

  Future<void> start({int port = defaultPort}) async {
    await stop();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_accept);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  void _accept(Socket client) => _handleIncoming(client);

  Future<void> _handleIncoming(Socket client) async {
    final source = client.remoteAddress.address;
    var buffer = <int>[];
    TransferMeta? meta;
    IOSink? sink;
    File? target;
    var received = 0;
    var jobId = 0;
    var started = false;
    var closed = false;
    StreamSubscription<List<int>>? subscription;
    final body = StreamController<List<int>>();
    StreamSubscription? bodySub;
    final bodyCompleter = Completer<void>();

    Future<void> abort() async {
      if (closed) return;
      closed = true;
      subscription?.cancel();
      await bodySub?.cancel();
      try { await body.close(); } catch (_) {}
      client.destroy();
    }

    void handleBodyChunk(List<int> chunk) {
      try {
        sink!.add(chunk);
        received += chunk.length;
        _incoming.add(ReceiveEvent.progress(
          id: jobId, received: received, total: meta!.size));
      } catch (e) {
        _incoming.add(ReceiveEvent.error(
          error: 'Failed to write chunk: $e', source: source, id: jobId));
        abort();
      }
    }

    void setupBody() {
      if (meta!.encrypted) {
        if (meta!.nonce == null || meta!.pubkey == null || _keyPair == null) {
          _incoming.add(ReceiveEvent.error(
            error: 'Encrypted transfer but no key available',
            source: source,
            id: jobId,
          ));
          abort();
          return;
        }
        _deriveKey(meta!.pubkey!).then((keyBytes) {
          if (closed) return;
          bodySub = _cipher
              .decryptStream(
                body.stream,
                secretKey: SecretKey(keyBytes),
                nonce: base64Decode(meta!.nonce!),
                mac: Mac.empty,
              )
              .listen((chunk) {
                try { handleBodyChunk(chunk); } catch (_) {}
              }, onDone: () { if (!closed) bodyCompleter.complete(); },
                  onError: (e) { if (!closed) bodyCompleter.completeError(e); });
        }).catchError((e) {
          if (closed) return;
          _incoming.add(ReceiveEvent.error(
            error: 'Key derivation failed: $e', source: source, id: jobId));
          abort();
        });
      } else {
        bodySub = body.stream.listen((chunk) {
          try { handleBodyChunk(chunk); } catch (_) {}
        }, onDone: () { if (!closed) bodyCompleter.complete(); },
            onError: (e) { if (!closed) bodyCompleter.completeError(e); });
      }
    }

    subscription = client.listen(
      (bytes) async {
        subscription?.pause();
        try {
          if (meta == null) {
            buffer.addAll(bytes);
            final headerEnd = _indexOfNewline(buffer);
            if (headerEnd == -1) return;
            final headerLine =
                utf8.decode(buffer.sublist(0, headerEnd), allowMalformed: true);
            try {
              meta = TransferMeta.fromJson(
                jsonDecode(headerLine) as Map<String, Object?>,
              );
            } catch (e) {
              _incoming.add(ReceiveEvent.error(
                error: 'Invalid metadata header: $e', source: source));
              await abort();
              return;
            }
            final saveDir = await resolveSaveDir();
            target = File('${saveDir.path}/${meta!.filename}');
            sink = target!.openWrite();
            jobId = _nextJobIdSync();
            started = true;
            _incoming.add(ReceiveEvent.started(
              id: jobId, meta: meta!, savePath: target!.path, source: source));
            setupBody();
            final remainder = buffer.sublist(headerEnd + 1);
            buffer = <int>[];
            if (remainder.isNotEmpty) body.add(remainder);
            return;
          }
          body.add(bytes);
        } finally {
          if (!closed) subscription?.resume();
        }
      },
      onDone: () async {
        if (!started || sink == null) { await abort(); return; }
        try {
          await body.close();
          await bodyCompleter.future;
        } catch (_) {}
        await sink!.flush();
        await sink!.close();
        final ok = await _verify(target!, meta!);
        try {
          client.add(utf8.encode(
            '${jsonEncode({'status': ok ? 'ok' : 'error',
              'message': ok ? null : 'checksum mismatch'})}\n'));
          await client.flush();
        } catch (_) {}
        _incoming.add(ReceiveEvent.completed(
          id: jobId, meta: meta!, savePath: target!.path,
          verified: ok, source: source));
        await abort();
      },
      onError: (Object e) async {
        _incoming.add(ReceiveEvent.error(
          error: e.toString(), source: source,
          id: started ? jobId : -1));
        await abort();
      },
    );
  }

  static final Chacha20 _cipher = Chacha20(macAlgorithm: MacAlgorithm.empty);

  Future<List<int>> _deriveKey(String peerPubkeyB64) async {
    final algorithm = X25519();
    final shared = await algorithm.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey:
          SimplePublicKey(base64Decode(peerPubkeyB64), type: KeyPairType.x25519),
    );
    return await shared.extractBytes();
  }

  Future<bool> _verify(File file, TransferMeta meta) async {
    try {
      return await _checksum(file) == meta.checksum;
    } catch (_) {
      return false;
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

  Future<Directory> resolveSaveDir() async {
    if (_saveDirOverride != null) return Directory(_saveDirOverride!);
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/received');
    await dir.create(recursive: true);
    return dir;
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

int _indexOfNewline(List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0a) return i;
  }
  return -1;
}
