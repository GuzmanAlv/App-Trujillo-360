import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data/density_store.dart';
import 'services/workflow_client.dart';
import 'ui/workflow_panel.dart';
import 'data/incident_store.dart';
import 'data/nearby_reports_store.dart';
import 'data/map_incidents_store.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models/incident.dart';
import 'core/config.dart';
import 'services/push_service.dart';
import 'ui/notification_settings.dart';
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
    debugShowCheckedModeBanner: false,
    // Reserva el espacio de navegación de Android para todas las rutas.
    // SafeArea elimina ese margen del MediaQuery de los hijos para no duplicarlo.
    builder: (context, child) =>
        SafeArea(top: false, child: child ?? const SizedBox.shrink()),
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
  String? operatorOpenedFor;
  Timer? expiryTimer;

  Future<void> checkRole(User? user) async {
    final ticket = ++roleGeneration;
    density.clear();
    density.schedule();
    if (user == null) {
      operatorOpenedFor = null;
      return;
    }
    try {
      final profile = await WorkflowClient.profile();
      if (mounted &&
          ticket == roleGeneration &&
          currentReportOwner == user.uid &&
          operatorOpenedFor != user.uid &&
          openedPush.isEmpty &&
          profile['status'] == 'active' &&
          ['operator', 'admin'].contains(profile['role'])) {
        operatorOpenedFor = user.uid;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const OperatorPortal()),
        );
        mapIncidents.clearSession();
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

  late final NearbyReportsStore nearby = widget.nearby ?? NearbyReportsStore();
  late final MapIncidentsStore mapIncidents =
      widget.mapIncidents ?? MapIncidentsStore();
  bool reportsNearbySelected = true;
  bool foreground = true;
  StreamSubscription<Map<String, dynamic>>? pushOpens;
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
      if (mounted && foreground) setState(() {});
    });
    pushOpens = PushService.instance.opened.stream.listen(openPush);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = PushService.instance.pending;
      if (pending != null) openPush(pending);
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
        leading: const Icon(Icons.support_agent),
        title: const Text('Panel de seguridad ciudadana'),
        subtitle: const Text(
          'Solo para cuentas Google autorizadas por un administrador.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const OperatorPortal()),
        ),
      ),
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
      ListTile(
        leading: const Icon(Icons.map_outlined),
        title: const Text('Google Maps'),
        subtitle: Text(
          AppConfig.mapsEnabled
              ? 'Activado por configuración. Requiere una clave válida.'
              : 'Pendiente de clave. Modo local disponible.',
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
        subtitle: const Text('Permisos, mi zona y avisos fuera de la app.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const NotificationSettings()),
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
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 12,
        title: Semantics(
          label: 'Trujillo 360',
          image: true,
          child: Image.asset(
            'assets/branding/logo.png',
            height: 44,
            width: 220,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
        actions: [
          IconButton(
            onPressed: dial,
            tooltip: 'Seguridad ciudadana · (044) 298734',
            icon: const Icon(Icons.phone_outlined),
          ),
          const Chip(label: Text('PILOTO')),
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
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tu comunidad, a la vista',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Incidentes corroborados o revisados · últimos 7 días.',
                            ),
                            const SizedBox(height: 12),
                            if (!historical) filters(),
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
                                  () =>
                                      density.configure(enabled: true, band: v),
                                ),
                              ),
                              const Text(
                                'Todas las categorías · zonas aproximadas: amarillo 1–2; rojo 3 o más. Sin color no significa seguro.',
                                style: TextStyle(fontSize: 12),
                              ),
                              if (density.loading)
                                const LinearProgressIndicator(),
                              if (density.error != null)
                                Text(
                                  density.error!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                            const SizedBox(height: 12),
                            if (mapIncidents.loading)
                              const LinearProgressIndicator(),
                            if (mapIncidents.note != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(mapIncidents.note!),
                              ),
                            Expanded(
                              child: MapPanel(
                                incidents: historical ? const [] : visible,
                                overlays: historical
                                    ? density.overlays
                                    : const {},
                                onIncident: communityDetails,
                                currentLocation: nearby.position == null
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
                      settings(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: tab >= 2
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReportForm(store: widget.store),
                ),
              ),
              label: const Text('Reportar'),
              icon: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          updateNearbyActivity();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa'),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            label: 'Reportes',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Configuración',
          ),
        ],
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
