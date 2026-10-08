import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/incident.dart';
import '../services/nearby_reports_client.dart';
import 'report_style.dart';
import '../services/community_photos_client.dart';
import 'community_photo_view.dart';

class CommunityIncidentPage extends StatefulWidget {
  const CommunityIncidentPage({
    super.key,
    required this.incident,
    this.fetch,
    this.fetchPhotos,
  });
  final Incident incident;
  final Future<List<Incident>> Function(String)? fetch;
  final Future<List<CommunityPhoto>> Function(String)? fetchPhotos;
  @override
  State<CommunityIncidentPage> createState() => _CommunityIncidentPageState();
}

class _CommunityIncidentPageState extends State<CommunityIncidentPage> {
  List<Incident>? reports;
  List<CommunityPhoto> photos = [];
  String? photosError;
  String? error;
  bool loading = true;
  int generation = 0;
  StreamSubscription<User?>? session;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      final owner = currentReportOwner;
      session = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user?.uid != owner && mounted) {
          generation++;
          setState(() {
            reports = null;
            photos = [];
            loading = false;
            error =
                'La sesión cambió. Regresa al mapa y vuelve a abrir el incidente.';
          });
        }
      });
    }
    load();
  }

  Future<void> load() async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      photos = [];
      photosError = null;
    });
    try {
      final result = await (widget.fetch ?? fetchIncidentReports)(
        widget.incident.id,
      );
      if (mounted && ticket == generation) {
        setState(() {
          reports = result;
          loading = false;
        });
        loadPhotos(ticket);
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          reports = null;
          loading = false;
          error = 'No se pudieron cargar los aportes. Vuelve a intentar.';
        });
      }
    }
  }

  Future<void> loadPhotos(int ticket) async {
    try {
      final result = await (widget.fetchPhotos ?? fetchCommunityPhotos)(
        widget.incident.id,
      );
      if (mounted && ticket == generation) setState(() => photos = result);
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => photosError = 'No se pudieron cargar las fotos.');
      }
    }
  }

  @override
  void dispose() {
    generation++;
    session?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.incident.type)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Incidente corroborado por la comunidad',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Mismo tipo, hasta 100 m y dentro de 15 minutos desde el primer reporte. Cada cuenta aporta una vez.',
        ),
        const SizedBox(height: 12),
        const Text(
          'La corroboración comunitaria no equivale a una verificación por un operador.',
        ),
        const SizedBox(height: 20),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) ...[
          Text(error!),
          TextButton(onPressed: load, child: const Text('Volver a intentar')),
        ],
        if (reports != null) ...[
          Text(
            '${reports!.length} reportes de cuentas diferentes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < reports!.length; index++)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: Text(
                      'Reporte ${index + 1} · ${reports![index].type}',
                    ),
                    subtitle: Text(
                      'Reportado ${reportTime(reports![index].createdAt)}\n${reports![index].latitude.toStringAsFixed(5)}, ${reports![index].longitude.toStringAsFixed(5)}',
                    ),
                  ),
                  if (photos.any((p) => p.reportId == reports![index].id))
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final photo in photos.where(
                              (p) => p.reportId == reports![index].id,
                            ))
                              CommunityPhotoView(
                                key: ValueKey(photo.id),
                                incidentId: widget.incident.id,
                                photoId: photo.id,
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (photosError != null) ...[
            Text(photosError!),
            TextButton(
              onPressed: () => loadPhotos(generation),
              child: const Text('Reintentar fotos'),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Las fotos se comparten cuando el incidente está corroborado. Los nombres y las descripciones privadas permanecen en Mis reportes.',
          ),
          TextButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar aportes'),
          ),
        ],
      ],
    ),
  );
}
