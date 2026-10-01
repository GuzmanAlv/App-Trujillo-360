import 'package:flutter/material.dart';
import 'data/incident_store.dart';
import 'models/incident.dart';
import 'models/report.dart';
import 'models/demo_profile.dart';
import 'core/config.dart';
import 'services/push_service.dart';
import 'ui/map_panel.dart';
import 'ui/report_form.dart';
import 'data/ai_detection_store.dart';
import 'ui/ai_detection_panel.dart';
import 'ui/incident_details.dart';
import 'ui/review_panel.dart';

class TrujilloApp extends StatelessWidget {
  const TrujilloApp({super.key, required this.store});
  final IncidentStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Trujillo 360',
    debugShowCheckedModeBanner: false,
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
  const HomePage({super.key, required this.store});
  final IncidentStore store;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final aiStore = AiDetectionStore();

  @override
  void dispose() {
    aiStore.dispose();
    super.dispose();
  }

  int tab = 0;
  String filter = 'Todos';
  String pushStatus = 'Sin activar';
  bool requestingPush = false;
  List<Incident> get visible => widget.store.mapItems
      .where((i) => filter == 'Todos' || i.type == filter)
      .toList();
  void details(Incident i) => showIncidentDetails(context, widget.store, i.id);
  Widget list() {
    final cases = widget.store.ownItems
        .where((i) => filter == 'Todos' || i.type == filter)
        .toList();
    return cases.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No has reportado en esta categoría.\nCrea uno con el botón Reportar.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.builder(
            itemCount: cases.length,
            itemBuilder: (context, index) {
              final i = cases[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text('${i.type} · ${i.place}'),
                  subtitle: Text(
                    '${i.status.label} · ${i.reporterCount} perfiles distintos\n'
                    '${i.isVisible ? 'Visible en mapa' : 'No visible en mapa'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => details(i),
                ),
              );
            },
          );
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Configuración del proyecto',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 20),
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
          'No conectados. Los reportes se guardan únicamente en este dispositivo.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Privacidad'),
        subtitle: Text(
          'Tu ubicación no se envía al servidor. El seguimiento se detiene al salir de la app. Usa datos de prueba: el almacenamiento local no está cifrado.',
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
        subtitle: Text(
          'Perfiles ficticios para probar reportes y revisión. No hay cuentas reales ni autenticación.',
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trujillo 360',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          Chip(label: Text('DEMO')),
          SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DropdownButtonFormField<DemoProfile>(
                    key: const Key('demo-profile'),
                    initialValue: widget.store.profile,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Perfil de prueba',
                    ),
                    items: DemoProfile.values
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.label)),
                        )
                        .toList(),
                    onChanged: widget.store.saving
                        ? null
                        : (p) {
                            if (p == null) return;
                            setState(() => tab = 0);
                            widget.store.selectProfile(p);
                          },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Demo local: los perfiles y la verificación son simulados.',
                  ),
                ),
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
                              'Visible con 3 perfiles distintos o verificación de prueba. '
                              'Misma categoría, hasta 150 m y 30 minutos. Sin conexión con emergencias.',
                            ),
                            const SizedBox(height: 12),
                            filters(),
                            Text('${visible.length} casos visibles'),
                            const SizedBox(height: 12),
                            Expanded(
                              child: MapPanel(
                                incidents: visible,
                                onIncident: details,
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
                            Expanded(child: list()),
                          ],
                        ),
                      ),
                      settings(),
                      AiDetectionPanel(store: aiStore),
                      if (widget.store.profile.isAdmin)
                        ReviewPanel(store: widget.store),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: tab >= 2 || widget.store.profile.isAdmin
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
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            label: 'Mapa',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_none),
            label: 'Mis reportes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Configuración',
          ),
          const NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            label: 'IA',
          ),
          if (widget.store.profile.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              label: 'Revisión',
            ),
        ],
      ),
    ),
  );
  Widget filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: ['Todos', ...incidentCategories]
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c),
                selected: filter == c,
                onSelected: (_) => setState(() => filter = c),
              ),
            ),
          )
          .toList(),
    ),
  );
}
