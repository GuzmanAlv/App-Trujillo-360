import 'package:flutter/foundation.dart';
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

class SosRouteController extends ChangeNotifier {
  String? caseId, error, calculatedAt;
  bool isReinforcement = false;
  Future<void> recalculate() async {
    if (caseId != null) {
      await calculate(caseId!, reinforcement: isReinforcement);
    }
  }

  List<LatLng> points = [];
  LatLng? origin, destination;
  double seconds = 0, meters = 0;
  bool loading = false, _disposed = false;
  int generation = 0, revision = 0;
  void clear() {
    generation++;
    caseId = null;
    points = [];
    origin = null;
    destination = null;
    error = null;
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> calculate(String id, {bool reinforcement = false}) async {
    if (_disposed) return;
    final ticket = ++generation;
    caseId = id;
    isReinforcement = reinforcement;
    loading = true;
    error = null;
    points = [];
    origin = null;
    destination = null;
    notifyListeners();
    try {
      final gps = await LocationService().current();
      if (_disposed || ticket != generation) return;
      final result = await WorkflowClient.request(
        'POST',
        reinforcement
            ? '/operator/reinforcements/$id/route'
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
      revision++;
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
    generation++;
    super.dispose();
  }
}
