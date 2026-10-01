import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/config.dart';
import '../models/incident.dart';
import '../services/location_service.dart';

const trujillo = LatLng(-8.1116, -79.0288);

class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    this.incidents = const [],
    this.selected,
    this.onPick,
    this.onIncident,
  });
  final List<Incident> incidents;
  final LatLng? selected;
  final ValueChanged<LatLng>? onPick;
  final ValueChanged<Incident>? onIncident;
  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> with WidgetsBindingObserver {
  GoogleMapController? controller;
  StreamSubscription<Position>? subscription;
  final service = LocationService();
  LatLng? location;
  bool following = false, busy = false, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      subscription?.cancel();
      subscription = null;
      if (mounted) setState(() => following = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> follow() async {
    if (busy) return;
    if (following) {
      await subscription?.cancel();
      if (mounted) setState(() => following = false);
      return;
    }
    setState(() => busy = true);
    try {
      final position = await service.current();
      if (!mounted || !foreground) return;
      update(position);
      setState(() => following = true);
      await subscription?.cancel();
      if (!mounted) return;
      subscription = service.watch().listen(
        update,
        onError: (_) {
          subscription?.cancel();
          if (mounted) setState(() => following = false);
          message('Se interrumpió la ubicación. Puedes volver a activarla.');
        },
      );
    } on LocationFailure catch (e) {
      message(e.message);
    } catch (_) {
      message(
        'No se pudo obtener la ubicación. Comprueba el GPS y vuelve a intentar.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void update(Position p) {
    if (!mounted) return;
    final value = LatLng(p.latitude, p.longitude);
    setState(() => location = value);
    controller?.animateCamera(CameraUpdate.newLatLng(value));
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final enabled = AppConfig.mapsEnabled && supported;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: enabled
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.selected ?? trujillo,
                      zoom: 14,
                    ),
                    onMapCreated: (c) => controller = c,
                    onTap: widget.onPick,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: {
                      for (final i in widget.incidents)
                        Marker(
                          markerId: MarkerId(i.id),
                          position: LatLng(i.latitude, i.longitude),
                          infoWindow: InfoWindow(
                            title: '${i.type} · ${i.status.label}',
                            snippet: '${i.place} · ${i.reporterCount} perfiles',
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            i.status == VerificationStatus.verified
                                ? BitmapDescriptor.hueGreen
                                : BitmapDescriptor.hueOrange,
                          ),
                          onTap: () => widget.onIncident?.call(i),
                        ),
                      if (location != null)
                        Marker(
                          markerId: const MarkerId('my_location'),
                          position: location!,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure,
                          ),
                          infoWindow: const InfoWindow(title: 'Mi ubicación'),
                        ),
                      if (widget.selected != null)
                        Marker(
                          markerId: const MarkerId('selected'),
                          position: widget.selected!,
                        ),
                    },
                  )
                : ColoredBox(
                    color: const Color(0xffe3ebe5),
                    child: Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.map_outlined,
                                size: 46,
                                color: Color(0xff087f68),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Google Maps pendiente',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Puedes probar los reportes locales. El mapa real necesita una clave configurada.',
                                textAlign: TextAlign.center,
                              ),
                              if (widget.selected != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    '${widget.selected!.latitude.toStringAsFixed(5)}, ${widget.selected!.longitude.toStringAsFixed(5)}',
                                  ),
                                ),
                              for (final incident in widget.incidents)
                                Card(
                                  child: ListTile(
                                    title: Text(
                                      '${incident.type} · ${incident.place}',
                                    ),
                                    subtitle: Text(
                                      '${incident.status.label} · '
                                      '${incident.reporterCount} perfiles distintos',
                                    ),
                                    onTap: () =>
                                        widget.onIncident?.call(incident),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (enabled)
            Positioned(
              right: 12,
              bottom: 38,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: following
                    ? 'Detener seguimiento'
                    : 'Seguir mi ubicación',
                onPressed: busy ? null : follow,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(following ? Icons.gps_fixed : Icons.my_location),
              ),
            ),
        ],
      ),
    );
  }
}
