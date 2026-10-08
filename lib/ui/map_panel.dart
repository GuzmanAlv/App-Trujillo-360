import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/config.dart';
import '../models/incident.dart';
import '../services/location_service.dart';
import 'report_style.dart';
import 'report_marker.dart';

const trujillo = LatLng(-8.1116, -79.0288);

class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    this.incidents = const [],
    this.selected,
    this.onPick,
    this.onIncident,
    this.currentLocation,
    this.onLocate,
    this.onViewportChanged,
    this.locating = false,
    this.locationRadius = 0,
    this.active = true,
  });
  final List<Incident> incidents;
  final LatLng? currentLocation;
  final VoidCallback? onLocate;
  final ValueChanged<LatLngBounds>? onViewportChanged;

  final bool locating, active;
  final double locationRadius;
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
  final Map<String, BitmapDescriptor> reportIcons = {};
  int iconGeneration = 0;
  BitmapDescriptor? locationIcon;
  BitmapDescriptor? explorationIcon;
  Future<void> prepareLocationIcon() async {
    final bytes = await renderLocationDot();
    final explorationBytes = await renderLocationDot(
      color: const Color(0xffe67e22),
    );
    if (!mounted) return;
    setState(() {
      locationIcon = BitmapDescriptor.bytes(
        bytes,
        imagePixelRatio: 2,
        width: 32,
        height: 32,
      );
      explorationIcon = BitmapDescriptor.bytes(
        explorationBytes,
        imagePixelRatio: 2,
        width: 32,
        height: 32,
      );
    });
  }

  String iconKey(Incident incident) =>
      '${incident.type}|${reportTime(incident.createdAt)}';

  Future<void> prepareReportIcons() async {
    final generation = ++iconGeneration;
    final incidents = List<Incident>.of(widget.incidents);
    final next = <String, BitmapDescriptor>{};
    for (final incident in incidents) {
      final key = iconKey(incident);
      if (next.containsKey(key)) continue;
      try {
        next[key] =
            reportIcons[key] ??
            BitmapDescriptor.bytes(
              await renderReportMarker(
                incident.type,
                reportTime(incident.createdAt),
              ),
              imagePixelRatio: 2,
              width: 174,
              height: 82,
            );
      } catch (_) {
        // Keep a category-colored marker if image rendering is unavailable.
      }
      if (!mounted || generation != iconGeneration) return;
    }
    if (!mounted || generation != iconGeneration) return;
    setState(() {
      reportIcons.addAll(next);
      while (reportIcons.length > 512) {
        final unused = reportIcons.keys.where((key) => !next.containsKey(key));
        if (unused.isEmpty) break;
        reportIcons.remove(unused.first);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onLocate != null && widget.active) {
      centerIfRequested();
    }
    if (!oldWidget.active && widget.active) {
      reportViewport();
    }
    if (!listEquals(oldWidget.incidents, widget.incidents)) {
      prepareReportIcons();
    }
  }

  bool centerRequested = true;
  int viewportGeneration = 0;
  Future<void> reportViewport() async {
    final c = controller;
    if (c == null || !widget.active || widget.onViewportChanged == null) return;
    final ticket = ++viewportGeneration;
    try {
      final bounds = await c.getVisibleRegion();
      if (mounted && widget.active && ticket == viewportGeneration) {
        widget.onViewportChanged!(bounds);
      }
    } catch (_) {
      /* A disposed map has no viewport to report. */
    }
  }

  void centerIfRequested() {
    final value = displayedLocation;
    if (!centerRequested || controller == null || value == null) return;
    centerRequested = false;
    controller!.animateCamera(CameraUpdate.newLatLng(value));
  }

  void locate() {
    setState(() => exploredLocation = null);
    centerRequested = true;
    centerIfRequested();
    widget.onLocate!();
  }

  LatLng? exploredLocation;

  void selectMapLocation(LatLng point) {
    if (widget.onPick != null) {
      widget.onPick!(point);
    } else if (widget.locationRadius > 0) {
      setState(() {
        exploredLocation = point;
        centerRequested = false;
      });
    }
  }

  LatLng? location;
  LatLng? get displayedLocation => widget.currentLocation ?? location;
  bool following = false, busy = false, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prepareReportIcons();
    prepareLocationIcon();
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
    viewportGeneration++;
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
                    // The form scrolls vertically. Gestures starting inside its
                    // location picker belong to the map, including pan and pinch.
                    gestureRecognizers: widget.onPick != null
                        ? {
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          }
                        : const <Factory<OneSequenceGestureRecognizer>>{},
                    initialCameraPosition: CameraPosition(
                      target: widget.selected ?? displayedLocation ?? trujillo,
                      zoom: displayedLocation == null ? 14 : 13,
                    ),
                    onMapCreated: (c) {
                      controller = c;
                      if (widget.active) {
                        centerIfRequested();
                        reportViewport();
                      }
                    },
                    onCameraIdle: reportViewport,
                    circles: locationHighlight(
                      exploredLocation ?? displayedLocation,
                      widget.locationRadius,
                    ),
                    onTap: selectMapLocation,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: {
                      for (final i in widget.incidents)
                        Marker(
                          markerId: MarkerId(i.id),
                          position: LatLng(i.latitude, i.longitude),
                          anchor: reportIcons.containsKey(iconKey(i))
                              ? const Offset(0.5, 78 / 82)
                              : const Offset(0.5, 1),
                          icon:
                              reportIcons[iconKey(i)] ??
                              BitmapDescriptor.defaultMarkerWithHue(
                                switch (i.type) {
                                  'Robo' => BitmapDescriptor.hueOrange,
                                  'Auxilio' => BitmapDescriptor.hueAzure,
                                  'Agresión' => BitmapDescriptor.hueRose,
                                  'Riesgo' => BitmapDescriptor.hueViolet,
                                  _ => BitmapDescriptor.hueGreen,
                                },
                              ),
                          infoWindow: InfoWindow(
                            title:
                                '${i.type} · Reportado ${reportTime(i.createdAt)}',
                            snippet: i.place,
                          ),
                          onTap: () => widget.onIncident?.call(i),
                        ),
                      if (displayedLocation != null && locationIcon != null)
                        Marker(
                          markerId: const MarkerId('my_location'),
                          position: displayedLocation!,
                          icon: locationIcon!,
                          anchor: const Offset(0.5, 0.5),
                          zIndexInt: 2,
                          infoWindow: const InfoWindow(title: 'Mi ubicación'),
                        ),
                      if (exploredLocation != null && explorationIcon != null)
                        Marker(
                          markerId: const MarkerId('exploration_center'),
                          position: exploredLocation!,
                          icon: explorationIcon!,
                          anchor: const Offset(0.5, 0.5),
                          zIndexInt: 3,
                          infoWindow: const InfoWindow(
                            title: 'Zona seleccionada',
                          ),
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
                          ],
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
                tooltip: widget.onLocate != null
                    ? 'Volver a mi ubicación'
                    : following
                    ? 'Detener seguimiento'
                    : 'Seguir mi ubicación',
                onPressed: busy || widget.locating
                    ? null
                    : widget.onLocate == null
                    ? follow
                    : locate,
                child: busy || widget.locating
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

Set<Circle> locationHighlight(LatLng? center, double radius) {
  if (center == null || radius <= 0) {
    return {};
  }
  return {
    Circle(
      circleId: const CircleId('near_me'),
      center: center,
      radius: radius,
      fillColor: const Color(0xff087f68).withValues(alpha: 0.10),
      strokeColor: const Color(0xff087f68).withValues(alpha: 0.65),
      strokeWidth: 2,
      zIndex: 0,
    ),
  };
}
