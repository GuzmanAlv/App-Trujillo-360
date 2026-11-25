import 'services/operator_presence.dart';
import 'services/operator_route_recovery.dart';
import 'services/citizen_sos_tracker.dart';
import 'services/pending_sos.dart';
import 'ui/map_filters_drawer.dart';
import 'services/sos_navigation.dart';
import 'services/operator_duty.dart';
import 'services/reinforcements_store.dart';
import 'ui/map_bottom_controls.dart';
import 'services/active_call.dart';
import 'ui/reinforcement_controls.dart';
import 'ui/report_form.dart' show categories;
import 'services/citizen_arrival_alerts.dart';
import 'ui/citizen_sos_page.dart';
import 'services/sos_arrival_tracker.dart';
import 'services/sos_route_controller.dart';
import 'ui/citizen_sos_map_layer.dart';
import 'ui/operator_sos_map_layer.dart';
import 'ui/incoming_call_overlay.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data/density_store.dart';
import 'services/workflow_client.dart';
import 'services/location_service.dart';
import 'services/report_sender.dart';
import 'ui/workflow_panel.dart';
import 'data/incident_store.dart';
import 'data/nearby_reports_store.dart';
import 'data/map_incidents_store.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models/incident.dart';
import 'services/push_service.dart';
import 'ui/notification_settings.dart';
import 'ui/sos_shortcut_settings.dart';
import 'ui/audio_call_page.dart';
import 'ui/push_destination.dart';
import 'ui/report_details_page.dart';
import 'ui/community_incident_page.dart';
import 'ui/reports_panel.dart';
import 'ui/map_panel.dart';
import 'ui/report_style.dart';
import 'ui/account_panel.dart';
import 'services/nearby_reports_client.dart';

class TrujilloApp extends StatelessWidget {
  const TrujilloApp({super.key, required this.store});
  final IncidentStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Trujillo 360',
    navigatorKey: appNavigatorKey,
    debugShowCheckedModeBanner: false,
    // Reserva el espacio de navegación de Android para todas las rutas.
    // SafeArea elimina ese margen del MediaQuery de los hijos para no duplicarlo.
    builder: (context, child) => SafeArea(
      top: false,
      child: IncomingCallOverlay(child: child ?? const SizedBox.shrink()),
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f68)),
      scaffoldBackgroundColor: const Color(0xfff4f6f2),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff4f6f2)),
    ),
    home: HomePage(store: store),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.nearby,
    this.mapIncidents,
  });
  final IncidentStore store;
  final NearbyReportsStore? nearby;
  final MapIncidentsStore? mapIncidents;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final density = DensityStore();
  final sosRoute = SosRouteController();
  final sosPreview = SosRouteController();

  Future<void> previewSos(String? id) async {
    if (id == null) {
      if (sosPreview.caseId != null) sosPreview.clear();
      return;
    }
    if (sosPreview.caseId == id &&
        (sosPreview.loading || sosPreview.points.isNotEmpty)) {
      return;
    }
    final route = sosPreview.calculate(id, preview: true);
    final generation = sosPreview.generation;
    await route;
    if (!mounted ||
        generation != sosPreview.generation ||
        sosPreview.error == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(sosPreview.error!)));
  }

  final operatorPresence = OperatorPresence();
  final routeRecovery = OperatorRouteRecovery();
  LatLngBounds? sosOverview;
  int sosOverviewRevision = 0;
  final citizenSos = CitizenSosTracker();
  final sosArrival = SosArrivalTracker();
  final reinforcements = ReinforcementsStore();
  void reinforcementsChanged() {
    if (sosRoute.isReinforcement &&
        reinforcements.loaded &&
        !reinforcements.rows.any((r) => r['id'] == sosRoute.caseId)) {
      sosRoute.clear();
    }
  }

  void dutyPriorityChanged() {
    final uid = currentReportOwner;
    if (sosRoute.caseId != null &&
        !sosRoute.isReinforcement &&
        !OperatorDuty.cases.value.any((r) => r['id'] == sosRoute.caseId)) {
      sosRoute.clear();
    }
    if (mounted && uid != null && OperatorDuty.owner == uid) {
      final id = routeRecovery.recover(
        uid,
        OperatorDuty.cases.value,
        sosRoute.caseId,
      );
      if (id != null) {
        routeOwner = uid;
        sosPreview.clear();
        setState(() {
          historical = false;
          sosOverview = null;
        });
        unawaited(sosRoute.calculate(id));
      }
    }

    if (sosRoute.isReinforcement &&
        OperatorDuty.cases.value.any((r) => r['attention'] == 'en_route')) {
      sosRoute.clear();
    }
  }

  void caseChanged() {
    final change = SosNavigation.caseChanges.value;
    if (!mounted || change == null) return;
    if (change.closed &&
        !sosRoute.isReinforcement &&
        sosRoute.caseId == change.id) {
      sosRoute.clear();
    }
    if (tab == 0) unawaited(mapIncidents.refresh());
  }

  void selectReinforcement(Map<String, dynamic> row, bool drawRoute) {
    returnToMap();
    setState(() => historical = false);
    reinforcements.select(row);
    if (!drawRoute) return;
    if (OperatorDuty.cases.value.any((r) => r['attention'] == 'en_route')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero llega al SOS ciudadano asignado. Su ruta tiene prioridad.',
          ),
        ),
      );
      return;
    }
    routeOwner = currentReportOwner;
    unawaited(sosRoute.calculate('${row['id']}', reinforcement: true));
  }

  String? routeOwner;
  void returnToMap() {
    if (mounted) {
      setState(() => tab = 0);
      updateNearbyActivity();
    }
  }

  void routeRequested() {
    final value = SosNavigation.request.value;
    if (!mounted || value == null || currentReportOwner != value.owner) return;
    sosOverview = null;
    sosPreview.clear();
    routeOwner = value.owner;
    setState(() {
      tab = 0;
      historical = false;
      filter = 'Todos';
    });
    updateNearbyActivity();
    unawaited(sosRoute.calculate(value.caseId));
  }

  bool historical = false;
  StreamSubscription<User?>? roleSession;
  int roleGeneration = 0;
  bool operatorAllowed = false;
  bool citizenAllowed = false;
  String? roleOwner;
  bool sosSending = false;
  String sosProgress = 'Enviando…';
  Timer? expiryTimer;

  Future<void> checkRole(User? user) async {
    if (roleOwner != user?.uid) {
      operatorPresence.configure(null);
      routeRecovery.reset();
      sosOverview = null;
      citizenSos.configure(null);
      roleOwner = user?.uid;
      sosPreview.clear();
      if (mounted) setState(() => citizenAllowed = false);
      mapIncidents.clearSession();
    }
    if (OperatorDuty.owner != user?.uid) {
      sosArrival.configure(false);
      OperatorDuty.clear();
    }
    reinforcements.configure(false);
    final ticket = ++roleGeneration;
    if (user?.uid != routeOwner) {
      routeOwner = null;
      sosRoute.clear();
    }
    density.clear();
    density.schedule();
    if (user == null) {
      if (mounted) {
        setState(() {
          operatorAllowed = false;
          citizenAllowed = false;
          if (tab >= 2) tab = 0;
        });
      }
      return;
    }
    try {
      final profile = await WorkflowClient.profile();
      if (mounted &&
          ticket == roleGeneration &&
          currentReportOwner == user.uid) {
        final allowed =
            profile['status'] == 'active' &&
            ['operator', 'admin'].contains(profile['role']);
        final citizen =
            profile['status'] == 'active' && profile['role'] == 'citizen';
        operatorPresence.configure(allowed ? user.uid : null);
        citizenSos.configure(citizen ? user.uid : null);
        sosArrival.configure(allowed);
        reinforcements.configure(allowed && foreground);
        if (!allowed) OperatorDuty.clear();
        if (!allowed && sosPreview.caseId != null) sosPreview.clear();
        if (operatorAllowed != allowed || citizenAllowed != citizen) {
          setState(() {
            if (operatorAllowed != allowed && tab == 1) {
              tab = 0;
            }
            operatorAllowed = allowed;
            citizenAllowed = citizen;
            if (!allowed) sosRoute.clear();
          });
          updateNearbyActivity();
        }
      }
    } catch (_) {
      /* The account panel exposes connection errors and a retry. */
    }
  }

  Future<void> dial() async {
    try {
      await const MethodChannel(
        'trujillo360/proximity',
      ).invokeMethod<void>('dial');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el teléfono.')),
        );
      }
    }
  }

  Future<void> sendSos() async {
    if (sosSending) return;
    final ongoing = ActiveCall.session.value;
    if (ongoing != null && !ongoing.finished) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AudioCallPage(callId: ongoing.callId, operator: ongoing.operator),
        ),
      );
      return;
    }
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión con Google antes de enviar un SOS.'),
        ),
      );
      return;
    }
    final owner = FirebaseAuth.instance.currentUser!.uid;
    setState(() {
      sosSending = true;
      sosProgress = 'Preparando SOS…';
    });
    try {
      await citizenSos.refresh();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != owner) return;
      final activeCase = citizenSos.caseId;
      if (activeCase != null) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => AudioCallPage(callId: activeCase, redial: true),
          ),
        );
        return;
      }
      var pending = await PendingSos.read(owner);
      if (pending == null) {
        if (mounted) setState(() => sosProgress = 'Buscando ubicación…');
        final gps = await LocationService().current();
        final point = LatLng(gps.latitude, gps.longitude);
        if (!mounted) return;
        pending = {
          'request_id': ReportSender.requestId(),
          'latitude': point.latitude,
          'longitude': point.longitude,
        };
        await PendingSos.save(owner, pending);
      }
      if (FirebaseAuth.instance.currentUser?.uid != owner) {
        throw StateError(
          'La sesión cambió. El SOS pendiente se conserva para su cuenta.',
        );
      }
      Map response;
      if (pending['received_id'] is String) {
        response = {'id': pending['received_id']};
      } else {
        if (mounted) setState(() => sosProgress = 'Confirmando envío…');
        response = Map.from(
          await WorkflowClient.request('POST', '/sos', body: pending) as Map,
        );
        if ((response['request_id'] != pending['request_id'] &&
                response['existing_active'] != true) ||
            response['source'] != 'sos' ||
            response['id'] is! String) {
          throw StateError(
            'Respuesta incompleta. El SOS se conserva para reintentar sin duplicarlo.',
          );
        }
        pending['received_id'] = response['id'];
        await PendingSos.save(owner, pending);
      }
      if (FirebaseAuth.instance.currentUser?.uid != owner || !mounted) return;
      setState(() => sosProgress = 'SOS recibido');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS recibido. Preparando conexión de audio.'),
        ),
      );
      unawaited(PushService.instance.ensureSosDevice(requestPermission: true));
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCallPage(
            callId: response['id'] as String,
            redial: response['existing_active'] == true,
          ),
        ),
      );
      if (ActiveCall.session.value?.finished != false) {
        await PendingSos.clear(owner);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SOS recibido por la plataforma. No confirma atención inmediata.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is LocationFailure
                  ? error.message
                  : error is StateError
                  ? error.message.toString()
                  : 'No recibimos confirmación. Tu solicitud queda pendiente en el teléfono. Reintenta con la misma cuenta.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sosSending = false);
    }
  }

  late final NearbyReportsStore nearby = widget.nearby ?? NearbyReportsStore();
  late final MapIncidentsStore mapIncidents =
      widget.mapIncidents ?? MapIncidentsStore();
  bool reportsNearbySelected = false;
  bool foreground = true;
  StreamSubscription<Map<String, dynamic>>? pushOpens;
  StreamSubscription<void>? sosSettingsRoutes;
  void openSosSettingsRoute() {
    if (!mounted || !PushService.instance.pendingSosSettingsRoute) return;
    PushService.instance.pendingSosSettingsRoute = false;
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SosShortcutSettings()),
    );
  }

  final Set<String> openedPush = {};
  void openPush(Map<String, dynamic> data) async {
    if (!mounted || !PushService.instance.valid(data)) return;
    final key = '${data['event_id']}';
    if (!openedPush.add(key)) return;
    PushService.instance.pending = null;
    if ((data['assigned_call'] == 'true' ||
            data['assignment_offer'] == 'true') &&
        operatorAllowed) {
      returnToMap();
      return;
    }
    if (data['kind'] == 'reinforcement') {
      final owner = currentReportOwner;
      try {
        final rows = await WorkflowClient.list('/operator/reinforcements');
        if (!mounted || owner != currentReportOwner) return;
        final matching = rows.where((r) => r['id'] == data['target_id']);
        if (matching.isNotEmpty) {
          selectReinforcement(matching.first, false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La solicitud de refuerzos ya no está activa.'),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir la solicitud de refuerzos.'),
            ),
          );
        }
      }
      return;
    }
    if (data['kind'] == 'sos_callback') {
      returnToMap();
      return;
    }
    if (data['kind'] == 'sos_arrival') {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CitizenSosPage(caseId: '${data['target_id']}'),
        ),
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PushDestination(data: data)),
    );
  }

  @override
  void initState() {
    super.initState();
    CitizenArrivalAlerts.instance.start();
    SosNavigation.request.addListener(routeRequested);
    reinforcements.addListener(reinforcementsChanged);
    OperatorDuty.cases.addListener(dutyPriorityChanged);
    SosNavigation.caseChanges.addListener(caseChanged);
    SosNavigation.mapRequested.addListener(returnToMap);
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      roleSession = FirebaseAuth.instance.authStateChanges().listen(checkRole);
    }
    expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && foreground) {
        setState(() {});
        if (tab == 0 && !historical && !mapIncidents.loading) {
          unawaited(mapIncidents.refresh());
        }
      }
    });
    pushOpens = PushService.instance.opened.stream.listen(openPush);
    sosSettingsRoutes = PushService.instance.sosSettingsRoutes.stream.listen(
      (_) => openSosSettingsRoute(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = PushService.instance.pending;
      if (pending != null) openPush(pending);
      PushService.channel
          .invokeMethod<bool>('takeSosSettingsRoute')
          .then((open) {
            if (open == true) {
              PushService.instance.pendingSosSettingsRoute = true;
              openSosSettingsRoute();
            }
          })
          .catchError((Object _) {});
      openSosSettingsRoute();
    });
  }

  void updateNearbyActivity() {
    citizenSos.configure(citizenAllowed ? roleOwner : null);
    sosArrival.configure(operatorAllowed);
    reinforcements.configure(operatorAllowed && foreground);
    nearby.setActive(
      foreground &&
          (tab == 0 || (!operatorAllowed && tab == 1 && reportsNearbySelected)),
    );
    mapIncidents.setActive(foreground && tab == 0);
    density.configure(enabled: foreground && tab == 0 && historical);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateNearbyActivity();
    if (foreground && Firebase.apps.isNotEmpty) {
      checkRole(FirebaseAuth.instance.currentUser);
    }
    if (foreground && PushService.instance.supported) {
      PushService.channel
          .invokeMethod<String>('takePush')
          .then((raw) {
            if (raw != null) {
              PushService.instance.accept(
                Map<String, dynamic>.from(jsonDecode(raw) as Map),
              );
            }
          })
          .catchError((Object _) {});
    }
  }

  void communityDetails(Incident incident) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CommunityIncidentPage(incident: incident),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pushOpens?.cancel();
    sosSettingsRoutes?.cancel();
    nearby.dispose();
    mapIncidents.dispose();
    roleGeneration++;
    roleSession?.cancel();
    expiryTimer?.cancel();
    SosNavigation.request.removeListener(routeRequested);
    reinforcements.removeListener(reinforcementsChanged);
    OperatorDuty.cases.removeListener(dutyPriorityChanged);
    SosNavigation.caseChanges.removeListener(caseChanged);
    SosNavigation.mapRequested.removeListener(returnToMap);
    sosRoute.dispose();
    sosPreview.dispose();
    operatorPresence.dispose();
    citizenSos.dispose();
    sosArrival.dispose();
    reinforcements.dispose();
    density.dispose();
    super.dispose();
  }

  int tab = 0;
  String filter = 'Todos';
  List<Incident> get visible => mapIncidents
      .filtered(filter)
      .where((i) => i.recentAt(DateTime.now()))
      .toList();
  void details(Incident incident) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReportDetailsPage(report: incident, store: widget.store),
    ),
  );
  Widget settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Configuración del proyecto',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 20),
      const AccountPanel(),
      ListTile(
        leading: const Icon(Icons.sos),
        title: const Text('Mis solicitudes de ayuda'),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Mis solicitudes de ayuda')),
              body: const WorkflowPanel(),
            ),
          ),
        ),
      ),
      const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Backend y WebSocket'),
        subtitle: Text(
          'Los reportes enviados se guardan en el servidor. WebSocket pendiente.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Privacidad'),
        subtitle: Text(
          'Al enviar un reporte se comparte su ubicación con el servidor. El seguimiento GPS se detiene al salir de la app. La copia local no está cifrada.',
        ),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Text('Notificaciones'),
        subtitle: const Text('Permisos y avisos según tu ubicación actual.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const NotificationSettings()),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.sos_outlined),
        title: const Text('SOS con botón de volumen · prueba'),
        subtitle: const Text('Tres pulsaciones de volumen abajo.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const SosShortcutSettings()),
        ),
      ),
      const SizedBox(height: 20),
      const ListTile(
        leading: Icon(Icons.videocam_outlined),
        title: Text('Cámaras e IA'),
        subtitle: Text(
          'Bandeja de detecciones disponible en el panel del operador. Ninguna cámara está conectada.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.person_outline),
        title: Text('Cuentas y panel de operadores'),
        subtitle: Text(
          'El servidor verifica el rol de la cuenta en cada operación. Solicitar ayuda no confirma atención institucional.',
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.store,
      nearby,
      mapIncidents,
      density,
      sosRoute,
      sosPreview,
      ActiveCall.session,
      ActiveCall.presentation,
      reinforcements,
    ]),
    builder: (context, _) => Theme(
      data: Theme.of(context),
      child: Builder(
        builder: (context) => Scaffold(
          drawer: tab == 0
              ? MapFiltersDrawer(
                  categories: categories,
                  selected: filter,
                  historical: historical,
                  hourBand: density.hourBand,
                  loading: density.loading,
                  error: density.error,
                  onCategory: (value) => setState(() => filter = value),
                  onPeriod: (value) {
                    if (value) previewSos(null);
                    setState(() {
                      historical = value;
                      density.configure(
                        enabled: value && foreground && tab == 0,
                      );
                    });
                  },
                  onHour: (value) => setState(
                    () => density.configure(enabled: true, band: value),
                  ),
                )
              : null,

          appBar: AppBar(
            centerTitle: true,
            titleSpacing: 12,
            title: Semantics(
              label: 'Trujillo 360',
              image: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xfff4f6f2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    height: 40,
                    width: 220,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: dial,
                tooltip: 'Seguridad ciudadana · (044) 298734',
                icon: const Icon(Icons.phone_outlined),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  children: [
                    if (widget.store.error != null)
                      MaterialBanner(
                        content: Text(widget.store.error!),
                        actions: const [SizedBox.shrink()],
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: tab,
                        children: [
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (historical
                                    ? density.loading
                                    : mapIncidents.loading)
                                  const LinearProgressIndicator(),
                                if (mapIncidents.note != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(mapIncidents.note!),
                                  ),
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CitizenSosMapLayer(
                                        onActiveCases: (rows) =>
                                            citizenSos.replace(roleOwner, rows),
                                        onCasesChanged: () =>
                                            unawaited(mapIncidents.refresh()),
                                        enabled:
                                            !operatorAllowed && !historical,
                                        active:
                                            foreground &&
                                            tab == 0 &&
                                            (ModalRoute.isCurrentOf(context) ??
                                                true),
                                        builder: (myMarkers, myIncidentIds) => OperatorSosMapLayer(
                                          onOverview: (bounds) => setState(() {
                                            sosOverview = bounds;
                                            sosOverviewRevision++;
                                          }),
                                          onPreview: (id) {
                                            if (sosOverview != null) {
                                              setState(
                                                () => sosOverview = null,
                                              );
                                            }
                                            previewSos(id);
                                          },
                                          reinforcements: reinforcements,
                                          onReinforcement: selectReinforcement,
                                          enabled:
                                              operatorAllowed && !historical,
                                          active:
                                              foreground &&
                                              tab == 0 &&
                                              (ModalRoute.isCurrentOf(
                                                    context,
                                                  ) ??
                                                  true),
                                          builder:
                                              (
                                                sosMarkers,
                                                sosIncidentIds,
                                                sosFocus,
                                              ) => MapPanel(
                                                bottomInset:
                                                    (operatorAllowed
                                                        ? (sosRoute.caseId !=
                                                                  null
                                                              ? 68.0
                                                              : 8.0)
                                                        : 90.0) +
                                                    (ActiveCall
                                                                .session
                                                                .value
                                                                ?.minimized ==
                                                            true
                                                        ? 58.0
                                                        : 0.0),
                                                extraMarkers: {
                                                  ...sosMarkers,
                                                  ...myMarkers,
                                                  if (operatorAllowed &&
                                                      sosRoute.origin != null)
                                                    Marker(
                                                      markerId: const MarkerId(
                                                        'route_origin',
                                                      ),
                                                      position:
                                                          sosRoute.origin!,
                                                      icon:
                                                          BitmapDescriptor.defaultMarkerWithHue(
                                                            BitmapDescriptor
                                                                .hueAzure,
                                                          ),
                                                      infoWindow: const InfoWindow(
                                                        title:
                                                            'Mi ubicación · inicio de ruta',
                                                      ),
                                                    ),
                                                  if (operatorAllowed &&
                                                      sosRoute.destination !=
                                                          null)
                                                    Marker(
                                                      markerId: const MarkerId(
                                                        'route_destination',
                                                      ),
                                                      position:
                                                          sosRoute.destination!,
                                                      infoWindow: const InfoWindow(
                                                        title:
                                                            'Destino · caso SOS',
                                                      ),
                                                    ),
                                                },
                                                polylines: {
                                                  if (operatorAllowed &&
                                                      sosRoute
                                                          .points
                                                          .isNotEmpty)
                                                    Polyline(
                                                      polylineId:
                                                          const PolylineId(
                                                            'sos_route',
                                                          ),
                                                      points: sosRoute.points,
                                                      color:
                                                          sosRoute
                                                              .isReinforcement
                                                          ? ReinforcementControls
                                                                .orange
                                                          : const Color(
                                                              0xff1769ce,
                                                            ),
                                                      width: 6,
                                                    ),
                                                  if (operatorAllowed &&
                                                      !historical &&
                                                      sosPreview
                                                          .points
                                                          .isNotEmpty)
                                                    Polyline(
                                                      polylineId:
                                                          const PolylineId(
                                                            'sos_preview',
                                                          ),
                                                      points: sosPreview.points,
                                                      color: const Color(
                                                        0xffc41728,
                                                      ),
                                                      zIndex: 1,
                                                      width: 6,
                                                    ),
                                                },
                                                routeBounds:
                                                    sosOverview ??
                                                    (!operatorAllowed
                                                        ? null
                                                        : !historical &&
                                                              sosPreview
                                                                      .caseId !=
                                                                  null
                                                        ? sosPreview.bounds
                                                        : sosRoute.bounds),
                                                routeRevision:
                                                    sosRoute.revision +
                                                    sosPreview.revision +
                                                    sosOverviewRevision,
                                                focusTarget: sosFocus?.target,
                                                focusRevision:
                                                    sosFocus?.revision ?? 0,
                                                incidents: historical
                                                    ? const []
                                                    : visible
                                                          .where(
                                                            (i) =>
                                                                !sosIncidentIds
                                                                    .contains(
                                                                      i.id,
                                                                    ) &&
                                                                !myIncidentIds
                                                                    .contains(
                                                                      i.id,
                                                                    ),
                                                          )
                                                          .toList(),
                                                overlays: historical
                                                    ? density.overlays
                                                    : const {},
                                                onIncident: communityDetails,
                                                currentLocation:
                                                    nearby.position == null
                                                    ? null
                                                    : LatLng(
                                                        nearby
                                                            .position!
                                                            .latitude,
                                                        nearby
                                                            .position!
                                                            .longitude,
                                                      ),
                                                onLocate: nearby.start,
                                                locating: nearby.locating,
                                                locationRadius: 500,
                                                onViewportChanged: (bounds) {
                                                  mapIncidents.setBounds(
                                                    bounds,
                                                  );
                                                  density.setBounds(bounds);
                                                },
                                                active: tab == 0,
                                              ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 12,
                                        right: 12,
                                        bottom: 12,
                                        child: MapBottomControls(
                                          citizenSos: citizenSos,
                                          operator: operatorAllowed,
                                          showSos: citizenAllowed,
                                          route: sosRoute,
                                          sending: sosSending,
                                          sendingLabel: sosProgress,
                                          onSos: sendSos,
                                        ),
                                      ),
                                      if (operatorAllowed)
                                        Positioned(
                                          right: 12,
                                          bottom: 160,
                                          child: ValueListenableBuilder<String?>(
                                            valueListenable: sosArrival,
                                            builder: (context, message, _) =>
                                                message == null
                                                ? const SizedBox.shrink()
                                                : IconButton.filledTonal(
                                                    tooltip: message,
                                                    icon: const Icon(
                                                      Icons.gps_off,
                                                      color: Colors.orange,
                                                    ),
                                                    onPressed: () =>
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              message,
                                                            ),
                                                          ),
                                                        ),
                                                  ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!operatorAllowed)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  filters(),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: ReportsPanel(
                                      filter: filter,
                                      active: tab == 1,
                                      nearby: nearby,
                                      onSessionChanged:
                                          mapIncidents.clearSession,
                                      onNearbySelected: (value) {
                                        reportsNearbySelected = value;
                                        updateNearbyActivity();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (operatorAllowed)
                            const OperatorPortal(embedded: true),
                          settings(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) {
                  setState(() => tab = i);
                  updateNearbyActivity();
                },
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    label: 'Mapa',
                  ),
                  if (!operatorAllowed)
                    NavigationDestination(
                      icon: Icon(Icons.notifications_none),
                      label: 'Reportes',
                    ),
                  if (operatorAllowed)
                    NavigationDestination(
                      icon: Icon(Icons.support_agent_outlined),
                      label: 'Operador',
                    ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: 'Configuración',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: categories
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  ReportStyle.forCategory(c).icon,
                  size: 20,
                  color: ReportStyle.forCategory(c).color,
                ),
                label: Text(c),
                labelStyle: TextStyle(
                  color: ReportStyle.forCategory(c).color,
                  fontWeight: filter == c ? FontWeight.w700 : FontWeight.w500,
                ),
                showCheckmark: false,
                backgroundColor: ReportStyle.forCategory(
                  c,
                ).color.withValues(alpha: 0.05),
                selectedColor: ReportStyle.forCategory(
                  c,
                ).color.withValues(alpha: 0.16),
                side: BorderSide(
                  color: ReportStyle.forCategory(
                    c,
                  ).color.withValues(alpha: filter == c ? 0.65 : 0.22),
                ),
                selected: filter == c,
                onSelected: (_) => setState(() => filter = c),
              ),
            ),
          )
          .toList(),
    ),
  );
}
