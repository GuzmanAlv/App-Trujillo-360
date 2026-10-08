import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/my_reports_client.dart';
import 'package:flutter/material.dart';
import '../data/nearby_reports_store.dart';
import 'package:geolocator/geolocator.dart';
import '../data/incident_store.dart';
import '../models/incident.dart';
import '../services/nearby_reports_client.dart';
import 'report_style.dart';

class ReportsPanel extends StatefulWidget {
  const ReportsPanel({
    super.key,
    required this.store,
    required this.filter,
    required this.onReport,
    required this.active,
    required this.nearby,
    required this.onNearbySelected,
    this.onSessionChanged,
  });
  final IncidentStore store;
  final String filter;
  final ValueChanged<Incident> onReport;
  final bool active;
  final NearbyReportsStore nearby;
  final ValueChanged<bool> onNearbySelected;
  final VoidCallback? onSessionChanged;
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  StreamSubscription<User?>? authSubscription;
  List<Incident> history = [];
  bool historyLoading = false;
  String? historyNote;
  int historyGeneration = 0;
  bool mine = false;
  bool corroboratedOnly = false;
  bool get locating => widget.nearby.locating;
  bool get loading => widget.nearby.loading;
  String? get note => widget.nearby.note;
  Position? get position => widget.nearby.position;
  Future<void> start() => widget.nearby.start();
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        historyGeneration++;
        widget.nearby.clearSession();
        widget.onSessionChanged?.call();
        setState(() {
          history = [];
          historyNote = null;
          historyLoading = false;
        });
        if (user != null) {
          loadHistory();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReportsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      loadHistory();
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    historyGeneration++;
    super.dispose();
  }

  Future<void> loadHistory() async {
    final owner = currentReportOwner;
    final ticket = ++historyGeneration;
    if (owner == null) {
      setState(() {
        history = [];
        historyLoading = false;
        historyNote = null;
      });
      return;
    }
    setState(() {
      historyLoading = true;
      historyNote = null;
    });
    try {
      final result = await fetchMyReports();
      if (mounted &&
          ticket == historyGeneration &&
          owner == currentReportOwner) {
        setState(() => history = result);
      }
    } catch (e) {
      if (mounted && ticket == historyGeneration) {
        setState(
          () => historyNote = e is StateError
              ? e.message.toString()
              : 'No se pudo cargar tu historial. Mostramos las copias disponibles.',
        );
      }
    } finally {
      if (mounted && ticket == historyGeneration) {
        setState(() => historyLoading = false);
      }
    }
  }

  double distance(Incident i) => widget.nearby.distance(i);
  String distanceLabel(Incident i) {
    final m = distance(i);
    return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  }

  List<Incident> get items {
    final uid = currentReportOwner;
    final own = mergeMyReports(uid, history, widget.store.items);
    final result = (mine ? own : widget.nearby.filtered(widget.filter))
        .where((i) => widget.filter == 'Todos' || i.type == widget.filter)
        .where(
          (i) =>
              mine ||
              !corroboratedOnly ||
              ((i.remoteStatus == 'corroborated' ||
                      i.remoteStatus == 'verified') &&
                  i.corroborationCount >= 3 &&
                  !i.needsReview),
        )
        .toList();
    if (!mine && position != null) {
      result.removeWhere((i) => distance(i) > NearbyReportsStore.searchRadius);
      result.sort((a, b) => distance(a).compareTo(distance(b)));
    } else {
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final reports = items;
    return Column(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Cerca de mí'),
              icon: Icon(Icons.near_me_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Mis reportes'),
              icon: Icon(Icons.person_outline),
            ),
          ],
          selected: {mine},
          onSelectionChanged: (value) {
            setState(() => mine = value.single);
            if (mine) {
              loadHistory();
            }
            widget.onNearbySelected(!mine);
          },
        ),
        const SizedBox(height: 12),
        if (!mine) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Todos')),
              ButtonSegment(
                value: true,
                label: Text('Corroborados'),
                icon: Icon(Icons.verified_outlined),
              ),
            ],
            selected: {corroboratedOnly},
            onSelectionChanged: (value) =>
                setState(() => corroboratedOnly = value.single),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          mine
              ? 'Tus reportes, estés donde estés.'
              : 'Reportes de la comunidad a menos de 1 km.',
        ),
        if (mine) ...[
          TextButton.icon(
            onPressed: historyLoading ? null : loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar mis reportes'),
          ),
          if (historyLoading) const LinearProgressIndicator(),
          if (historyNote != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(historyNote!, textAlign: TextAlign.center),
            ),
        ],
        if (!mine) ...[
          TextButton.icon(
            onPressed: locating ? null : start,
            icon: const Icon(Icons.my_location),
            label: Text(
              locating
                  ? 'Buscando ubicación…'
                  : position == null
                  ? 'Activar ubicación'
                  : 'Actualizar ubicación',
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (note != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(note!, textAlign: TextAlign.center),
            ),
        ],
        Expanded(
          child: reports.isEmpty
              ? Center(
                  child: Text(
                    mine
                        ? currentReportOwner == null
                              ? 'Inicia sesión para ver tus reportes.'
                              : historyLoading
                              ? 'Cargando tus reportes...'
                              : historyNote != null
                              ? 'Tu historial no está disponible. Vuelve a intentar.'
                              : 'Todavía no tienes reportes en esta categoría.'
                        : position == null
                        ? 'Activa tu ubicación para ver reportes cercanos.'
                        : loading
                        ? 'Consultando reportes cercanos…'
                        : note != null
                        ? 'La consulta de reportes cercanos no está disponible.'
                        : corroboratedOnly
                        ? 'No hay incidentes corroborados en esta categoría a menos de 1 km.'
                        : 'No hay reportes en esta categoría a menos de 1 km.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final i = reports[index];
                    final communityConfirmed =
                        !mine &&
                        i.remoteStatus == 'corroborated' &&
                        i.corroborationCount >= 3 &&
                        !i.needsReview;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: ReportCategoryIcon(category: i.type),
                        title: Text('${i.type} · ${i.place}'),
                        subtitle: communityConfirmed
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${distanceLabel(i)} · Reportado ${reportTime(i.createdAt)}',
                                  ),
                                  const Text(
                                    'Corroborado por la comunidad',
                                    style: TextStyle(
                                      color: Color(0xff087f68),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                '${mine ? '' : '${distanceLabel(i)} · '}Reportado ${reportTime(i.createdAt)} · ${i.deliveryLabel}',
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (mine) {
                            widget.onReport(i);
                          } else {
                            showModalBottomSheet<void>(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        i.type,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${distanceLabel(i)} de tu ubicación · ${i.deliveryLabel}',
                                      ),
                                      Text(
                                        'Reportado ${reportTime(i.createdAt)}',
                                      ),
                                      Text(
                                        '${i.latitude.toStringAsFixed(6)}, ${i.longitude.toStringAsFixed(6)}',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
