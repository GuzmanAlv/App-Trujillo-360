import 'package:flutter/material.dart';
import 'data/incident_store.dart';
import 'data/nearby_reports_store.dart';
import 'data/map_incidents_store.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'models/incident.dart';
import 'core/config.dart';
import 'services/push_service.dart';
import 'ui/report_details_page.dart';
import 'ui/community_incident_page.dart';
import 'ui/reports_panel.dart';
import 'ui/map_panel.dart';
import 'ui/report_form.dart';
import 'ui/report_style.dart';
import 'ui/account_panel.dart';
import 'data/ai_detection_store.dart';
import 'ui/ai_detection_panel.dart';
import 'services/proximity_alerts.dart';
import 'services/nearby_reports_client.dart';
import 'ui/nearby_incident_page.dart';
import 'ui/proximity_alert_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final aiStore = AiDetectionStore();
  late final NearbyReportsStore nearby = widget.nearby ?? NearbyReportsStore();
  late final MapIncidentsStore mapIncidents =
      widget.mapIncidents ?? MapIncidentsStore();
  bool reportsNearbySelected = true;
  bool foreground = true;
  bool alertsEnabled = false;
  final notifications = ProximityNotifications();
  ProximityAlertPolicy alertPolicy = ProximityAlertPolicy();
  String? alertOwner;

  void openAlert(Incident incident) {
    if (!mounted || currentReportOwner == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NearbyIncidentPage(
          incident: incident,
          distance: nearby.distance(incident),
        ),
      ),
    );
  }

  Future<void> restoreAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    notifications.listen(openAlert);
    final pending = await notifications.takePending();
    if (!mounted) return;
    if (pending != null) openAlert(pending);
    if (prefs.getBool('proximity_alerts_enabled') ?? false) {
      alertOwner = currentReportOwner;
      setState(() => alertsEnabled = true);
      nearby.pollContinuously = true;
      updateNearbyActivity();
      await nearby.start();
    }
  }

  void checkAlerts() {
    final owner = currentReportOwner;
    if (owner != alertOwner) {
      alertOwner = owner;
      alertPolicy = ProximityAlertPolicy();
    }
    if (!alertsEnabled || !foreground || owner == null) return;
    for (final incident in alertPolicy.collect(
      nearby.filtered('Todos'),
      nearby.distance,
      DateTime.now(),
    )) {
      final meters = nearby.distance(incident).round();
      notifications.show(incident, meters).catchError((Object _) {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.white,
          elevation: 10,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xffdbe8e1)),
          ),
          duration: const Duration(seconds: 12),
          content: ProximityAlertCard(
            incident: incident,
            meters: meters,
            onDismiss: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            onOpen: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              openAlert(incident);
            },
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nearby.addListener(checkAlerts);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreAlerts().catchError((Object _) {});
    });
  }

  void updateNearbyActivity() {
    nearby.setActive(
      foreground &&
          (alertsEnabled || tab == 0 || (tab == 1 && reportsNearbySelected)),
    );
    mapIncidents.setActive(foreground && tab == 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateNearbyActivity();
    if (foreground) {
      notifications
          .takePending()
          .then((i) {
            if (i != null) openAlert(i);
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
    notifications.dispose();
    nearby.removeListener(checkAlerts);
    nearby.dispose();
    mapIncidents.dispose();
    aiStore.dispose();
    super.dispose();
  }

  int tab = 0;
  String filter = 'Todos';
  String pushStatus = 'Sin activar';
  bool requestingPush = false;
  List<Incident> get visible => mapIncidents.filtered(filter);
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
      SwitchListTile(
        title: const Text('Alertas a 500 metros'),
        subtitle: const Text(
          'Incidencias nuevas, incluso pendientes de corroboración. Se consultan cada 15 segundos mientras la app está abierta. Requiere sesión y ubicación.',
        ),
        value: alertsEnabled,
        onChanged: (value) async {
          if (value) {
            try {
              final allowed = await notifications.enable();
              if (!mounted) return;
              if (!allowed && notifications.supported) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Permite las notificaciones en los ajustes de Android. Los avisos también se mostrarán dentro de la app.',
                    ),
                  ),
                );
              }
            } catch (_) {
              /* In-app alerts remain available. */
            }
          }
          if (!mounted) return;
          setState(() => alertsEnabled = value);
          alertPolicy = ProximityAlertPolicy();
          alertOwner = currentReportOwner;
          nearby.pollContinuously = value;
          updateNearbyActivity();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('proximity_alerts_enabled', value);
          if (value && mounted) await nearby.start();
        },
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
        subtitle: Text(pushStatus),
      ),
      FilledButton.tonal(
        onPressed: requestingPush
            ? null
            : () async {
                setState(() => requestingPush = true);
                final status = await PushService().enable();
                if (mounted) {
                  setState(() {
                    pushStatus = status;
                    requestingPush = false;
                  });
                }
              },
        child: Text(
          requestingPush ? 'Configurando…' : 'Activar notificaciones',
        ),
      ),
      const SizedBox(height: 20),
      const ListTile(
        leading: Icon(Icons.videocam_outlined),
        title: Text('Cámaras e IA'),
        subtitle: Text(
          'Bandeja de detecciones preparada en la pestaña IA. Ninguna cámara está conectada.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.person_outline),
        title: Text('Cuentas y panel de operadores'),
        subtitle: Text('Panel de operadores pendiente de conexión al backend.'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, nearby, mapIncidents]),
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
        actions: const [
          Chip(label: Text('PILOTO')),
          SizedBox(width: 12),
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
                              'Incidentes corroborados. Toca el mapa para explorar 500 m.',
                            ),
                            const SizedBox(height: 12),
                            filters(),
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
                                incidents: visible,
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
                                onViewportChanged: mapIncidents.setBounds,
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
                      AiDetectionPanel(store: aiStore),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            label: 'IA',
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
