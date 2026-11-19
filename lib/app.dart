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
import 'ui/hold_sos_button.dart';
import 'ui/audio_call_page.dart';
import 'ui/push_destination.dart';
import 'ui/report_details_page.dart';
import 'ui/community_incident_page.dart';
import 'ui/reports_panel.dart';
import 'ui/map_panel.dart';
import 'ui/report_form.dart';
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
  bool historical = false;
  StreamSubscription<User?>? roleSession;
  int roleGeneration = 0;
  bool operatorAllowed = false;
  bool sosSending = false;
  String? pendingSosId;
  String? pendingSosOwner;
  double? pendingSosLatitude, pendingSosLongitude;
  Timer? expiryTimer;

  Future<void> checkRole(User? user) async {
    final ticket = ++roleGeneration;
    if (user?.uid != pendingSosOwner) {
      pendingSosId = null;
      pendingSosOwner = null;
      pendingSosLatitude = null;
      pendingSosLongitude = null;
    }
    density.clear();
    density.schedule();
    if (user == null) {
      if (mounted) {
        setState(() {
          operatorAllowed = false;
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
        if (operatorAllowed != allowed) {
          setState(() {
            if (!operatorAllowed && allowed && tab == 2) {
              tab = 3;
            }
            if (operatorAllowed && !allowed && tab == 3) {
              tab = 2;
            } else if (operatorAllowed && !allowed && tab == 2) {
              tab = 0;
            }
            operatorAllowed = allowed;
          });
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
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión con Google antes de enviar un SOS.'),
        ),
      );
      return;
    }
    final owner = FirebaseAuth.instance.currentUser!.uid;
    setState(() => sosSending = true);
    try {
      if (pendingSosId == null) {
        final position = await LocationService().current();
        if (FirebaseAuth.instance.currentUser?.uid != owner) {
          throw StateError('La sesión cambió. Vuelve a intentarlo.');
        }
        pendingSosId = ReportSender.requestId();
        pendingSosOwner = owner;
        pendingSosLatitude = position.latitude;
        pendingSosLongitude = position.longitude;
      }
      if (FirebaseAuth.instance.currentUser?.uid != owner) {
        throw StateError('La sesión cambió. Vuelve a intentarlo.');
      }
      final response = await WorkflowClient.request(
        'POST',
        '/sos',
        body: {
          'request_id': pendingSosId,
          'latitude': pendingSosLatitude,
          'longitude': pendingSosLongitude,
        },
      );
      if (response is! Map ||
          response['request_id'] != pendingSosId ||
          response['source'] != 'sos') {
        throw StateError('No se confirmó el SOS. Vuelve a intentarlo.');
      }
      pendingSosId = null;
      pendingSosOwner = null;
      pendingSosLatitude = null;
      pendingSosLongitude = null;
      if (mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => AudioCallPage(callId: response['id'] as String),
          ),
        );
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
                  : 'No se confirmó el SOS. Vuelve a intentarlo.',
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
  bool reportsNearbySelected = true;
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
  void openPush(Map<String, dynamic> data) {
    if (!mounted || !PushService.instance.valid(data)) return;
    final key = '${data['event_id']}';
    if (!openedPush.add(key)) return;
    PushService.instance.pending = null;
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PushDestination(data: data)),
    );
  }

  @override
  void initState() {
    super.initState();
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
    nearby.setActive(
      foreground && (tab == 0 || (tab == 1 && reportsNearbySelected)),
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
    listenable: Listenable.merge([widget.store, nearby, mapIncidents, density]),
    builder: (context, _) => Theme(
      data: Theme.of(context),
      child: Builder(
        builder: (context) => Scaffold(
          drawer: tab == 0
              ? Drawer(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Filtros del mapa',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar filtros',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text('Tipo de incidente'),
                        if (!historical)
                          Wrap(
                            spacing: 8,
                            children: categories
                                .map(
                                  (c) => ChoiceChip(
                                    label: Text(c),
                                    selected: filter == c,
                                    onSelected: (_) =>
                                        setState(() => filter = c),
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 20),
                        const Text('Periodo del mapa'),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Recientes · 7 días'),
                              selected: !historical,
                              onSelected: (_) => setState(() {
                                historical = false;
                                density.configure(enabled: false);
                              }),
                            ),
                            ChoiceChip(
                              label: const Text('Historial · 90 días'),
                              selected: historical,
                              onSelected: (_) => setState(() {
                                historical = true;
                                density.configure(enabled: true);
                              }),
                            ),
                          ],
                        ),
                        if (historical) ...[
                          DropdownButton<int>(
                            isExpanded: true,
                            value: density.hourBand,
                            items: const [
                              DropdownMenuItem(
                                value: -1,
                                child: Text('Todas las horas'),
                              ),
                              DropdownMenuItem(
                                value: 0,
                                child: Text('Madrugada · 00–06 h'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('Mañana · 06–12 h'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('Tarde · 12–18 h'),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text('Noche · 18–24 h'),
                              ),
                            ],
                            onChanged: (v) => setState(
                              () => density.configure(enabled: true, band: v),
                            ),
                          ),
                          const Text(
                            'Todas las categorías · zonas aproximadas: amarillo 1–2; rojo 3 o más. Sin color no significa seguro.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (density.loading) const LinearProgressIndicator(),
                          if (density.error != null)
                            Text(
                              density.error!,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],

                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Ver mapa'),
                        ),
                      ],
                    ),
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
                                  child: OperatorSosMapLayer(
                                    enabled: operatorAllowed && !historical,
                                    active:
                                        foreground &&
                                        tab == 0 &&
                                        (ModalRoute.isCurrentOf(context) ??
                                            true),
                                    builder:
                                        (
                                          sosMarkers,
                                          sosIncidentIds,
                                          sosFocus,
                                        ) => MapPanel(
                                          extraMarkers: sosMarkers,
                                          focusTarget: sosFocus?.target,
                                          focusRevision:
                                              sosFocus?.revision ?? 0,
                                          incidents: historical
                                              ? const []
                                              : visible
                                                    .where(
                                                      (i) => !sosIncidentIds
                                                          .contains(i.id),
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
                                                  nearby.position!.latitude,
                                                  nearby.position!.longitude,
                                                ),
                                          onLocate: nearby.start,
                                          locating: nearby.locating,
                                          locationRadius: 500,
                                          onViewportChanged: (bounds) {
                                            mapIncidents.setBounds(bounds);
                                            density.setBounds(bounds);
                                          },
                                          active: tab == 0,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                filters(),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: ReportsPanel(
                                    store: widget.store,
                                    filter: filter,
                                    onReport: details,
                                    active: tab == 1,
                                    nearby: nearby,
                                    onSessionChanged: mapIncidents.clearSession,
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
              if (tab < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      HoldSosButton(busy: sosSending, onComplete: sendSos),
                      FloatingActionButton.extended(
                        heroTag: 'report',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ReportForm(store: widget.store),
                          ),
                        ),
                        label: const Text('Reportar'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
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
