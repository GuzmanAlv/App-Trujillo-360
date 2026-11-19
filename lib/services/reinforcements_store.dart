import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'report_sender.dart';
import 'workflow_client.dart';

class ReinforcementsStore extends ChangeNotifier {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? banner, focus;
  String? error;
  int focusRevision = 0;
  bool enabled = false, busy = false, _fetching = false, _disposed = false;
  bool loaded = false;
  String? _owner, _requestId;
  int _generation = 0;
  final _seen = <String>{};
  Timer? _poll, _hide;
  DateTime _lastPosition = DateTime(2000);
  List<Map<String, dynamic>> get others =>
      rows.where((r) => r['is_mine'] != true).toList();
  Map<String, dynamic>? get mine {
    final own = rows.where((r) => r['is_mine'] == true);
    return own.isEmpty ? null : own.first;
  }

  void configure(bool active) {
    final uid = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    if (_owner != uid) {
      _owner = uid;
      _generation++;
      rows = [];
      loaded = false;
      banner = null;
      focus = null;
      _seen.clear();
      _requestId = null;
      _lastPosition = DateTime(2000);
      error = null;
      _hide?.cancel();
      notifyListeners();
    }
    if (enabled == active) return;
    enabled = active;
    _generation++;
    _poll?.cancel();
    if (active && uid != null) {
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
      unawaited(refresh());
    }
  }

  Map<String, dynamic> position(Position gps) => {
    'latitude': gps.latitude,
    'longitude': gps.longitude,
    'accuracy': gps.accuracy,
    'observed_at': gps.timestamp.toUtc().toIso8601String(),
  };
  Future<void> refresh() async {
    if (!enabled || _fetching || _owner == null || _disposed) return;
    _fetching = true;
    final ticket = _generation;
    bool current() => !_disposed && enabled && ticket == _generation;
    try {
      final next = await WorkflowClient.list('/operator/reinforcements');
      if (!current()) return;
      rows = next;
      loaded = true;
      error = null;
      final fresh = others.where((r) => !_seen.contains('${r['id']}')).toList();
      for (final r in others) {
        _seen.add('${r['id']}');
      }
      if (fresh.isNotEmpty) {
        banner = fresh.first;
        _hide?.cancel();
        _hide = Timer(const Duration(seconds: 5), () {
          if (!_disposed) {
            banner = null;
            notifyListeners();
          }
        });
      }
      notifyListeners();
      final own = mine;
      if (own != null &&
          DateTime.now().difference(_lastPosition).inSeconds >= 30) {
        final permission = await Geolocator.checkPermission();
        if (!current() ||
            ![
              LocationPermission.always,
              LocationPermission.whileInUse,
            ].contains(permission)) {
          return;
        }
        final gps = await LocationService().current();
        if (!current()) return;
        if (gps.accuracy <= 100) {
          await WorkflowClient.request(
            'PUT',
            '/operator/reinforcements/${own['id']}/position',
            body: position(gps),
          );
          _lastPosition = DateTime.now();
        }
      }
    } catch (_) {
      if (current()) {
        error = 'No se pudieron actualizar los refuerzos.';
        notifyListeners();
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> request() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    notifyListeners();
    final ticket = _generation;
    try {
      final gps = await LocationService().current();
      if (_disposed || ticket != _generation) return;
      if (gps.accuracy > 100) {
        throw StateError(
          'Espera una ubicación GPS más precisa para solicitar refuerzos.',
        );
      }
      _requestId ??= ReportSender.requestId();
      final row = Map<String, dynamic>.from(
        await WorkflowClient.request(
          'POST',
          '/operator/reinforcements',
          body: {'request_id': _requestId, ...position(gps)},
        ),
      );
      if (_disposed || ticket != _generation) return;
      rows = [row, ...rows.where((r) => r['id'] != row['id'])];
      _requestId = null;
      _lastPosition = DateTime.now();
    } catch (e) {
      if (!_disposed && ticket == _generation) {
        error = e is StateError
            ? e.message.toString()
            : 'No se pudo solicitar refuerzos. Reintenta.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> closeMine() async {
    final own = mine;
    if (own == null || busy) return;
    final ticket = _generation;
    busy = true;
    notifyListeners();
    try {
      await WorkflowClient.request(
        'POST',
        '/operator/reinforcements/${own['id']}/close',
      );
      if (!_disposed && ticket == _generation) {
        rows = rows.where((r) => r['id'] != own['id']).toList();
        error = null;
      }
    } catch (_) {
      if (!_disposed) error = 'No se pudo finalizar la solicitud de refuerzos.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void select(Map<String, dynamic> row) {
    focus = row;
    focusRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    _hide?.cancel();
    super.dispose();
  }
}
