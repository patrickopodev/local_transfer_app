import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer_app/models/transfer_record.dart';

void main() {
  test('TransferRecord toJson/fromJson round-trips', () {
    final record = TransferRecord(
      id: 1,
      filename: 'test.bin',
      sizeBytes: 1024,
      peer: '192.168.1.5',
      direction: TransferDirection.received,
      status: TransferRecordStatus.completed,
      timestamp: DateTime(2025, 1, 1, 12, 0, 0),
      bytesTransferred: 1024,
      speed: 100.0,
      remaining: Duration(seconds: 0),
      isPaused: false,
      savePath: '/storage/test.bin',
    );
    final json = record.toJson();
    final decoded = TransferRecord.fromJson(json);
    expect(decoded.id, record.id);
    expect(decoded.filename, record.filename);
    expect(decoded.sizeBytes, record.sizeBytes);
    expect(decoded.peer, record.peer);
    expect(decoded.direction, record.direction);
    expect(decoded.status, record.status);
    expect(decoded.bytesTransferred, record.bytesTransferred);
    expect(decoded.speed, record.speed);
    expect(decoded.remaining, record.remaining);
    expect(decoded.isPaused, record.isPaused);
    expect(decoded.savePath, record.savePath);
  });

  test('TransferRecord.fromJson degrades gracefully for old records missing new fields',
      () {
    final json = {
      'id': 1,
      'filename': 'old.bin',
      'sizeBytes': 512,
      'peer': '192.168.1.1',
      'direction': 'received',
      'status': 'completed',
      'bytesTransferred': 512,
      'timestamp': '2025-01-01T00:00:00.000',
    };
    final record = TransferRecord.fromJson(json);
    expect(record.speed, 0);
    expect(record.remaining, Duration.zero);
    expect(record.isPaused, isFalse);
    expect(record.savePath, isNull);
  });

  test('TransferRecord.copyWith preserves unspecified fields', () {
    final record = TransferRecord(
      id: 1,
      filename: 'test.bin',
      sizeBytes: 1024,
      peer: '192.168.1.5',
      direction: TransferDirection.sent,
      status: TransferRecordStatus.active,
      timestamp: DateTime.now(),
      bytesTransferred: 512,
      speed: 50.0,
      remaining: Duration(seconds: 10),
      isPaused: true,
      savePath: '/storage/test.bin',
    );
    final updated = record.copyWith(status: TransferRecordStatus.completed);
    expect(updated.status, TransferRecordStatus.completed);
    expect(updated.bytesTransferred, 512);
    expect(updated.speed, 50.0);
    expect(updated.isPaused, true);
    expect(updated.savePath, '/storage/test.bin');
  });
}
