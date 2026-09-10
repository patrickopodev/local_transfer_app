import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer_app/models/transfer_models.dart';
import 'package:local_transfer_app/services/transfer_service.dart';

void main() {
  late Directory tempDir;
  late int port;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('transfer_test');
    port = await _freePort();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('send() reports onDone only after receiver verifies checksum', () async {
    final recvDir = Directory('${tempDir.path}/recv')..createSync();
    final receiver = TransferService()..setSaveDir(recvDir.path);
    await receiver.start(port: port);

    final source = File('${tempDir.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(256 * 1024, (i) => i % 251));

    final received = <ReceiveEvent>[];
    final sub = receiver.onIncoming.listen(received.add);

    var progressSeen = false;
    var done = false;
    Object? thrown;
    try {
      await TransferService().send(
        '127.0.0.1',
        port,
        source,
        onProgress: (_) => progressSeen = true,
        onDone: () => done = true,
      );
    } catch (e) {
      thrown = e;
    }
    await sub.cancel();
    await receiver.stop();

    expect(thrown, isNull);
    expect(done, isTrue);
    expect(progressSeen, isTrue);

    final completed = received.whereType<ReceiveCompleted>().toList();
    expect(completed, hasLength(1));
    expect(completed.single.verified, isTrue);

    final saved = File(completed.single.savePath);
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsBytes(), await source.readAsBytes());
  });

  test('send() encrypts the payload with ChaCha20 when a peer key is given',
      () async {
    final recvDir = Directory('${tempDir.path}/recv')..createSync();
    final receiver = TransferService()..setSaveDir(recvDir.path);
    final recvKp = await X25519().newKeyPair();
    final recvPub = await recvKp.extractPublicKey();
    final recvPubB64 = base64Encode(recvPub.bytes);
    await receiver.start(port: port, keyPair: recvKp);

    final source = File('${tempDir.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(256 * 1024, (i) => i % 251));

    final received = <ReceiveEvent>[];
    final sub = receiver.onIncoming.listen(received.add);

    var done = false;
    Object? thrown;
    try {
      final sender = TransferService()..setKeyPair(await X25519().newKeyPair());
      await sender.send(
        '127.0.0.1',
        port,
        source,
        peerPubkey: recvPubB64,
        onDone: () => done = true,
      );
    } catch (e) {
      thrown = e;
    }
    await sub.cancel();
    await receiver.stop();

    expect(thrown, isNull);
    expect(done, isTrue);
    final completed = received.whereType<ReceiveCompleted>().toList();
    expect(completed, hasLength(1));
    expect(completed.single.verified, isTrue);
    final saved = File(completed.single.savePath);
    expect(await saved.readAsBytes(), await source.readAsBytes());
  });

  test('receiver writes an error ack when checksum does not match',
      () async {
    final receiver = TransferService()..setSaveDir(tempDir.path);
    await receiver.start(port: port);

    final source = File('${tempDir.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(64 * 1024, (i) => i % 251));
    final wrongChecksum = sha256.convert(utf8.encode('not the file')).toString();

    final client = await Socket.connect('127.0.0.1', port);
    client.add(utf8.encode('${jsonEncode({
      'filename': 'tampered.bin',
      'size': await source.length(),
      'checksum': wrongChecksum,
    })}\n'));
    final raf = await source.open();
    try {
      while (true) {
        final chunk = await raf.read(TransferService.chunkSize);
        if (chunk.isEmpty) break;
        client.add(chunk);
      }
    } finally {
      await raf.close();
    }
    await client.flush();
    // Half-close send side so the receiver verifies and acks.
    await client.close();
    final line = await client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    client.destroy();
    await receiver.stop();

    final ack = jsonDecode(line) as Map<String, Object?>;
    expect(ack['status'], 'error');
    expect(ack['message'], 'checksum mismatch');
  });

  test('send() throws when the receiver rejects the transfer', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final serverDone = Future<void>(() async {
      final client = await server.first;
      // Read the metadata header line, then drain the file bytes until EOF.
      // Parse the header from raw bytes so binary payloads never hit utf8.
      final header = Completer<String>();
      final drained = Completer<void>();
      final buffer = <int>[];
      var headerSeen = false;
      client.listen(
        (bytes) {
          if (!headerSeen) {
            buffer.addAll(bytes);
            final nl = buffer.indexOf(0x0a);
            if (nl != -1) {
              headerSeen = true;
              header.complete(
                utf8.decode(buffer.sublist(0, nl), allowMalformed: true),
              );
            }
          }
        },
        onDone: () => drained.complete(),
      );
      await header.future;
      await drained.future;
      // Reply with a rejection ack; the sender must surface this as a throw.
      client.add(utf8.encode('{"status":"error","message":"disk full"}\n'));
      await client.flush();
      client.close();
      await server.close();
    });

    final source = File('${tempDir.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(32 * 1024, (i) => i % 251));

    Object? thrown;
    var done = false;
    try {
      await TransferService().send('127.0.0.1', port, source,
          onDone: () => done = true);
    } catch (e) {
      thrown = e;
    }
    await serverDone;

    expect(done, isFalse);
    expect(thrown, isA<Exception>());
    expect('$thrown', contains('Receiver rejected transfer'));
  });

  test('receiver emits ReceiveError for a malformed header', () async {
    final receiver = TransferService()..setSaveDir(tempDir.path);
    await receiver.start(port: port);

    final received = <ReceiveEvent>[];
    final sub = receiver.onIncoming.listen(received.add);

    final client = await Socket.connect('127.0.0.1', port);
    client.add(utf8.encode('not json at all\n'));
    await client.flush();
    await client.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await sub.cancel();
    await receiver.stop();

    expect(received.whereType<ReceiveError>(), isNotEmpty);
  });

  test('send() supports pause and resume', () async {
    final recvDir = Directory('${tempDir.path}/recv')..createSync();
    final receiver = TransferService()..setSaveDir(recvDir.path);
    await receiver.start(port: port);

    final source = File('${tempDir.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(512 * 1024, (i) => i % 251));

    final received = <ReceiveEvent>[];
    final sub = receiver.onIncoming.listen(received.add);

    var done = false;
    Object? thrown;
    try {
      final sender = TransferService();
      final sendFuture = sender.send(
        '127.0.0.1',
        port,
        source,
        onDone: () => done = true,
      );
      // Let transfer start
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sender.isPaused, isFalse);
      sender.pause();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sender.isPaused, isTrue);
      sender.resume();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(sender.isPaused, isFalse);
      await sendFuture;
    } catch (e) {
      thrown = e;
    }
    await sub.cancel();
    await receiver.stop();

    expect(thrown, isNull);
    expect(done, isTrue);
  });
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}
