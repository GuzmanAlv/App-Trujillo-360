import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'workflow_client.dart';
import 'operator_duty.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Foreground only. Arrival is decided by the server, independently of routing.
class SosArrivalTracker extends ValueNotifier<String?> {
  SosArrivalTracker() : super(null);
  Timer? _timer;
  bool _enabled = false, _busy = false;
  int _generation = 0;

  void configure(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _generation++;
    _timer?.cancel();
    value = null;
    if (enabled) {
      _timer = Timer.periodic(const Duration(seconds: 12), (_) => check());
      unawaited(check());
    }
  }

  Future<void> check() async {
    if (!_enabled || _busy) return;
    _busy = true;
    final ticket = _generation;
    bool current() => _enabled && ticket == _generation;
    try {
      final rows = await WorkflowClient.list('/operator/sos-map');
      if (!current()) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) OperatorDuty.replace(uid, rows);
      final active = rows
          .where(
            (r) =>
                r['decision'] == 'confirmed' &&
                r['attention'] == 'en_route' &&
                r['can_track'] == true,
          )
          .toList();
      if (active.isEmpty) {
        value = null;
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (!current()) return;
      if (![
            LocationPermission.always,
            LocationPermission.whileInUse,
          ].contains(permission) ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (current()) {
          value = 'Activa el GPS y su permiso para detectar la llegada al SOS.';
        }
        return;
      }
      final gps = await LocationService().current();
      if (!current()) return;
      value = gps.accuracy > 30
          ? 'Esperando mejor precisión GPS para detectar la llegada.'
          : null;
      for (final row in active) {
        if (!current()) return;
        final result = await WorkflowClient.request(
          'POST',
          '/operator/sos-cases/${row['id']}/arrival',
          body: {
            'latitude': gps.latitude,
            'longitude': gps.longitude,
            'accuracy': gps.accuracy,
            'observed_at': gps.timestamp.toUtc().toIso8601String(),
          },
        );
        if (current() && result['reason'] == 'gps_quality') {
          value =
              'Esperando una ubicación GPS reciente y precisa para detectar la llegada.';
        }
        if (current() && uid != null && result['attention'] == 'on_scene') {
          OperatorDuty.upsert(uid, {...row, 'attention': 'on_scene'});
        }
      }
    } catch (_) {
      if (current()) {
        value = 'No se pudo comprobar la llegada al SOS. Se reintentará.';
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _enabled = false;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
