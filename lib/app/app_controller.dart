import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/device.dart';
import '../models/transfer_file.dart';
import '../models/transfer_models.dart';
import '../models/transfer_record.dart';
import '../models/transfer_state.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';

/// Owns the networking services and the current-session state, keeping UI
/// decoupled from sockets (design doc §32).
class AppController extends ChangeNotifier {
  static const String defaultDeviceName = 'My Device';

  /// Human-readable OS label advertised to peers so the device list can show a
  /// platform-specific icon. Wrapped so non-IO platforms (e.g. test shells)
  /// fall back to an empty label rather than throwing.
  static String get _platformName {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return '';
    }
  }

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

  /// Path to the on-disk history log; resolved lazily on first use.
  File? _historyFile;

  bool _receiving = false;
  bool get receiving => _receiving;

  /// Set when the last [start] attempt failed to open the listener/discovery,
  /// so the UI can surface a reason instead of an unhandled exception.
  String? _receiveError;
  String? get receiveError => _receiveError;

  bool _busy = false;
  bool _stopRequested = false;
  int _nextId = 0;

  /// Base64 X25519 public key advertised to peers so transfers can be
  /// encrypted. Empty until [init] generates the keypair (encryption is then
  /// unavailable and transfers fall back to plaintext).
  String _selfPubkey = '';
  String get selfPubkey => _selfPubkey;

  /// Active (in-flight) records keyed by their record id so progress/terminal
  /// events can transition the same entry instead of appending duplicates.
  final Map<int, TransferRecord> _active = {};

  AppController({String? deviceName})
      : selfName = deviceName ?? defaultDeviceName {
    devices = ValueNotifier<List<TransferDevice>>(const []);
    _discovery = DiscoveryService(
      selfName: selfName,
      transferPort: TransferService.defaultPort,
      selfPlatform: _platformName,
    );
    _discovery.onChanges.listen((_) {
      devices.value = _discovery.peers;
    });
    _transferService.onIncoming.listen(_handleIncoming);
  }

  /// Loads the persisted transfer history (if any) and generates the keypair
  /// used to negotiate encrypted transfers, before networking starts. Safe to
  /// call once at launch; failures are swallowed so a missing log or a failing
  /// key generation never blocks the app (transfers then fall back to
  /// plaintext).
  Future<void> init() async {
    await _generateKeyPair();
    await _loadHistory();
  }

  Future<void> _generateKeyPair() async {
    try {
      final keyPair = await X25519().newKeyPair();
      final pub = await keyPair.extractPublicKey();
      _selfPubkey = base64Encode(pub.bytes);
      _transferService.setKeyPair(keyPair);
      _discovery.setSelfPubkey(_selfPubkey);
    } catch (_) {
      // Encryption is optional; a failure just disables it.
    }
  }

  /// Starts receiving: opens the TCP listener and begins advertising on LAN.
  ///
  /// Idempotent — safe to call repeatedly (a no-op when already receiving),
  /// serialized so double-taps can't double-bind sockets, and it never throws:
  /// a failure is recorded in [receiveError] so the UI can show a snackbar
  /// instead of crashing with an unhandled async exception.
  ///
  /// If [stop] is requested while this is still starting up, the teardown is
  /// deferred until start() finishes instead of being silently dropped.
  Future<void> start() async {
    if (_busy || _receiving) return;
    _busy = true;
    _stopRequested = false;
    _receiveError = null;
    try {
      await _transferService.start();
      try {
        await _discovery.start();
      } catch (_) {
        await _transferService.stop();
        rethrow;
      }
      _receiving = true;
    } catch (e) {
      _receiving = false;
      _receiveError = e.toString();
    } finally {
      _busy = false;
      if (_stopRequested) {
        _stopRequested = false;
        await stop();
      }
      notifyListeners();
    }
  }

  /// Re-announces this device and prunes stale peers without tearing down the
  /// listener (the refresh button on Home).
  void refresh() {
    _discovery.refresh();
    notifyListeners();
  }

  Future<void> stop() async {
    // If start() is still binding sockets, remember the intent and let start()
    // finish the teardown itself so we never double-close or leave _receiving
    // stuck true.
    _stopRequested = true;
    if (_busy) return;
    _busy = true;
    try {
      await _transferService.stop();
      await _discovery.stop();
    } finally {
      _receiving = false;
      _receiveError = null;
      _busy = false;
      notifyListeners();
    }
  }

  int _newId() => _nextId++;

  /// Sends [files] to [device] sequentially, emitting state snapshots via
  /// [onState]. Each file gets its own history entry that resolves to a
  /// terminal status. The shared [_current] state always describes the file
  /// being transferred right now, so the transfer screen tracks the whole.
  Future<void> send(
    TransferDevice device,
    List<TransferFile> files, {
    required void Function(TransferState state) onState,
  }) async {
    for (final file in files) {
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

      // Sequential: each file streams on its own socket and completes (or
      // fails) before the next one starts. A cancel aborts the whole batch,
      // not just the in-flight file.
      final cancelled = await _sendOne(
        device,
        file,
        id,
        onState,
        peerPubkey: device.pubkey,
      );
      if (cancelled) break;
    }
  }

  /// Returns true if the transfer was cancelled mid-flight (so the caller can
  /// stop sending the remaining files in the batch).
  Future<bool> _sendOne(
    TransferDevice device,
    TransferFile file,
    int id,
    void Function(TransferState) onState, {
    String? peerPubkey,
  }) async {
    final startedAt = DateTime.now();
    var lastBytes = 0;
    var lastTime = startedAt;
    var wasCancelled = false;
    try {
      await _transferService.send(
        device.ip,
        device.port,
        File(file.path),
        peerPubkey: peerPubkey,
        onProgress: (p) {
          final now = DateTime.now();
          final total = file.size;
          final received = (p * total).round();
          final delta = received - lastBytes;
          // Speed is bytes since the previous tick over the real elapsed time
          // of that tick — not over the whole transfer — so it tracks the
          // live throughput instead of the decaying average.
          final dt = now.difference(lastTime).inMilliseconds / 1000.0;
          final speed = dt > 0 ? delta / dt : 0.0;
          lastBytes = received;
          lastTime = now;
          _updateProgress(id, bytesTransferred: received);
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
            filename: file.name,
            destination: device.name,
          ));
          _resolve(id, TransferRecordStatus.completed);
        },
        onCancelled: () {
          wasCancelled = true;
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
    return wasCancelled;
  }

  void cancelTransfer() {
    _transferService.cancelCurrent();
  }

  void pauseTransfer() {
    _transferService.pause();
    _updateActivePaused(true);
  }

  void resumeTransfer() {
    _transferService.resume();
    _updateActivePaused(false);
  }

  void _updateActivePaused(bool paused) {
    final active = _active.values.toList();
    for (final record in active) {
      final updated = record.copyWith(isPaused: paused);
      _active[record.id] = updated;
      history.value =
          history.value.map((r) => r.id == record.id ? updated : r).toList();
    }
    _persistHistory();
  }

  bool get isTransferPaused => _transferService.isPaused;

  /// Changes the advertised device name (persists for this session and is
  /// announced immediately on the LAN).
  void setDeviceName(String name) {
    _discovery.setSelfName(name);
    notifyListeners();
  }

  String? get saveDirOverride => _transferService.saveDirOverride;

  /// Overrides (or clears, when [path] is null) the receive directory.
  void setSaveDir(String? path) {
    _transferService.setSaveDir(path);
    notifyListeners();
  }

  /// Adds a peer manually (e.g. from a scanned pairing code) so it appears in
  /// the device list even if UDP broadcast discovery hasn't seen it. Replaces
  /// the entry if one with the same ip:port already exists. [pubkey] enables an
  /// encrypted transfer to the paired peer.
  void addPairedDevice(String name, String ip, int port, {String pubkey = ''}) {
    final devices = [...this.devices.value];
    final key = '$ip:$port';
    final existingIndex = devices.indexWhere(
      (d) => '${d.ip}:${d.port}' == key,
    );
    final entry = TransferDevice(name: name, ip: ip, port: port, pubkey: pubkey);
    if (existingIndex == -1) {
      devices.insert(0, entry);
    } else {
      devices[existingIndex] = entry;
    }
    this.devices.value = devices;
    notifyListeners();
  }

  void _record(TransferRecord record) {
    _active[record.id] = record;
    history.value = [record, ...history.value];
    _persistHistory();
  }

  void _resolve(int id, TransferRecordStatus status) {
    final record = _active[id];
    if (record == null) return;
    _active.remove(id);
    final resolved = record.copyWith(status: status);
    history.value =
        history.value.map((r) => r.id == id ? resolved : r).toList();
    _persistHistory();
  }

  Future<File> _resolveHistoryFile() async {
    _historyFile ??= File(
      '${(await getApplicationDocumentsDirectory()).path}/transfer_history.json',
    );
    return _historyFile!;
  }

  /// Reads the history log written by [_persistHistory]. Any entry still marked
  /// [active] (the app must have restarted mid-transfer) is downgraded to
  /// [failed] so the UI never shows a stuck progress bar.
  Future<void> _loadHistory() async {
    try {
      final file = await _resolveHistoryFile();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      final records = json
          .map((e) => TransferRecord.fromJson(e as Map<String, Object?>))
          .map((r) => r.status == TransferRecordStatus.active
              ? r.copyWith(status: TransferRecordStatus.failed)
              : r)
          .toList();
      if (records.isNotEmpty) history.value = records;
    } catch (_) {
      // Corrupt or unreadable log — start fresh rather than crash.
    }
  }

  /// Writes the current history to disk. Best-effort: I/O errors are ignored so
  /// a full disk or denied permission never breaks an in-flight transfer.
  Future<void> _persistHistory() async {
    try {
      final file = await _resolveHistoryFile();
      await file.writeAsString(
        jsonEncode(history.value.map((r) => r.toJson()).toList()),
      );
    } catch (_) {
      // Non-fatal: history is a convenience, not required for transfers.
    }
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
          savePath: event.savePath,
        ));
        break;
      case ReceiveProgress():
        _updateProgress(event.id, bytesTransferred: event.received);
        break;
      case ReceiveCompleted():
        _resolve(
          event.id,
          event.verified
              ? TransferRecordStatus.completed
              : TransferRecordStatus.failed,
        );
        break;
      case ReceiveError():
        _resolve(event.id, TransferRecordStatus.failed);
        break;
    }
  }

  void _updateProgress(int id, {required int bytesTransferred}) {
    final record = _active[id];
    if (record == null) return;
    final updated = record.copyWith(bytesTransferred: bytesTransferred);
    _active[id] = updated;
    history.value =
        history.value.map((r) => r.id == id ? updated : r).toList();
  }

  @override
  void dispose() {
    try {
      _discovery.stop();
    } catch (_) {}
    try {
      _transferService.stop();
    } catch (_) {}
    devices.dispose();
    history.dispose();
    super.dispose();
  }
}