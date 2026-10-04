import 'package:flutter/material.dart';
import 'data/incident_store.dart';
import 'models/incident.dart';
import 'core/config.dart';
import 'services/push_service.dart';
import 'ui/map_panel.dart';
import 'ui/report_form.dart';
import 'ui/report_style.dart';
import 'data/ai_detection_store.dart';
import 'ui/ai_detection_panel.dart';

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
  List<Incident> get visible => widget.store.items
      .where((i) => filter == 'Todos' || i.type == filter)
      .toList();
  void details(Incident i) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReportCategoryIcon(category: i.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    i.type,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: ReportStyle.forCategory(i.type).color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(i.place),
            const SizedBox(height: 12),
            Text(
              i.description.isEmpty
                  ? 'Sin descripción adicional.'
                  : i.description,
            ),
            const SizedBox(height: 12),
            Text(
              '${i.latitude.toStringAsFixed(6)}, ${i.longitude.toStringAsFixed(6)}',
            ),
            Text(
              'Registrado: ${i.createdAt.toLocal().toString().substring(0, 16)}',
            ),
            const SizedBox(height: 12),
            const Chip(label: Text('Sin verificar · Solo en este dispositivo')),
            const Text(
              'Atención: sin asignar. Este reporte no se ha enviado a operadores.',
            ),
          ],
        ),
      ),
    ),
  );
  Widget list() => visible.isEmpty
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No hay reportes en esta categoría.\nCrea uno con el botón Reportar.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final i = visible[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: ReportCategoryIcon(category: i.type),
                title: Text('${i.type} · ${i.place}'),
                subtitle: Text(
                  'Reportado ${reportTime(i.createdAt)} · Sin verificar',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => details(i),
              ),
            );
          },
        );
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
          'Pendientes de autenticación y backend. Esta app no simula confirmaciones de operadores.',
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
          Chip(label: Text('LOCAL')),
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
                              'Reportes locales para probar el proyecto. Sin conexión con emergencias.',
                            ),
                            const SizedBox(height: 12),
                            filters(),
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
        onDestinationSelected: (i) => setState(() => tab = i),
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
