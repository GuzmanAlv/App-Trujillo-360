import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'workflow_client.dart';
import 'operator_duty.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Foreground UI checks plus an Android location foreground service for arrival.
class SosArrivalTracker extends ValueNotifier<String?>
    with WidgetsBindingObserver {
  SosArrivalTracker() : super(null) {
    WidgetsBinding.instance.addObserver(this);
    OperatorDuty.cases.addListener(dutyChanged);
  }
  void dutyChanged() {
    if (!_enabled) return;
    final enRoute = OperatorDuty.cases.value.any(
      (row) => row['attention'] == 'en_route',
    );
    if (!enRoute || _foreground) unawaited(nativeTracking(enRoute));
  }

  Timer? _timer;
  bool _enabled = false, _busy = false;
  bool _foreground = true;
  bool _nativeTracking = false;
  Future<void> nativeTracking(bool enabled) async {
    if (_nativeTracking == enabled) return;
    try {
      final accepted = await const MethodChannel(
        'trujillo360/proximity',
      ).invokeMethod<bool>('sosArrivalTracking', {'enabled': enabled});
      _nativeTracking = enabled && accepted == true;
      if (enabled && !_nativeTracking) {
        value =
            'Abre la app y permite ubicación precisa para activar el seguimiento.';
      }
    } catch (_) {
      _nativeTracking = false;
      if (enabled && defaultTargetPlatform == TargetPlatform.android) {
        value = 'No se pudo activar el seguimiento en segundo plano.';
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _nativeTracking = false;
    if (_foreground) dutyChanged();
    if (_foreground && _enabled) unawaited(check());
  }

  int _generation = 0;

  void configure(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _generation++;
    _timer?.cancel();
    value = null;
    if (!enabled) unawaited(nativeTracking(false));
    if (enabled) {
      _timer = Timer.periodic(const Duration(seconds: 12), (_) => check());
      unawaited(check());
    }
  }

  Future<void> check() async {
    if (!_enabled || !_foreground || _busy) return;
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
        await nativeTracking(false);
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
      await nativeTracking(true);
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
    unawaited(nativeTracking(false));
    WidgetsBinding.instance.removeObserver(this);
    OperatorDuty.cases.removeListener(dutyChanged);
    super.dispose();
  }
}
