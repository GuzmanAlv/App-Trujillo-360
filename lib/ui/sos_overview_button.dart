import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

LatLngBounds? sosOverviewBounds(Iterable<LatLng> points) {
  if (points.isEmpty) return null;
  var south = points.first.latitude, north = south;
  var west = points.first.longitude, east = west;
  for (final p in points) {
    if (p.latitude < south) south = p.latitude;
    if (p.latitude > north) north = p.latitude;
    if (p.longitude < west) west = p.longitude;
    if (p.longitude > east) east = p.longitude;
  }
  return LatLngBounds(
    southwest: LatLng(
      (south - .002).clamp(-90, 90),
      (west - .002).clamp(-180, 180),
    ),
    northeast: LatLng(
      (north + .002).clamp(-90, 90),
      (east + .002).clamp(-180, 180),
    ),
  );
}

class SosOverviewButton extends StatelessWidget {
  const SosOverviewButton({
    super.key,
    required this.count,
    required this.onPressed,
  });
  final int count;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count SOS activos en Trujillo. Ver todos en el mapa',
    button: true,
    child: Badge(
      label: Text('$count'),
      backgroundColor: const Color(0xffa20d20),
      child: FloatingActionButton.small(
        heroTag: null,
        backgroundColor: Colors.white,
        tooltip: 'Todos los SOS activos · $count',
        onPressed: onPressed,
        child: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xffd4162a),
          size: 24,
        ),
      ),
    ),
  );
}
