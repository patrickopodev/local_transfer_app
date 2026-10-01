import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer_app/models/transfer_models.dart';
import 'package:local_transfer_app/services/transfer_service.dart';
import 'package:local_transfer_app/utils/file_name.dart';

/// Sends [source] to the receiver on [port] using a hand-rolled client so the
/// metadata header can be forged (which a real sender could not do through
/// [TransferService.send]).
Future<List<ReceiveEvent>> _rawSend({
  required int port,
  required Directory saveDir,
  required String filename,
  required File source,
  String? checksumOverride,
}) async {
  final receiver = TransferService()..setSaveDir(saveDir.path);
  await receiver.start(port: port);

  final received = <ReceiveEvent>[];
  final sub = receiver.onIncoming.listen(received.add);

  final client = await Socket.connect('127.0.0.1', port);
  final checksum =
      checksumOverride ?? sha256.convert(await source.readAsBytes()).toString();
  client.add(
    utf8.encode(
      '${jsonEncode({'filename': filename, 'size': await source.length(), 'checksum': checksum})}\n',
    ),
  );
  client.add(await source.readAsBytes());
  await client.flush();
  await client.close();
  // Give the receiver time to finish writing + verifying + acking.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  await sub.cancel();
  await receiver.stop();
  return received;
}

void main() {
  late Directory tempDir;
  late int port;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hardening_test');
    port = await _freePort();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('sanitizeFileName', () {
    test('strips path traversal segments', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(
        sanitizeFileName('..\\..\\Windows\\system32\\evil.dll'),
        'evil.dll',
      );
      expect(sanitizeFileName('a/b/c.txt'), 'c.txt');
    });

    test('strips absolute paths and drive letters', () {
      expect(sanitizeFileName('/etc/shadow'), 'shadow');
      expect(sanitizeFileName('C:\\Users\\me\\secret.png'), 'secret.png');
      expect(sanitizeFileName('C:/Users/me/secret.png'), 'secret.png');
    });

    test('strips control characters, NUL and Windows-reserved characters', () {
      expect(sanitizeFileName('bad\u0000name.txt'), 'badname.txt');
      expect(sanitizeFileName('a\nb.txt'), 'ab.txt');
      expect(sanitizeFileName('we:ird*na?me.txt'), 'weirdname.txt');
      expect(sanitizeFileName('a<b>c|d"e.txt'), 'abcde.txt');
    });

    test('never returns an empty or traversal-only name', () {
      expect(sanitizeFileName(''), 'unnamed');
      expect(sanitizeFileName('.'), 'unnamed');
      expect(sanitizeFileName('..'), 'unnamed');
      expect(sanitizeFileName('   '), 'unnamed');
      expect(sanitizeFileName('...'), 'unnamed');
      expect(sanitizeFileName('/'), 'unnamed');
    });

    test('keeps ordinary filenames, including unicode and dots', () {
      expect(sanitizeFileName('report.pdf'), 'report.pdf');
      expect(sanitizeFileName('my.holiday.photo.jpg'), 'my.holiday.photo.jpg');
      expect(sanitizeFileName('Ünïcödé näme.png'), 'Ünïcödé näme.png');
      expect(sanitizeFileName('archive.tar.gz'), 'archive.tar.gz');
      expect(sanitizeFileName('.env'), 'env');
    });
  });

  group('extension helpers', () {
    test('fileExtension lowercases and ignores dotfiles', () {
      expect(fileExtension('a.MP4'), 'mp4');
      expect(fileExtension('noext'), '');
      expect(fileExtension('.env'), '');
      expect(fileExtension('trailing.'), '');
    });

    test('classifies images and videos', () {
      expect(isVideoFile('clip.mp4'), isTrue);
      expect(isVideoFile('clip.MOV'), isTrue);
      expect(isImageFile('shot.JPEG'), isTrue);
      expect(isMediaFile('a.png'), isTrue);
      expect(isMediaFile('a.pdf'), isFalse);
      expect(isMediaFile('noext'), isFalse);
    });
  });

  group('receiver filename hardening', () {
    late File source;

    setUp(() async {
      source = File('${tempDir.path}/payload.bin')
        ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 251));
    });

    test('a traversal filename cannot escape the save directory', () async {
      final saveDir = Directory('${tempDir.path}/downloads')..createSync();
      final events = await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: '../../escaped.txt',
        source: source,
      );

      final completed = events.whereType<ReceiveCompleted>().toList();
      expect(completed, hasLength(1));
      expect(completed.single.verified, isTrue);

      // The saved file must sit directly inside saveDir.
      final savedPath = completed.single.savePath;
      expect(
        savedPath.startsWith('${saveDir.path}${Platform.pathSeparator}'),
        isTrue,
        reason: 'saved outside the save directory: $savedPath',
      );
      expect(File(savedPath).uri.pathSegments, contains('escaped.txt'));

      // Nothing was created above the save directory.
      expect(File('${tempDir.path}/escaped.txt').existsSync(), isFalse);
      expect(File('${tempDir.path}/../escaped.txt').existsSync(), isFalse);
    });

    test(
      'an absolute-path filename cannot escape the save directory',
      () async {
        final saveDir = Directory('${tempDir.path}/downloads2')..createSync();
        final events = await _rawSend(
          port: port,
          saveDir: saveDir,
          filename: '/tmp/abs-escape.txt',
          source: source,
        );

        final completed = events.whereType<ReceiveCompleted>().toList();
        expect(completed, hasLength(1));
        expect(
          completed.single.savePath.startsWith(
            '${saveDir.path}${Platform.pathSeparator}',
          ),
          isTrue,
          reason:
              'saved outside the save directory: ${completed.single.savePath}',
        );
        expect(File('/tmp/abs-escape.txt').existsSync(), isFalse);
      },
    );

    test('a duplicate filename is deduped instead of overwriting', () async {
      final saveDir = Directory('${tempDir.path}/dupes')..createSync();

      final first = await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: 'photo.jpg',
        source: source,
      );
      final second = await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: 'photo.jpg',
        source: source,
      );

      final firstPath = first.whereType<ReceiveCompleted>().single.savePath;
      final secondPath = second.whereType<ReceiveCompleted>().single.savePath;
      expect(
        firstPath,
        isNot(secondPath),
        reason: 'the second transfer clobbered the first',
      );

      // Both files survive with their original contents.
      expect(File(firstPath).existsSync(), isTrue);
      expect(File(secondPath).existsSync(), isTrue);
      expect(await File(firstPath).readAsBytes(), await source.readAsBytes());

      final names =
          saveDir.listSync().map((e) => e.uri.pathSegments.last).toList()
            ..sort();
      expect(names, ['photo (1).jpg', 'photo.jpg']);
    });

    test('a dotfile collision dedupes without splitting the name', () async {
      final saveDir = Directory('${tempDir.path}/dotfiles')..createSync();
      await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: '.env',
        source: source,
      );
      await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: '.env',
        source: source,
      );

      final names =
          saveDir.listSync().map((e) => e.uri.pathSegments.last).toList()
            ..sort();
      expect(names, ['env', 'env (1)']);
    });

    test('an empty filename still yields a usable file', () async {
      final saveDir = Directory('${tempDir.path}/emptyname')..createSync();
      final events = await _rawSend(
        port: port,
        saveDir: saveDir,
        filename: '',
        source: source,
      );

      final completed = events.whereType<ReceiveCompleted>().toList();
      expect(completed, hasLength(1));
      expect(File(completed.single.savePath).existsSync(), isTrue);
    });
  });

  group('TransferService keypair wiring', () {
    test('setKeyPair() + start() enables encrypted receive', () async {
      // Regression: start() used to forward its own (null) keyPair parameter to
      // the receiver instead of the key set via setKeyPair(), which is exactly
      // how AppController wires it. Every encrypted receive then failed with
      // "Encrypted transfer but no key available" and the sender hit an ack
      // timeout.
      final recvDir = Directory('${tempDir.path}/enc')..createSync();
      final recvKp = await X25519().newKeyPair();
      final recvPubB64 = base64Encode((await recvKp.extractPublicKey()).bytes);

      final receiver = TransferService()..setSaveDir(recvDir.path);
      receiver.setKeyPair(recvKp);
      await receiver.start(port: port);

      final received = <ReceiveEvent>[];
      final sub = receiver.onIncoming.listen(received.add);

      final source = File('${tempDir.path}/secret.bin')
        ..writeAsBytesSync(List<int>.generate(128 * 1024, (i) => i % 251));

      Object? thrown;
      try {
        final sender = TransferService()
          ..setKeyPair(await X25519().newKeyPair());
        await sender.send('127.0.0.1', port, source, peerPubkey: recvPubB64);
      } catch (e) {
        thrown = e;
      }
      await sub.cancel();
      await receiver.stop();

      expect(thrown, isNull);
      final completed = received.whereType<ReceiveCompleted>().toList();
      expect(completed, hasLength(1));
      expect(
        completed.single.verified,
        isTrue,
        reason: 'receiver could not decrypt the stream',
      );
      expect(
        await File(completed.single.savePath).readAsBytes(),
        await source.readAsBytes(),
      );
    });

    test('start(keyPair:) still overrides the key', () async {
      final recvDir = Directory('${tempDir.path}/enc2')..createSync();
      final explicitKp = await X25519().newKeyPair();
      final otherKp = await X25519().newKeyPair();
      final explicitPub = base64Encode(
        (await explicitKp.extractPublicKey()).bytes,
      );

      final receiver = TransferService()..setSaveDir(recvDir.path);
      receiver.setKeyPair(otherKp);
      await receiver.start(port: port, keyPair: explicitKp);

      final received = <ReceiveEvent>[];
      final sub = receiver.onIncoming.listen(received.add);

      final source = File('${tempDir.path}/secret2.bin')
        ..writeAsBytesSync(List<int>.generate(64 * 1024, (i) => i % 251));

      final sender = TransferService()..setKeyPair(await X25519().newKeyPair());
      await sender.send('127.0.0.1', port, source, peerPubkey: explicitPub);

      await sub.cancel();
      await receiver.stop();

      final completed = received.whereType<ReceiveCompleted>().toList();
      expect(completed, hasLength(1));
      expect(
        completed.single.verified,
        isTrue,
        reason: 'explicit keyPair argument did not take effect',
      );
    });
  });

  group('send() ack handling', () {
    test('reads the ack after half-closing the write side', () async {
      final recvDir = Directory('${tempDir.path}/ack')..createSync();
      final receiver = TransferService()..setSaveDir(recvDir.path);
      await receiver.start(port: port);

      final source = File('${tempDir.path}/ack.bin')
        ..writeAsBytesSync(List<int>.generate(256 * 1024, (i) => i % 251));

      var done = false;
      await TransferService().send(
        '127.0.0.1',
        port,
        source,
        onDone: () => done = true,
      );
      await receiver.stop();

      expect(
        done,
        isTrue,
        reason: 'the ack was lost when the socket was closed before reading',
      );
      expect(
        File('${recvDir.path}/ack.bin').readAsBytesSync(),
        await source.readAsBytes(),
      );
    });
  });
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}
