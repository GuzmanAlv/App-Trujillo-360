import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../data/incident_store.dart';
import '../services/location_service.dart';
import '../ui/map_panel.dart';
import '../ui/report_form.dart';
import '../ui/report_photo_view.dart';
import 'pilot_store.dart';

String pilotTime(DateTime date) {
  final d = date.toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

bool matchesHour(DateTime date, int? band) =>
    band == null || date.toLocal().hour ~/ 6 == band;

class PilotHome extends StatefulWidget {
  const PilotHome({super.key, required this.store});
  final PilotStore store;
  @override
  State<PilotHome> createState() => _PilotHomeState();
}

class _PilotHomeState extends State<PilotHome> with WidgetsBindingObserver {
  bool operator = false, locating = false, historical = false;
  int tab = 0;
  int? band;
  Position? position;
  String? locationNote;
  Timer? clock;
  DateTime now = DateTime.now();
  final notices = <String>{};
  @override
  void initState() {
    super.initState();
    notices.addAll(widget.store.cases.map((c) => c.incident.id));
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(checkRequests);
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  void checkRequests() {
    final fresh = widget.store.cases
        .where((c) => c.help && !notices.contains(c.incident.id))
        .toList();
    notices.addAll(fresh.map((c) => c.incident.id));
    if (fresh.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Solicitud local recibida · Urgencia ${fresh.first.priority}. Revisa la bandeja del operador.',
            ),
            action: SnackBarAction(
              label: 'Ver bandeja',
              onPressed: () => setState(() {
                operator = true;
                tab = 0;
              }),
            ),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => now = DateTime.now());
    }
  }

  @override
  void dispose() {
    clock?.cancel();
    widget.store.removeListener(checkRequests);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() {
      locating = true;
      locationNote = null;
    });
    try {
      final p = await LocationService().current();
      if (mounted) {
        setState(() {
          position = p;
          locationNote = 'Precisión GPS aproximada: ±${p.accuracy.round()} m.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => locationNote = e is LocationFailure
              ? e.message
              : 'No se pudo obtener el GPS.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> create(bool help) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportForm(
          store: IncidentStore(widget.store.preferences),
          requestHelp: help,
          onLocalSubmit: (incident, priority) => widget.store.submit(
            incident,
            help: help,
            priority: help ? priority : 'Baja',
          ),
        ),
      ),
    );
    if (mounted) setState(() => now = DateTime.now());
  }

  void detail(PilotCase item, {bool publicView = false}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PilotDetails(
          id: item.incident.id,
          store: widget.store,
          operator: operator,
          publicView: publicView,
        ),
      ),
    );
  }

  Future<void> dial() async {
    try {
      await const MethodChannel(
        'trujillo360/proximity',
      ).invokeMethod<void>('dial');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abre la aplicación Teléfono de tu celular.'),
          ),
        );
      }
    }
  }

  Widget caseList(List<PilotCase> cases, {bool publicView = false}) =>
      cases.isEmpty
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Todavía no hay casos para mostrar.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : ListView.builder(
          itemCount: cases.length,
          itemBuilder: (_, index) {
            final c = cases[index];
            final expired = !c.activeAt(now);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: Icon(
                  c.help && !publicView
                      ? Icons.sos
                      : Icons.location_on_outlined,
                  color: c.help && !publicView
                      ? Colors.red.shade700
                      : const Color(0xff087f68),
                ),
                title: Text('${c.incident.type} · ${c.incident.place}'),
                subtitle: Text(
                  publicView
                      ? 'Revisado por operador (prueba) · ${pilotTime(c.incident.createdAt)}'
                      : '${c.help ? 'Ayuda · Urgencia ${c.priority}' : 'Reporte informativo'}\n${c.stage} · ${pilotTime(c.incident.createdAt)}${expired ? '\nFuera del mapa activo; conserva seguimiento' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                isThreeLine: !publicView,
                onTap: () => detail(c, publicView: publicView),
              ),
            );
          },
        );

  Widget citizenMap() {
    final cases = widget.store.cases
        .where(
          (c) =>
              c.publicAt(now, historical: historical) &&
              matchesHour(c.incident.createdAt, band),
        )
        .toList();
    final groups = <String, List<PilotCase>>{};
    if (historical) {
      for (final c in cases) {
        final key =
            '${(c.incident.latitude / .001).floor()}:${(c.incident.longitude / .001).floor()}';
        (groups[key] ??= []).add(c);
      }
    }
    final overlays = <Circle>{};
    for (final entry in groups.entries) {
      final count = entry.value.length;
      // Require at least three independent cases to display a concentration.
      if (count < 3) continue;
      final coordinates = entry.key.split(':').map(int.parse).toList();
      final color = count >= 6 ? Colors.red : Colors.orange;
      overlays.add(
        Circle(
          circleId: CircleId('density:${entry.key}'),
          center: LatLng(
            (coordinates[0] + .5) * .001,
            (coordinates[1] + .5) * .001,
          ),
          radius: 80,
          fillColor: color.withValues(alpha: .25),
          strokeColor: color,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$count casos revisados en esta zona y franja · últimos 7 días. No es una predicción de peligro.',
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Recientes')),
              ButtonSegment(value: true, label: Text('Por horario')),
            ],
            selected: {historical},
            onSelectionChanged: (value) =>
                setState(() => historical = value.single),
          ),
        ),
        if (historical)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<int>(
              initialValue: band ?? -1,
              decoration: const InputDecoration(
                labelText: 'Hora local del hecho · últimos 7 días',
              ),
              items: const [
                DropdownMenuItem(value: -1, child: Text('Todas las horas')),
                DropdownMenuItem(value: 0, child: Text('Madrugada · 00–06 h')),
                DropdownMenuItem(value: 1, child: Text('Mañana · 06–12 h')),
                DropdownMenuItem(value: 2, child: Text('Tarde · 12–18 h')),
                DropdownMenuItem(value: 3, child: Text('Noche · 18–24 h')),
              ],
              onChanged: (value) =>
                  setState(() => band = value == -1 ? null : value),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            historical
                ? 'Concentración por zonas aproximadas: naranja 3–5 casos; rojo 6 o más. Sin color: información insuficiente, no significa seguro. No colorea calles exactas.'
                : 'Solo casos revisados y vigentes: hasta 2 horas desde el hecho. La caducidad no confirma que el peligro terminó.',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MapPanel(
              incidents: cases.map((c) => c.incident).toList(),
              overlays: overlays,
              active: tab == 0 && !operator,
              currentLocation: position == null
                  ? null
                  : LatLng(position!.latitude, position!.longitude),
              onLocate: locate,
              locating: locating,
              onIncident: (i) => detail(
                cases.firstWhere((c) => c.incident.id == i.id),
                publicView: true,
              ),
            ),
          ),
        ),
        if (locationNote != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(locationNote!)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => create(false),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Reportar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: () => create(true),
                  icon: const Icon(Icons.sos),
                  label: const Text('Pedir ayuda'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget nearMe() {
    final cases = widget.store.cases
        .where(
          (c) =>
              c.publicAt(now) &&
              position != null &&
              Geolocator.distanceBetween(
                    position!.latitude,
                    position!.longitude,
                    c.incident.latitude,
                    c.incident.longitude,
                  ) <=
                  1000,
        )
        .toList();
    if (position != null) {
      cases.sort(
        (a, b) =>
            Geolocator.distanceBetween(
              position!.latitude,
              position!.longitude,
              a.incident.latitude,
              a.incident.longitude,
            ).compareTo(
              Geolocator.distanceBetween(
                position!.latitude,
                position!.longitude,
                b.incident.latitude,
                b.incident.longitude,
              ),
            ),
      );
    }
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Casos revisados y vigentes a menos de 1 km. Los pendientes permanecen en la bandeja del operador.',
          ),
        ),
        TextButton.icon(
          onPressed: locating ? null : locate,
          icon: const Icon(Icons.my_location),
          label: Text(
            locating ? 'Buscando ubicación…' : 'Actualizar mi ubicación',
          ),
        ),
        if (locationNote != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(locationNote!)),
        if (position == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Activa tu ubicación para consultar Cerca de ti.'),
          ),
        Expanded(child: caseList(cases, publicView: true)),
      ],
    );
  }

  Widget operatorInbox() {
    final items = List<PilotCase>.of(widget.store.cases);
    const rank = {'Alta': 0, 'Media': 1, 'Baja': 2};
    items.sort((a, b) {
      final terminal = (a.terminal ? 1 : 0).compareTo(b.terminal ? 1 : 0);
      if (terminal != 0) return terminal;
      final help = (a.help ? 0 : 1).compareTo(b.help ? 0 : 1);
      if (help != 0) return help;
      final priority = rank[a.priority]!.compareTo(rank[b.priority]!);
      return priority != 0 ? priority : b.receivedAt.compareTo(a.receivedAt);
    });
    final requests = items.where((c) => c.help && !c.terminal).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$requests solicitudes de ayuda abiertas',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Avisos locales de ayuda primero; después reportes informativos. Revisa cada caso antes de publicar.',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: caseList(items)),
      ],
    );
  }

  Widget information() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Cómo probar',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      const Text(
        '1. En Ciudadano, registra un hecho o solicita ayuda.\n2. Cambia arriba a Operador. Abre el caso, revisa y registra una decisión con su motivo.\n3. Vuelve a Ciudadano → Mis casos para consultar el seguimiento.\n4. Publica un caso revisado para verlo en el mapa; Cerca de ti también requiere GPS y una distancia menor de 1 km.',
      ),
      const ListTile(
        leading: Icon(Icons.schedule),
        title: Text('Vigencia de prueba'),
        subtitle: Text(
          '2 horas en el mapa activo y 7 días para concentración por horario. El seguimiento de ayuda no se cierra por caducidad. Son reglas del piloto por validar.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Datos solo en este celular'),
        subtitle: Text(
          'No hay envío al servidor, comunicación entre dispositivos ni atención institucional. Cambiar de vista simula dos roles; no concede permisos de una cuenta real. Los datos locales no están cifrados: usa casos ficticios.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.phone_outlined),
        title: Text('Llamar por separado'),
        subtitle: Text(
          'Puedes abrir el teléfono e introducir el número del servicio que corresponda. La app no inicia llamadas ni adjunta tu reporte automáticamente.',
        ),
      ),
      OutlinedButton.icon(
        onPressed: dial,
        icon: const Icon(Icons.phone),
        label: const Text('Abrir teléfono'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final body = operator
          ? (tab == 0
                ? operatorInbox()
                : tab == 1
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Cámaras e IA\n\nSin cámaras ni inferencia conectadas. Los posibles eventos necesitarán revisión del operador antes de publicarse.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : information())
          : (tab == 0
                ? citizenMap()
                : tab == 1
                ? nearMe()
                : tab == 2
                ? caseList(widget.store.cases)
                : information());
      return Scaffold(
        appBar: AppBar(
          title: const Text('Trujillo 360'),
          actions: [
            IconButton(
              onPressed: dial,
              tooltip: 'Abrir teléfono',
              icon: const Icon(Icons.phone_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.amber.shade100,
              child: const Text(
                'PRUEBA LOCAL · No contacta a seguridad ciudadana',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.person_outline),
                    label: Text('Ciudadano'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.support_agent),
                    label: Text('Operador'),
                  ),
                ],
                selected: {operator},
                onSelectionChanged: (value) => setState(() {
                  operator = value.single;
                  tab = 0;
                  now = DateTime.now();
                }),
              ),
            ),
            if (widget.store.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.store.error!),
              ),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() {
            tab = value;
            now = DateTime.now();
          }),
          destinations: operator
              ? const [
                  NavigationDestination(
                    icon: Icon(Icons.inbox_outlined),
                    label: 'Bandeja',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.videocam_outlined),
                    label: 'Cámaras / IA',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.info_outline),
                    label: 'Prueba',
                  ),
                ]
              : const [
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    label: 'Mapa',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.near_me_outlined),
                    label: 'Cerca de ti',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    label: 'Mis casos',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.info_outline),
                    label: 'Prueba',
                  ),
                ],
        ),
      );
    },
  );
}

class PilotDetails extends StatefulWidget {
  const PilotDetails({
    super.key,
    required this.id,
    required this.store,
    required this.operator,
    required this.publicView,
  });
  final String id;
  final PilotStore store;
  final bool operator, publicView;
  @override
  State<PilotDetails> createState() => _PilotDetailsState();
}

class _PilotDetailsState extends State<PilotDetails>
    with WidgetsBindingObserver {
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  final reason = TextEditingController();
  String? stage, priority;
  bool publish = false;
  String? note;
  @override
  void dispose() {
    refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    reason.dispose();
    super.dispose();
  }

  Future<void> save(PilotCase c) async {
    if (reason.text.trim().length < 5) {
      setState(
        () => note = 'Explica la decisión o acción con al menos 5 caracteres.',
      );
      return;
    }
    final ok = await widget.store.update(
      widget.id,
      stage: stage ?? PilotStore.transitions[c.stage]!.first,
      priority: priority ?? c.priority,
      reason: reason.text,
      publish: publish,
    );
    if (!mounted) return;
    setState(() {
      note = ok
          ? 'Decisión guardada en la prueba local.'
          : 'No se pudo guardar la decisión. Revisa el estado e intenta nuevamente.';
      if (ok) {
        reason.clear();
        stage = null;
        publish = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final c = widget.store.cases.firstWhere(
        (c) => c.incident.id == widget.id,
      );
      final i = c.incident;
      final now = DateTime.now();
      // Re-evaluate public visibility on reads, including when returning from background.
      final visible = !widget.publicView || c.publicAt(now, historical: true);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.publicView
                ? 'Incidente revisado · Prueba'
                : c.help
                ? 'Solicitud de ayuda'
                : 'Detalle del reporte',
          ),
        ),
        body: !visible
            ? const Center(
                child: Text(
                  'Este incidente ya no está disponible públicamente.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${i.type} · ${i.place}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('Hora del hecho: ${pilotTime(i.createdAt)}'),
                  if (!widget.publicView)
                    Text('Recepción local: ${pilotTime(c.receivedAt)}'),
                  const SizedBox(height: 8),
                  Text(
                    c.activeAt(now)
                        ? 'Dentro de la vigencia de prueba (2 horas).'
                        : 'Fuera del mapa activo. La caducidad no confirma el fin del peligro.',
                  ),
                  if (!widget.publicView) ...[
                    Text('Estado: ${c.stage}'),
                    Text(
                      'Urgencia: ${c.priority} · independiente de la verificación',
                    ),
                    Text(
                      c.published
                          ? 'Revisado para publicación (prueba).'
                          : 'Pendiente de revisión para publicación.',
                    ),
                    if (i.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(i.description),
                      ),
                  ] else
                    const Text(
                      'Revisado por operador en una demostración local. No es una confirmación institucional.',
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: MapPanel(selected: LatLng(i.latitude, i.longitude)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${i.latitude.toStringAsFixed(6)}, ${i.longitude.toStringAsFixed(6)}',
                  ),
                  if (!widget.publicView) ...[
                    for (final photo in i.photos)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 180,
                          child: ReportPhotoView(photo: photo),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Seguimiento',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final event in c.events)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(event['text']!),
                        subtitle: Text(pilotTime(DateTime.parse(event['at']!))),
                      ),
                  ],
                  if (widget.operator && !widget.publicView && !c.terminal) ...[
                    const Divider(),
                    Text(
                      'Decisión del operador · Simulación',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('stage:${c.stage}'),
                      initialValue:
                          stage ?? PilotStore.transitions[c.stage]!.first,
                      decoration: const InputDecoration(
                        labelText: 'Siguiente estado',
                      ),
                      items: PilotStore.transitions[c.stage]!
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => setState(() {
                        stage = s;
                        if (s == 'Cerrada' || s == 'Descartada') {
                          publish = false;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: priority ?? c.priority,
                      decoration: const InputDecoration(
                        labelText: 'Urgencia revisada',
                      ),
                      items: ['Baja', 'Media', 'Alta']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => setState(() => priority = s),
                    ),
                    if (!c.published &&
                        !['Cerrada', 'Descartada'].contains(
                          stage ?? PilotStore.transitions[c.stage]!.first,
                        ))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: publish,
                        onChanged: (v) => setState(() => publish = v!),
                        title: const Text(
                          'Revisado: publicar ubicación y categoría',
                        ),
                        subtitle: const Text(
                          'No publica fotos, descripción ni seguimiento. Es independiente de la urgencia.',
                        ),
                      ),
                    TextField(
                      controller: reason,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Motivo o acción realizada (obligatorio)',
                      ),
                    ),
                    const Text(
                      'Registra solo lo realizado en esta simulación. No presupone que se enviaron agentes.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: widget.store.saving ? null : () => save(c),
                      child: const Text('Guardar decisión'),
                    ),
                  ],
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(note!),
                    ),
                ],
              ),
      );
    },
  );
}
