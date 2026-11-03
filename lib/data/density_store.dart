import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/workflow_client.dart';

class DensityStore extends ChangeNotifier {
  LatLngBounds? bounds;
  int hourBand = -1, generation = 0;
  bool active = false, loading = false, disposed = false;
  String? error;
  List<Map<String, dynamic>> cells = [];
  Timer? timer;
  void setBounds(LatLngBounds value) {
    bounds = value;
    schedule();
  }

  void configure({required bool enabled, int? band}) {
    active = enabled;
    if (band != null && band != hourBand) {
      hourBand = band;
      cells = [];
      error = null;
    }
    schedule();
  }

  void clear() {
    generation++;
    cells = [];
    error = null;
    loading = false;
    timer?.cancel();
    notifyListeners();
  }

  void schedule() {
    generation++;
    timer?.cancel();
    if (!active || disposed) return;
    timer = Timer(const Duration(milliseconds: 350), refresh);
  }

  Future<void> refresh() async {
    final b = bounds;
    if (!active || disposed || b == null) return;
    final ticket = ++generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await WorkflowClient.request(
        'GET',
        '/incidents/density',
        query: {
          'south': '${b.southwest.latitude}',
          'north': '${b.northeast.latitude}',
          'west': '${b.southwest.longitude}',
          'east': '${b.northeast.longitude}',
          'hour_band': '$hourBand',
        },
      );
      if (!disposed && ticket == generation) {
        cells = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      if (!disposed && ticket == generation) {
        cells = [];
        error = e is StateError
            ? e.message.toString()
            : 'No se pudo consultar el historial.';
      }
    } finally {
      if (!disposed && ticket == generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Set<Circle> get overlays => {
    for (final c in cells)
      Circle(
        circleId: CircleId('history:${c['latitude']}:${c['longitude']}'),
        center: LatLng(
          (c['latitude'] as num).toDouble(),
          (c['longitude'] as num).toDouble(),
        ),
        radius: 80,
        fillColor: ((c['count'] as num) >= 3 ? Colors.red : Colors.amber)
            .withValues(alpha: .28),
        strokeColor: (c['count'] as num) >= 3
            ? Colors.red
            : Colors.amber.shade800,
        strokeWidth: 2,
      ),
  };
  @override
  void dispose() {
    disposed = true;
    generation++;
    timer?.cancel();
    super.dispose();
  }
}
