import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/my_reports_client.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/incident_store.dart';
import '../models/incident.dart';
import '../services/location_service.dart';
import '../services/nearby_reports_client.dart';
import 'report_style.dart';

class ReportsPanel extends StatefulWidget {
  const ReportsPanel({
    super.key,
    required this.store,
    required this.filter,
    required this.onReport,
    required this.active,
  });
  final IncidentStore store;
  final String filter;
  final ValueChanged<Incident> onReport;
  final bool active;
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel>
    with WidgetsBindingObserver {
  final locationService = LocationService();
  StreamSubscription<Position>? subscription;
  StreamSubscription<User?>? authSubscription;
  List<Incident> history = [];
  bool historyLoading = false;
  String? historyNote;
  int historyGeneration = 0;
  Position? position;
  List<Incident> community = [];
  bool mine = false, locating = false, loading = false;
  bool enabled = false;
  String? note;
  int generation = 0;
  int fetchGeneration = 0;
  DateTime? lastFetch;
  Timer? refreshTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        historyGeneration++;
        fetchGeneration++;
        setState(() {
          history = [];
          community = [];
          historyNote = null;
          historyLoading = false;
          loading = false;
        });
        if (user != null) {
          loadHistory();
        }
        if (widget.active && !mine && position != null) {
          refresh();
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
    if (!widget.active) {
      stop();
    } else if (!oldWidget.active && enabled && !mine) {
      start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      stop();
    } else if (widget.active && enabled && !mine) {
      start();
    }
  }

  void stop() {
    subscription?.cancel();
    subscription = null;
    refreshTimer?.cancel();
    generation++;
    fetchGeneration++;
    locating = false;
    loading = false;
  }

  @override
  void dispose() {
    stop();
    authSubscription?.cancel();
    historyGeneration++;
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> start() async {
    if (locating) return;
    enabled = true;
    final ticket = ++generation;
    setState(() {
      locating = true;
      note = null;
    });
    try {
      final p = await locationService.current();
      if (!mounted || ticket != generation) return;
      update(p);
      await subscription?.cancel();
      if (!mounted || ticket != generation) return;
      subscription = locationService.watch().listen(
        update,
        onError: (_) {
          stop();
          if (mounted) {
            setState(
              () => note = 'Se interrumpió la ubicación. Vuelve a activarla.',
            );
          }
        },
      );
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(
          () => note = e is LocationFailure
              ? e.message
              : 'No se pudo obtener tu ubicación. Vuelve a intentar.',
        );
      }
    } finally {
      if (mounted && ticket == generation) setState(() => locating = false);
    }
  }

  void update(Position p) {
    if (!mounted) return;
    setState(() => position = p);
    refreshTimer?.cancel();
    final elapsed = lastFetch == null
        ? const Duration(seconds: 10)
        : DateTime.now().difference(lastFetch!);
    if (elapsed >= const Duration(seconds: 10)) {
      refresh();
    } else {
      refreshTimer = Timer(const Duration(seconds: 10) - elapsed, refresh);
    }
  }

  Future<void> refresh() async {
    if (position == null) return;
    final ticket = ++fetchGeneration;
    final p = position!;
    lastFetch = DateTime.now();
    setState(() {
      loading = true;
      note = null;
    });
    try {
      final result = await fetchNearbyReports(p.latitude, p.longitude);
      if (mounted && ticket == fetchGeneration) {
        setState(() => community = result);
      }
    } catch (e) {
      if (mounted && ticket == fetchGeneration) {
        setState(
          () => note = e is StateError
              ? e.message.toString()
              : 'No se pudieron actualizar los reportes cercanos.',
        );
      }
    } finally {
      if (mounted && ticket == fetchGeneration) setState(() => loading = false);
    }
  }

  double distance(Incident i) => Geolocator.distanceBetween(
    position!.latitude,
    position!.longitude,
    i.latitude,
    i.longitude,
  );
  String distanceLabel(Incident i) {
    final m = distance(i);
    return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  }

  List<Incident> get items {
    final uid = currentReportOwner;
    final own = mergeMyReports(uid, history, widget.store.items);
    final result = (mine ? own : community)
        .where((i) => widget.filter == 'Todos' || i.type == widget.filter)
        .toList();
    if (!mine && position != null) {
      result.removeWhere((i) => distance(i) > 3000);
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
              stop();
              loadHistory();
            } else if (enabled) {
              start();
            }
          },
        ),
        const SizedBox(height: 12),
        Text(
          mine
              ? 'Tus reportes, estés donde estés.'
              : 'Reportes de la comunidad a menos de 3 km.',
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
                        : 'No hay reportes en esta categoría a menos de 3 km.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final i = reports[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: ReportCategoryIcon(category: i.type),
                        title: Text('${i.type} · ${i.place}'),
                        subtitle: Text(
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
