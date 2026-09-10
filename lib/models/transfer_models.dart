class TransferMeta {
  final String filename;
  final int size;
  final String checksum;
  final bool encrypted;
  final String? nonce;
  final String? pubkey;

  const TransferMeta({
    required this.filename,
    required this.size,
    required this.checksum,
    this.encrypted = false,
    this.nonce,
    this.pubkey,
  });

  Map<String, Object?> toJson() => {
        'filename': filename,
        'size': size,
        'checksum': checksum,
        'encrypted': encrypted,
        if (nonce != null) 'nonce': nonce,
        if (pubkey != null) 'pubkey': pubkey,
      };

  static TransferMeta fromJson(Map<String, Object?> json) => TransferMeta(
        filename: json['filename'] as String? ?? 'unknown',
        size: json['size'] as int? ?? 0,
        checksum: json['checksum'] as String? ?? '',
        encrypted: json['encrypted'] as bool? ?? false,
        nonce: json['nonce'] as String?,
        pubkey: json['pubkey'] as String?,
      );
}

class TransferAck {
  final String status;
  final String? message;

  const TransferAck({required this.status, this.message});

  bool get isOk => status == 'ok';
}

abstract class ReceiveEvent {
  final int id;
  final TransferMeta meta;
  final String savePath;
  final String source;

  const ReceiveEvent._({
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
  const ReceiveStarted({
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

  const ReceiveCompleted({
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
