import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'workflow_client.dart';

/// Tracks only this account's confirmed active case. GPS never edits the event.
class CitizenSosTracker extends ValueNotifier<List<Map<String, dynamic>>> {
  CitizenSosTracker() : super([]);
  String? _owner;
  Timer? _timer;
  StreamSubscription<Position>? _gps;
  Position? _latest;
  bool _busy = false, _sending = false, _disposed = false;
  bool _permissionAsked = false;
  int _generation = 0;
  String? get caseId => value.isEmpty ? null : value.first['id'] as String;

  void replace(String? owner, List<Map<String, dynamic>> rows) {
    if (!_disposed && owner != null && owner == _owner) value = rows;
  }

  void configure(String? owner) {
    if (_owner == owner) return;
    _owner = owner;
    _generation++;
    _timer?.cancel();
    _gps?.cancel();
    _gps = null;
    _latest = null;
    _permissionAsked = false;
    value = [];
    if (owner == null) return;
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_owner == null || _busy || _disposed) return;
    _busy = true;
    final ticket = _generation;
    try {
      final rows = await WorkflowClient.list('/my-sos');
      if (_disposed || ticket != _generation) return;
      value = rows;
      if (rows.isEmpty) {
        await _gps?.cancel();
        _gps = null;
        _latest = null;
      } else {
        await _startGps();
        await _publish();
      }
    } catch (_) {
      // A network failure must not enable a second SOS or erase its state.
    } finally {
      _busy = false;
    }
  }

  Future<void> _startGps() async {
    if (_gps != null) return;
    final ticket = _generation;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && !_permissionAsked) {
      _permissionAsked = true;
      permission = await Geolocator.requestPermission();
    }
    if (_disposed ||
        ticket != _generation ||
        caseId == null ||
        ![
          LocationPermission.always,
          LocationPermission.whileInUse,
        ].contains(permission)) {
      return;
    }
    _gps =
        Geolocator.getPositionStream(
          locationSettings: defaultTargetPlatform == TargetPlatform.android
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 0,
                  intervalDuration: const Duration(seconds: 10),
                  foregroundNotificationConfig: const ForegroundNotificationConfig(
                    notificationTitle: 'SOS: ubicación compartida',
                    notificationText:
                        'Tu operador recibe tu ubicación mientras tu caso está activo.',
                    notificationChannelName: 'Ubicación del SOS',
                    setOngoing: true,
                    enableWakeLock: true,
                  ),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 10,
                ),
        ).listen(
          (gps) {
            if (!_disposed && ticket == _generation) _latest = gps;
          },
          onError: (Object _) {
            unawaited(_gps?.cancel());
            _gps = null;
          },
        );
  }

  Future<void> _publish() async {
    final gps = _latest, id = caseId, owner = _owner;
    if (_sending ||
        gps == null ||
        id == null ||
        gps.accuracy > 50 ||
        DateTime.now().difference(gps.timestamp).abs() >
            const Duration(seconds: 30) ||
        FirebaseAuth.instance.currentUser?.uid != owner) {
      return;
    }
    _sending = true;
    try {
      await WorkflowClient.request(
        'POST',
        '/my-sos/$id/position',
        body: {
          'latitude': gps.latitude,
          'longitude': gps.longitude,
          'accuracy': gps.accuracy,
          'observed_at': gps.timestamp.toUtc().toIso8601String(),
        },
      );
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _gps?.cancel();
    super.dispose();
  }
}
