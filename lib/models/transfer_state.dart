/// Lifecycle of a single file transfer.
enum TransferStatus {
  idle,
  connecting,
  transferring,
  completed,
  failed,
  cancelled,
}

/// Snapshot of a transfer shown by the UI.
class TransferState {
  final TransferStatus status;
  final double progress;
  final int bytesTransferred;
  final int totalBytes;
  final double speed;
  final Duration remaining;
  final String filename;
  final String destination;

  const TransferState({
    this.status = TransferStatus.idle,
    this.progress = 0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.remaining = Duration.zero,
    this.filename = '',
    this.destination = '',
  });

  bool get isActive =>
      status == TransferStatus.connecting ||
      status == TransferStatus.transferring;

  TransferState copyWith({
    TransferStatus? status,
    double? progress,
    int? bytesTransferred,
    int? totalBytes,
    double? speed,
    Duration? remaining,
    String? filename,
    String? destination,
  }) {
    return TransferState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      speed: speed ?? this.speed,
      remaining: remaining ?? this.remaining,
      filename: filename ?? this.filename,
      destination: destination ?? this.destination,
    );
  }
}