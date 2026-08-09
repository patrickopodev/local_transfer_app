import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/transfer_file.dart';
import '../models/transfer_record.dart';
import '../models/transfer_state.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';

/// Owns the networking services and the current-session state, keeping UI
/// decoupled from sockets (design doc §32).
class AppController extends ChangeNotifier {
  static const String defaultDeviceName = 'My Device';

  final String selfName;
  final TransferService _transferService = TransferService();
  late final DiscoveryService _discovery;

  late final ValueNotifier<List<TransferDevice>> devices;

  /// Transfers list state, newest first. Members start [active] and resolve to
  /// a terminal status, so interrupted receives still show up as failed.
  final ValueNotifier<List<TransferRecord>> history =
      ValueNotifier<List<TransferRecord>>(const []);

  final TransferState _current = const TransferState();
  TransferState get current => _current;

  bool _receiving = false;
  bool get receiving => _receiving;

  int _nextId = 0;

  /// Active (in-flight) records keyed by their record id so progress/terminal
  /// events can transition the same entry instead of appending duplicates.
  final Map<int, TransferRecord> _active = {};

  AppController({String? deviceName})
      : selfName = deviceName ?? defaultDeviceName {
    devices = ValueNotifier<List<TransferDevice>>(const []);
    _discovery = DiscoveryService(
      selfName: selfName,
      transferPort: TransferService.defaultPort,
    );
    _discovery.onChanges.listen((_) {
      devices.value = _discovery.peers;
    });
    _transferService.onIncoming.listen(_handleIncoming);
  }

  /// Starts receiving: opens the TCP listener and begins advertising on LAN.
  Future<void> start() async {
    await _transferService.start();
    await _discovery.start();
    _receiving = true;
    notifyListeners();
  }

  Future<void> stop() async {
    await _transferService.stop();
    await _discovery.stop();
    _receiving = false;
    notifyListeners();
  }

  int _newId() => _nextId++;

  /// Sends [files] to [device], emitting state snapshots via [onState].
  Future<void> send(
    TransferDevice device,
    List<TransferFile> files, {
    required void Function(TransferState state) onState,
  }) async {
    final file = files.first;
    onState(_current.copyWith(
      status: TransferStatus.connecting,
      filename: file.name,
      totalBytes: file.size,
      destination: device.name,
    ));

    final id = _newId();
    _record(TransferRecord(
      id: id,
      filename: file.name,
      sizeBytes: file.size,
      peer: device.name,
      direction: TransferDirection.sent,
      status: TransferRecordStatus.active,
      timestamp: DateTime.now(),
    ));

    final startedAt = DateTime.now();
    var lastBytes = 0;
    try {
      await _transferService.send(
        device.ip,
        device.port,
        File(file.path),
        onProgress: (p) {
          final now = DateTime.now();
          final elapsed = now.difference(startedAt).inSeconds;
          final total = file.size;
          final received = (p * total).round();
          final delta = received - lastBytes;
          final speed = elapsed > 0 ? delta / elapsed : 0.0;
          lastBytes = received;
          onState(_current.copyWith(
            status: TransferStatus.transferring,
            progress: p,
            bytesTransferred: received,
            totalBytes: total,
            speed: speed,
            remaining: speed > 0
                ? Duration(seconds: ((total - received) / speed).round())
                : Duration.zero,
            filename: file.name,
            destination: device.name,
          ));
        },
        onDone: () {
          onState(_current.copyWith(
            status: TransferStatus.completed,
            progress: 1.0,
            bytesTransferred: file.size,
            totalBytes: file.size,
            speed: 0,
            remaining: Duration.zero,
          ));
          _resolve(id, TransferRecordStatus.completed);
        },
        onCancelled: () {
          onState(_current.copyWith(
            status: TransferStatus.cancelled,
            speed: 0,
          ));
          _resolve(id, TransferRecordStatus.cancelled);
        },
      );
    } catch (_) {
      onState(_current.copyWith(status: TransferStatus.failed, speed: 0));
      _resolve(id, TransferRecordStatus.failed);
    }
  }

  void cancelTransfer() => _transferService.cancelCurrent();

  void _record(TransferRecord record) {
    _active[record.id] = record;
    history.value = [record, ...history.value];
  }

  void _resolve(int id, TransferRecordStatus status) {
    final record = _active[id];
    if (record == null) return;
    _active.remove(id);
    final resolved = record.copyWith(status: status);
    history.value =
        history.value.map((r) => r.id == id ? resolved : r).toList();
  }

  void _handleIncoming(ReceiveEvent event) {
    switch (event) {
      case ReceiveStarted():
        _record(TransferRecord(
          id: event.id,
          filename: event.meta.filename,
          sizeBytes: event.meta.size,
          peer: event.source,
          direction: TransferDirection.received,
          status: TransferRecordStatus.active,
          timestamp: DateTime.now(),
        ));
      case ReceiveProgress():
        break;
      case ReceiveCompleted():
        _resolve(
          event.id,
          event.verified
              ? TransferRecordStatus.completed
              : TransferRecordStatus.failed,
        );
      case ReceiveError():
        _resolve(event.id, TransferRecordStatus.failed);
    }
  }

  @override
  void dispose() {
    _discovery.stop();
    _transferService.stop();
    devices.dispose();
    history.dispose();
    super.dispose();
  }
}