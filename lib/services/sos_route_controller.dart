import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_service.dart';
import 'workflow_client.dart';

List<LatLng> decodeRoutePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  int coordinate() {
    var value = 0, shift = 0, part = 0;
    do {
      if (index >= encoded.length || shift > 35) {
        throw const FormatException('Ruta inválida');
      }
      part = encoded.codeUnitAt(index++) - 63;
      if (part < 0 || part > 63) throw const FormatException('Ruta inválida');
      value |= (part & 31) << shift;
      shift += 5;
    } while (part >= 32);
    return value & 1 == 1 ? ~(value >> 1) : value >> 1;
  }

  while (index < encoded.length) {
    lat += coordinate();
    lng += coordinate();
    if (lat.abs() > 9000000 || lng.abs() > 18000000 || points.length > 25000) {
      throw const FormatException('Ruta inválida');
    }
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  if (points.length < 2) throw const FormatException('Ruta incompleta');
  return points;
}

/// Distance to a segment (not just its vertices), in meters, near the route.
double distanceFromRoute(LatLng point, List<LatLng> line) {
  var best = double.infinity;
  final scale = math.cos(point.latitude * math.pi / 180);
  for (var i = 1; i < line.length; i++) {
    final ax = (line[i - 1].longitude - point.longitude) * 111320 * scale;
    final ay = (line[i - 1].latitude - point.latitude) * 111320;
    final bx = (line[i].longitude - point.longitude) * 111320 * scale;
    final by = (line[i].latitude - point.latitude) * 111320;
    final dx = bx - ax, dy = by - ay, length = dx * dx + dy * dy;
    final t = length == 0
        ? 0.0
        : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0);
    best = math.min(
      best,
      math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
    );
  }
  return best;
}

class SosRouteController extends ChangeNotifier with WidgetsBindingObserver {
  bool _observing = false;
  Timer? _tracking;
  bool _foreground = true, _checking = false, _preview = false;
  DateTime? _lastCalculation;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_follow());
  }

  Future<void> _follow() async {
    final id = caseId, ticket = generation;
    if (id == null ||
        loading ||
        _checking ||
        !_foreground ||
        _disposed ||
        _preview ||
        isReinforcement) {
      return;
    }
    _checking = true;
    try {
      final gps = await LocationService().current();
      final target = await WorkflowClient.request(
        'GET',
        '/operator/sos-cases/$id/navigation-target',
      );
      if (_disposed ||
          ticket != generation ||
          id != caseId ||
          gps.accuracy > 30) {
        return;
      }
      final here = LatLng(gps.latitude, gps.longitude);
      final to = LatLng(
        (target['latitude'] as num).toDouble(),
        (target['longitude'] as num).toDouble(),
      );
      double distance(LatLng a, LatLng b) => Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (origin == null ||
          destination == null ||
          distance(to, destination!) >= 20 ||
          distanceFromRoute(here, points) >= 40 ||
          distance(here, origin!) >= 100 ||
          _lastCalculation == null ||
          DateTime.now().difference(_lastCalculation!) >=
              const Duration(minutes: 2)) {
        await calculate(id, automatic: true, gps: gps);
      }
    } catch (e) {
      if (e is WorkflowFailure && [403, 404, 409].contains(e.status)) {
        _tracking?.cancel();
      }
      // Keep the last successful route while connectivity recovers.
    } finally {
      _checking = false;
    }
  }

  String? caseId, error, calculatedAt;
  bool isReinforcement = false;
  Future<void> recalculate() async {
    if (caseId != null) {
      await calculate(
        caseId!,
        reinforcement: isReinforcement,
        preview: _preview,
      );
    }
  }

  List<LatLng> points = [];
  LatLng? origin, destination;
  double seconds = 0, meters = 0;
  bool loading = false, _disposed = false;
  int generation = 0, revision = 0;
  void clear() {
    _tracking?.cancel();
    generation++;
    caseId = null;
    points = [];
    origin = null;
    destination = null;
    error = null;
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> calculate(
    String id, {
    bool reinforcement = false,
    bool preview = false,
    bool automatic = false,
    Position? gps,
  }) async {
    if (_disposed) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final same =
        caseId == id && _preview == preview && isReinforcement == reinforcement;
    final ticket = ++generation;
    caseId = id;
    isReinforcement = reinforcement;
    _preview = preview;
    _tracking?.cancel();
    loading = true;
    error = null;
    if (!same) {
      points = [];
      origin = null;
      destination = null;
    }
    notifyListeners();
    try {
      gps ??= await LocationService().current();
      if (_disposed || ticket != generation) return;
      final result = await WorkflowClient.request(
        'POST',
        reinforcement
            ? '/operator/reinforcements/$id/route'
            : preview
            ? '/operator/sos-cases/$id/preview-route'
            : '/operator/sos-cases/$id/route',
        body: {'latitude': gps.latitude, 'longitude': gps.longitude},
      );
      final line = decodeRoutePolyline(result['encoded_polyline'] as String);
      if (_disposed || ticket != generation) return;
      points = line;
      seconds = (result['duration_seconds'] as num).toDouble();
      meters = (result['distance_meters'] as num).toDouble();
      origin = LatLng(gps.latitude, gps.longitude);
      destination = LatLng(
        (result['destination']['latitude'] as num).toDouble(),
        (result['destination']['longitude'] as num).toDouble(),
      );
      calculatedAt = result['calculated_at'] as String?;
      _lastCalculation = DateTime.now();
      if (!automatic) revision++;
    } catch (e) {
      if (!_disposed && ticket == generation) {
        error = e is StateError
            ? e.message.toString()
            : e is LocationFailure
            ? e.message
            : 'No se pudo calcular una ruta real. Puedes reintentar.';
      }
    } finally {
      if (!_disposed && ticket == generation) {
        loading = false;
        if (!preview && !reinforcement) {
          _tracking = Timer.periodic(
            const Duration(seconds: 20),
            (_) => _follow(),
          );
        }
        notifyListeners();
      }
    }
  }

  LatLngBounds? get bounds {
    if (points.isEmpty) return null;
    final all = [...points, ?origin, ?destination];
    var south = all.first.latitude,
        north = south,
        west = all.first.longitude,
        east = west;
    for (final p in all) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(
        (south - .0005).clamp(-90, 90),
        (west - .0005).clamp(-180, 180),
      ),
      northeast: LatLng(
        (north + .0005).clamp(-90, 90),
        (east + .0005).clamp(-180, 180),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _tracking?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    generation++;
    super.dispose();
  }
}
