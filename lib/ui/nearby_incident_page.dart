import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/config.dart';
import '../models/incident.dart';
import 'report_style.dart';

class NearbyIncidentPage extends StatelessWidget {
  const NearbyIncidentPage({super.key, required this.incident, this.distance});
  final Incident incident;
  final double? distance;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(incident.latitude, incident.longitude);
    final confirmed =
        !incident.needsReview &&
        incident.corroborationCount >= 3 &&
        ['corroborated', 'verified'].contains(incident.remoteStatus);
    final available =
        AppConfig.mapsEnabled &&
        (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    Widget map(bool interactive) => GoogleMap(
      initialCameraPosition: CameraPosition(target: point, zoom: 16),
      markers: {
        Marker(markerId: const MarkerId('alert_location'), position: point),
      },
      zoomControlsEnabled: interactive,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      rotateGesturesEnabled: interactive,
      tiltGesturesEnabled: interactive,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Incidencia cerca de ti')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(incident.type, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            confirmed
                ? 'Corroborado por la comunidad'
                : 'Pendiente de corroboración',
          ),
          Text('Reportado ${reportTime(incident.createdAt)}'),
          if (distance != null && distance!.isFinite)
            Text('${distance!.round()} m de tu ubicación actual'),
          const SizedBox(height: 16),
          const Text(
            'Aviso ciudadano. No confirma que el incidente siga en curso ni que una autoridad esté atendiendo el caso.',
          ),
          const SizedBox(height: 16),
          if (available) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 240, child: map(false)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.fullscreen),
              label: const Text('Ampliar ubicación'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(incident.type)),
                    body: map(true),
                  ),
                ),
              ),
            ),
          ] else
            const Text(
              'Mapa no disponible. Configura Google Maps para ver la ubicación.',
            ),
          Text(
            '${incident.latitude.toStringAsFixed(6)}, ${incident.longitude.toStringAsFixed(6)}',
          ),
        ],
      ),
    );
  }
}
