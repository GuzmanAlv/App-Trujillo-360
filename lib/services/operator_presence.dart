import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'workflow_client.dart';

/// A signed-in operator shares a recent position for the 15 km alert zone.
class OperatorPresence extends ValueNotifier<Position?> {
  OperatorPresence() : super(null);
  String? _owner;
  StreamSubscription<Position>? _gps;
  Timer? _timer;
  int _generation = 0;
  bool _starting = false, _sending = false, _disposed = false, _asked = false;
  DateTime? _lastSent;
  void configure(String? owner) {
    if (owner == _owner) return;
    _owner = owner;
    _generation++;
    _gps?.cancel();
    _gps = null;
    _timer?.cancel();
    _asked = false;
    _lastSent = null;
    value = null;
    if (owner == null) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    unawaited(tick());
  }

  Future<void> tick() async {
    if (_disposed || _owner == null || _starting) return;
    final ticket = _generation;
    _starting = true;
    try {
      if (_gps == null) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied && !_asked) {
          _asked = true;
          permission = await Geolocator.requestPermission();
        }
        if (_disposed ||
            ticket != _generation ||
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
                      intervalDuration: const Duration(seconds: 15),
                      foregroundNotificationConfig:
                          const ForegroundNotificationConfig(
                            notificationTitle: 'Operador: avisos SOS cercanos',
                            notificationText:
                                'Tu ubicación define el radio de avisos de 15 km.',
                            notificationChannelName: 'Zona SOS del operador',
                            setOngoing: true,
                            enableWakeLock: true,
                          ),
                    )
                  : const LocationSettings(
                      accuracy: LocationAccuracy.high,
                      distanceFilter: 0,
                    ),
            ).listen(
              (gps) {
                if (_disposed || ticket != _generation) return;
                value = gps;
                unawaited(publish());
              },
              onError: (Object _) {
                if (_disposed || ticket != _generation) return;
                unawaited(_gps?.cancel());
                _gps = null;
                value = null;
              },
            );
      }
      await publish();
    } catch (_) {
      // Unknown location disables alarms, while the global SOS map stays usable.
    } finally {
      _starting = false;
    }
  }

  Future<void> publish() async {
    final gps = value;
    if (_disposed ||
        _sending ||
        gps == null ||
        gps.accuracy > 100 ||
        _owner == null ||
        FirebaseAuth.instance.currentUser?.uid != _owner ||
        DateTime.now().difference(gps.timestamp).abs() >
            const Duration(seconds: 30) ||
        (_lastSent != null &&
            DateTime.now().difference(_lastSent!) <
                const Duration(seconds: 25))) {
      return;
    }
    final ticket = _generation;
    _sending = true;
    try {
      await WorkflowClient.request(
        'POST',
        '/operator/position',
        body: {
          'latitude': gps.latitude,
          'longitude': gps.longitude,
          'accuracy': gps.accuracy,
          'observed_at': gps.timestamp.toUtc().toIso8601String(),
        },
      );
      if (ticket == _generation) _lastSent = DateTime.now();
    } catch (_) {
      // Retry at the next GPS sample/tick; never report a position as uploaded.
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
