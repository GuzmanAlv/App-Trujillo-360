import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/incident.dart';
import '../services/location_service.dart';
import '../services/nearby_reports_client.dart';

class NearbyReportsStore extends ChangeNotifier {
  NearbyReportsStore({
    LocationService? locationService,
    Future<List<Incident>> Function(double, double)? fetch,
  }) : service = locationService ?? LocationService(),
       fetchReports = fetch ?? fetchNearbyReports;
  final LocationService service;
  final Future<List<Incident>> Function(double, double) fetchReports;
  Position? position;
  List<Incident> _items = [];
  bool locating = false, loading = false, enabled = false, tracking = false;
  bool active = true, _disposed = false;
  String? note;
  StreamSubscription<Position>? _subscription;
  Timer? _timer;
  DateTime? _lastFetch;
  int _locationGeneration = 0, _fetchGeneration = 0;
  static const searchRadius = 1000.0;

  List<Incident> filtered(String category) {
    final p = position;
    if (p == null) {
      return [];
    }
    return _items
        .where(
          (i) =>
              (category == 'Todos' || i.type == category) &&
              distance(i) <= searchRadius,
        )
        .toList()
      ..sort((a, b) => distance(a).compareTo(distance(b)));
  }

  double distance(Incident i) => position == null
      ? double.infinity
      : Geolocator.distanceBetween(
          position!.latitude,
          position!.longitude,
          i.latitude,
          i.longitude,
        );
  void setActive(bool value) {
    if (active == value) {
      return;
    }
    active = value;
    if (!active) {
      _stop();
    } else if (enabled) {
      start();
    }
  }

  void clearSession() {
    _fetchGeneration++;
    _items = [];
    note = null;
    loading = false;
    notifyListeners();
    if (active && enabled && position != null) {
      refresh();
    }
  }

  void _stop() {
    _locationGeneration++;
    _fetchGeneration++;
    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    locating = false;
    loading = false;
    tracking = false;
  }

  Future<void> start() async {
    if (locating || !active || _disposed) {
      return;
    }
    enabled = true;
    final ticket = ++_locationGeneration;
    locating = true;
    note = null;
    notifyListeners();
    try {
      final p = await service.current();
      if (_disposed || ticket != _locationGeneration || !active) {
        return;
      }
      _update(p);
      await _subscription?.cancel();
      if (_disposed || ticket != _locationGeneration || !active) {
        return;
      }
      tracking = true;
      _subscription = service.watch().listen(
        _update,
        onError: (_) {
          _stop();
          if (!_disposed) {
            note = 'Se interrumpió la ubicación. Vuelve a activarla.';
            notifyListeners();
          }
        },
      );
    } catch (e) {
      if (!_disposed && ticket == _locationGeneration) {
        note = e is LocationFailure
            ? e.message
            : 'No se pudo obtener tu ubicación. Vuelve a intentar.';
      }
    } finally {
      if (!_disposed && ticket == _locationGeneration) {
        locating = false;
        notifyListeners();
      }
    }
  }

  void _update(Position p) {
    if (_disposed || !active) {
      return;
    }
    position = p;
    notifyListeners();
    _timer?.cancel();
    final elapsed = _lastFetch == null
        ? const Duration(seconds: 10)
        : DateTime.now().difference(_lastFetch!);
    if (elapsed >= const Duration(seconds: 10)) {
      refresh();
    } else {
      _timer = Timer(const Duration(seconds: 10) - elapsed, refresh);
    }
  }

  Future<void> refresh() async {
    if (position == null || !active || _disposed) {
      return;
    }
    final ticket = ++_fetchGeneration;
    final p = position!;
    _lastFetch = DateTime.now();
    loading = true;
    note = null;
    notifyListeners();
    try {
      final result = await fetchReports(p.latitude, p.longitude);
      if (!_disposed && ticket == _fetchGeneration) {
        _items = result;
      }
    } catch (e) {
      if (!_disposed && ticket == _fetchGeneration) {
        note = e is StateError
            ? e.message.toString()
            : 'No se pudieron actualizar los reportes cercanos.';
      }
    } finally {
      if (!_disposed && ticket == _fetchGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
