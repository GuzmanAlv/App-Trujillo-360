import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/incident.dart';
import '../services/nearby_reports_client.dart';

Future<List<Incident>> fetchMapIncidents(LatLngBounds bounds) =>
    fetchCommunityReports('/incidents/map', {
      'south': '${bounds.southwest.latitude}',
      'north': '${bounds.northeast.latitude}',
      'west': '${bounds.southwest.longitude}',
      'east': '${bounds.northeast.longitude}',
    });

class MapIncidentsStore extends ChangeNotifier {
  MapIncidentsStore({
    Future<List<Incident>> Function(LatLngBounds)? fetch,
    this.debounce = const Duration(milliseconds: 120),
  }) : fetchReports = fetch ?? fetchMapIncidents;
  final Future<List<Incident>> Function(LatLngBounds) fetchReports;
  final Duration debounce;
  LatLngBounds? bounds;
  List<Incident> items = [];
  bool loading = false, active = true, disposed = false;
  String? note;
  Timer? timer;
  int generation = 0;
  final cache = <_MapArea>[];
  static const cacheLifetime = Duration(seconds: 20);
  bool contains(LatLngBounds area, LatLng point) =>
      point.latitude >= area.southwest.latitude &&
      point.latitude <= area.northeast.latitude &&
      (area.southwest.longitude <= area.northeast.longitude
          ? point.longitude >= area.southwest.longitude &&
                point.longitude <= area.northeast.longitude
          : point.longitude >= area.southwest.longitude ||
                point.longitude <= area.northeast.longitude);

  List<Incident> filtered(String category) => items
      .where(
        (i) =>
            (i.remoteStatus == 'corroborated' ||
                i.remoteStatus == 'verified') &&
            i.corroborationCount >= 3 &&
            !i.needsReview &&
            (category == 'Todos' || i.type == category),
      )
      .toList();
  void setBounds(LatLngBounds value) {
    if (disposed) return;
    bounds = value;
    generation++;
    timer?.cancel();
    if (!active) return;
    cache.removeWhere(
      (entry) => DateTime.now().difference(entry.created) >= cacheLifetime,
    );
    final matches = cache.where(
      (entry) =>
          entry.bounds == value ||
          (entry.items.length < 500 &&
              entry.bounds.southwest.longitude <=
                  entry.bounds.northeast.longitude &&
              value.southwest.longitude <= value.northeast.longitude &&
              contains(entry.bounds, value.southwest) &&
              contains(entry.bounds, value.northeast)),
    );
    if (matches.isNotEmpty) {
      items = matches.last.items
          .where((i) => contains(value, LatLng(i.latitude, i.longitude)))
          .toList();
      loading = false;
      note = items.length >= 500
          ? 'Acerca el mapa para ver más incidentes de esta zona.'
          : null;
      notifyListeners();
      return;
    }
    // Keep overlapping markers visible while the next viewport is fetched.
    items = items
        .where((i) => contains(value, LatLng(i.latitude, i.longitude)))
        .toList();
    loading = true;
    note = null;
    notifyListeners();
    timer = Timer(debounce, refresh);
  }

  void setActive(bool value) {
    if (active == value || disposed) return;
    active = value;
    if (!active) {
      generation++;
      timer?.cancel();
      loading = false;
    } else {
      refresh();
    }
  }

  void clearSession() {
    generation++;
    cache.clear();
    timer?.cancel();
    items = [];
    loading = false;
    note = null;
    notifyListeners();
    if (active) refresh();
  }

  Future<void> refresh() async {
    final viewport = bounds;
    if (disposed || !active || viewport == null) return;
    final ticket = ++generation;
    loading = true;
    note = null;
    notifyListeners();
    try {
      final result = await fetchReports(viewport);
      if (!disposed && ticket == generation) {
        items = result;
        cache.removeWhere((entry) => entry.bounds == viewport);
        cache.add(
          _MapArea(viewport, List<Incident>.of(result), DateTime.now()),
        );
        if (cache.length > 8) cache.removeAt(0);
        if (result.length >= 500) {
          note = 'Acerca el mapa para ver más incidentes de esta zona.';
        }
      }
    } catch (e) {
      if (!disposed && ticket == generation) {
        note = e is StateError
            ? e.message.toString()
            : 'No se pudieron consultar los incidentes del mapa.';
      }
    } finally {
      if (!disposed && ticket == generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    timer?.cancel();
    super.dispose();
  }
}

class _MapArea {
  _MapArea(this.bounds, this.items, this.created);
  final LatLngBounds bounds;
  final List<Incident> items;
  final DateTime created;
}
