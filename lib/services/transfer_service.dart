import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class _DigestAccumulator implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest!;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

class TransferMeta {
  final String filename;
  final int size;
  final String checksum;

  const TransferMeta({
    required this.filename,
    required this.size,
    required this.checksum,
  });

  Map<String, Object?> toJson() => {
        'filename': filename,
        'size': size,
        'checksum': checksum,
      };

  static TransferMeta fromJson(Map<String, Object?> json) => TransferMeta(
        filename: json['filename'] as String? ?? 'unknown',
        size: json['size'] as int? ?? 0,
        checksum: json['checksum'] as String? ?? '',
      );
}

/// One-line JSON ack the receiver writes back after verifying a transfer.
class TransferAck {
  final String status;
  final String? message;

  const TransferAck({required this.status, this.message});

  bool get isOk => status == 'ok';
}

/// File transfer over raw TCP sockets (guide Section 4, Steps 4-5).
///
/// Protocol: one line of JSON metadata (`\n`-terminated) followed by the raw
/// file bytes. The receiver streams to disk, verifies the SHA-256 checksum
/// against the metadata, then replies with a one-line JSON ack
/// (`{"status":"ok"}` or `{"status":"error","message":...}`). The sender
/// half-closes its write side to signal EOF, waits for that ack, and only
/// reports success when the receiver confirmed the checksum.
class TransferService {
  static const int defaultPort = 5678;
  static const int chunkSize = 64 * 1024;

  final StreamController<ReceiveEvent> _incoming =
      StreamController<ReceiveEvent>.broadcast();

  ServerSocket? _server;
  String? _saveDirOverride;
  bool _cancelRequested = false;

  Stream<ReceiveEvent> get onIncoming => _incoming.stream;

  /// Directory used to save received files. Defaults to Downloads if the
  /// platform exposes it, otherwise the app documents directory.
  Future<Directory> resolveSaveDir() async {
    if (_saveDirOverride != null) return Directory(_saveDirOverride!);
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/received');
    await dir.create(recursive: true);
    return dir;
  }

  /// Overrides the receive directory (and returns the current override, if any).
  String? get saveDirOverride => _saveDirOverride;

  /// Sets the receive directory override; null restores the platform default.
  void setSaveDir(String? path) {
    _saveDirOverride = path;
  }

  /// Starts a TCP listener on [port] accepting file transfers.
  Future<void> start({int port = defaultPort}) async {
    await stop();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_accept);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  void _accept(Socket client) {
    _handleIncoming(client);
  }

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

    Future<void> abort() async {
      if (closed) return;
      closed = true;
      subscription?.cancel();
      client.destroy();
    }

    subscription = client.listen(
      (bytes) async {
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
              error: 'Invalid metadata header: $e',
              source: source,
            ));
            await abort();
            return;
          }

          final saveDir = await resolveSaveDir();
          target = File('${saveDir.path}/${meta!.filename}');
          sink = target!.openWrite();
          jobId = DateTime.now().microsecondsSinceEpoch;
          started = true;
          _incoming.add(
            ReceiveEvent.started(
              id: jobId,
              meta: meta!,
              savePath: target!.path,
              source: source,
            ),
          );

          final remainder = buffer.sublist(headerEnd + 1);
          buffer = <int>[];
          if (remainder.isNotEmpty) {
            sink!.add(remainder);
            received += remainder.length;
            _incoming.add(
              ReceiveEvent.progress(
                id: jobId,
                received: received,
                total: meta!.size,
              ),
            );
          }
          return;
        }

        sink!.add(bytes);
        received += bytes.length;
        _incoming.add(
          ReceiveEvent.progress(
            id: jobId,
            received: received,
            total: meta!.size,
          ),
        );
      },
      onDone: () async {
        if (!started || sink == null) {
          await abort();
          return;
        }
        await sink!.flush();
        await sink!.close();
        final ok = await _verify(target!, meta!);
        try {
          // Reply with a verification ack so the sender only reports success
          // when the checksum actually matched (send() waits on this line).
          client.add(utf8.encode(
            '${jsonEncode({
              'status': ok ? 'ok' : 'error',
              'message': ok ? null : 'checksum mismatch',
            })}\n',
          ));
          await client.flush();
        } catch (_) {
          // Peer closed early; nothing left to ack to.
        }
        _incoming.add(
          ReceiveEvent.completed(
            id: jobId,
            meta: meta!,
            savePath: target!.path,
            verified: ok,
            source: source,
          ),
        );
        await abort();
      },
      onError: (Object e) async {
        _incoming.add(ReceiveEvent.error(
          error: e.toString(),
          source: source,
          id: started ? jobId : -1,
        ));
        await abort();
      },
    );
  }

  Future<bool> _verify(File file, TransferMeta meta) async {
    try {
      final actual = await _checksum(file);
      return actual == meta.checksum;
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

  /// Aborts the currently running [send], if any. The next loop iteration
  /// stops and the socket is closed so the peer sees an early EOF.
  void cancelCurrent() {
    _cancelRequested = true;
  }

  /// Sends [file] to the destination at [ip]:[port] with a JSON metadata
  /// header. [onCancelled] fires if [cancelCurrent] was requested mid-transfer;
  /// [onDone] fires only after the receiver verifies the SHA-256 checksum and
  /// replies with a `{"status":"ok"}` ack. Throws if the receiver rejects the
  /// transfer, times out, or the ack is malformed.
  Future<void> send(
    String ip,
    int port,
    File file, {
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function()? onCancelled,
  }) async {
    final meta = TransferMeta(
      filename: file.uri.pathSegments.last,
      size: await file.length(),
      checksum: await _checksum(file),
    );

    _cancelRequested = false;
    final socket = await Socket.connect(ip, port,
        timeout: const Duration(seconds: 15));
    var cancelled = false;
    try {
      final header = '${jsonEncode(meta.toJson())}\n';
      socket.add(utf8.encode(header));
      await socket.flush();

      final raf = await file.open();
      var sent = 0;
      try {
        while (true) {
          if (_cancelRequested) {
            cancelled = true;
            break;
          }
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          socket.add(chunk);
          sent += chunk.length;
          onProgress?.call(meta.size == 0 ? 1.0 : sent / meta.size);
        }
      } finally {
        await raf.close();
      }
      await socket.flush();

      if (cancelled) {
        onCancelled?.call();
        return;
      }

      // Half-close the write side (Socket.close() shuts down only the send
      // direction) so the receiver sees EOF and verifies, then read its
      // one-line JSON ack before deciding success/failure.
      await socket.close();
      final ack = await _readAck(socket);
      if (ack.isOk) {
        onDone?.call();
      } else {
        throw Exception(
            'Receiver rejected transfer: ${ack.message ?? 'unknown reason'}');
      }
    } finally {
      try {
        socket.destroy();
      } catch (_) {
        // Socket already closed/errored; nothing more to clean up.
      }
    }
  }

  /// Reads the receiver's one-line JSON ack from [socket], with a 15s timeout.
  /// The receiver replies `{"status":"ok"}` after a verified checksum, or
  /// `{"status":"error","message":...}` on failure.
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

  int _indexOfNewline(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0a) return i;
    }
    return -1;
  }
}

sealed class ReceiveEvent {
  final int id;
  final TransferMeta meta;
  final String savePath;

  /// Peer address that sent the file ('0.0.0.0' when unknown).
  final String source;

  ReceiveEvent._({
    required this.id,
    required this.meta,
    required this.savePath,
    this.source = '0.0.0.0',
  });

  factory ReceiveEvent.started({
    required int id,
    required TransferMeta meta,
    required String savePath,
    String source,
  }) = ReceiveStarted;

  factory ReceiveEvent.progress({
    required int id,
    required int received,
    required int total,
    String source,
  }) = ReceiveProgress;

  factory ReceiveEvent.completed({
    required int id,
    required TransferMeta meta,
    required String savePath,
    required bool verified,
    String source,
  }) = ReceiveCompleted;

factory ReceiveEvent.error({
    required String error,
    String source,
    int id,
  }) = ReceiveError;
}

class ReceiveStarted extends ReceiveEvent {
  ReceiveStarted({
    required super.id,
    required super.meta,
    required super.savePath,
    super.source = '0.0.0.0',
  }) : super._();
}

class ReceiveProgress extends ReceiveEvent {
  final int received;
  final int total;

  ReceiveProgress({
    required super.id,
    required this.received,
    required this.total,
    super.source = '0.0.0.0',
  }) : super._(
          meta: TransferMeta(filename: '', size: total, checksum: ''),
          savePath: '',
        );
}

class ReceiveCompleted extends ReceiveEvent {
  final bool verified;

  ReceiveCompleted({
    required super.id,
    required super.meta,
    required super.savePath,
    required this.verified,
    super.source = '0.0.0.0',
  }) : super._();
}

class ReceiveError extends ReceiveEvent {
  final String error;

  ReceiveError({required this.error, super.source, super.id = -1})
      : super._(
          meta: TransferMeta(filename: '', size: 0, checksum: ''),
          savePath: '',
        );
}
