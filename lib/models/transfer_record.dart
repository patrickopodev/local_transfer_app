/// Direction of a finished transfer shown in the history list.
enum TransferDirection { sent, received }

/// Lifecycle state of an item in the Transfers list.
enum TransferRecordStatus { active, completed, failed, cancelled }

/// An entry in the Transfers list. Starts as [active] while in flight and
/// transitions to a terminal state when the transfer resolves.
class TransferRecord {
  final int id;

  final String filename;
  final int sizeBytes;

  /// Name of the peer device when known, else its IP.
  final String peer;

  final TransferDirection direction;
  final TransferRecordStatus status;

  /// Received/sent byte count while [status] is [TransferRecordStatus.active].
  final int bytesTransferred;

  final DateTime timestamp;

  const TransferRecord({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.peer,
    required this.direction,
    required this.status,
    required this.timestamp,
    this.bytesTransferred = 0,
  });

  double get progress =>
      sizeBytes > 0 ? (bytesTransferred / sizeBytes).clamp(0.0, 1.0) : 0.0;

  TransferRecord copyWith({
    TransferRecordStatus? status,
    int? bytesTransferred,
  }) {
    return TransferRecord(
      id: id,
      filename: filename,
      sizeBytes: sizeBytes,
      peer: peer,
      direction: direction,
      status: status ?? this.status,
      timestamp: timestamp,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    );
  }
}