/// Direction of a finished transfer shown in the history list.
enum TransferDirection { sent, received }

/// Lifecycle state of an item in the Transfers list.
enum TransferRecordStatus { active, paused, completed, failed, cancelled }

/// An entry in the Transfers list. Starts as [active] while in flight and
/// transitions to a terminal state when the transfer resolves.
class TransferRecord {
  final int id;

  final String filename;
  final int sizeBytes;

  /// Name of the peer when known, else its IP.
  final String peer;

  final TransferDirection direction;
  final TransferRecordStatus status;

  /// Received/sent byte count while [status] is [TransferRecordStatus.active].
  final int bytesTransferred;

  /// Current transfer speed in bytes per second (while active).
  final double speed;

  /// Estimated remaining duration (while active).
  final Duration remaining;

  /// True if this transfer was paused.
  final bool isPaused;

  /// Path where the file was saved (for received transfers).
  final String? savePath;

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
    this.speed = 0,
    this.remaining = Duration.zero,
    this.isPaused = false,
    this.savePath,
  });

  double get progress =>
      sizeBytes > 0 ? (bytesTransferred / sizeBytes).clamp(0.0, 1.0) : 0.0;

  TransferRecord copyWith({
    TransferRecordStatus? status,
    int? bytesTransferred,
    double? speed,
    Duration? remaining,
    bool? isPaused,
    String? savePath,
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
      speed: speed ?? this.speed,
      remaining: remaining ?? this.remaining,
      isPaused: isPaused ?? this.isPaused,
      savePath: savePath ?? this.savePath,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'filename': filename,
        'sizeBytes': sizeBytes,
        'peer': peer,
        'direction': direction.name,
        'status': status.name,
        'bytesTransferred': bytesTransferred,
        'speed': speed,
        'remaining': remaining.inSeconds,
        'isPaused': isPaused,
        'savePath': savePath,
        'timestamp': timestamp.toIso8601String(),
      };

  static TransferRecord fromJson(Map<String, Object?> json) {
    final direction = TransferDirection.values.firstWhere(
      (d) => d.name == json['direction'],
      orElse: () => TransferDirection.sent,
    );
    final status = TransferRecordStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => TransferRecordStatus.failed,
    );
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '')
        ?? DateTime.fromMillisecondsSinceEpoch(0);
    return TransferRecord(
      id: json['id'] as int? ?? 0,
      filename: json['filename'] as String? ?? 'unknown',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      peer: json['peer'] as String? ?? '',
      direction: direction,
      status: status,
      timestamp: timestamp,
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      remaining: Duration(seconds: json['remaining'] as int? ?? 0),
      isPaused: json['isPaused'] as bool? ?? false,
      savePath: json['savePath'] as String?,
    );
  }
}