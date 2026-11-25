import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/workflow_client.dart';

typedef AiSimulationRequest =
    Future<dynamic> Function(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? query,
    });

typedef SimulationMapBuilder =
    Widget Function(Set<Marker> markers, LatLng center);

String simulationTime(dynamic value) =>
    DateTime.tryParse('$value')?.toLocal().toString() ?? '$value';

class AiSimulationPanel extends StatefulWidget {
  const AiSimulationPanel({super.key, this.request, this.mapBuilder});
  final AiSimulationRequest? request;
  final SimulationMapBuilder? mapBuilder;

  @override
  State<AiSimulationPanel> createState() => _AiSimulationPanelState();
}

class _AiSimulationPanelState extends State<AiSimulationPanel>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> cases = [];
  Map<String, dynamic>? config;
  bool busy = false, foreground = true;
  String? error;
  Timer? timer;

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => (widget.request ?? WorkflowClient.request)(
    method,
    path,
    body: body,
    query: query,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (!foreground) return;
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          TickerMode.valuesOf(context).enabled) {
        refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
    if (foreground && (ModalRoute.of(context)?.isCurrent ?? true)) refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        request('GET', '/operator/ai/simulation/config'),
        request('GET', '/operator/ai/simulation/cases'),
      ]);
      final next = (values[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          config = Map<String, dynamic>.from(values[0] as Map);
          cases = next;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          config = null;
          cases = [];
          error = e is StateError
              ? e.message.toString()
              : 'No se pudo consultar la simulación.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openCase(Map<String, dynamic> item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _SimulationCasePage(item: item, request: request),
      ),
    );
    if (mounted) await refresh();
  }

  Set<Marker> get markers => {
    for (final item in cases)
      Marker(
        markerId: MarkerId('simulation-${item['id']}'),
        position: LatLng(
          (item['latitude'] as num).toDouble(),
          (item['longitude'] as num).toDouble(),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          ['Cerrada', 'Descartada'].contains(item['stage'])
              ? BitmapDescriptor.hueAzure
              : BitmapDescriptor.hueViolet,
        ),
        infoWindow: InfoWindow(
          title: 'Simulación IA · Posible forcejeo',
          snippet: '${item['stage']}',
        ),
        onTap: () => openCase(item),
      ),
  };

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = cases.isEmpty
        ? const LatLng(-8.1116, -79.0288)
        : LatLng(
            (cases.first['latitude'] as num).toDouble(),
            (cases.first['longitude'] as num).toDouble(),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Simulación IA')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Cámara de prueba y atención de posibles forcejeos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Los casos de esta pantalla son de simulación. El mapa y la atención son para operadores.',
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: busy ? null : refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar simulación'),
              ),
              if (config?['enabled'] == true)
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _CreateSessionPage(
                                cameraId: '${config!['cameraId']}',
                                request: request,
                              ),
                            ),
                          );
                          if (mounted) await refresh();
                        },
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Preparar cámara de prueba'),
                ),
            ],
          ),
          if (config != null && config!['enabled'] != true)
            const Text(
              'La creación de sesiones de cámara está habilitada solo para la cuenta de prueba autorizada.',
            ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
          if (error == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 290,
              child:
                  widget.mapBuilder?.call(markers, center) ??
                  GoogleMap(
                    key: ValueKey('${center.latitude},${center.longitude}'),
                    initialCameraPosition: CameraPosition(
                      target: center,
                      zoom: 15,
                    ),
                    markers: markers,
                    myLocationButtonEnabled: false,
                    mapToolbarEnabled: false,
                  ),
            ),
            const SizedBox(height: 12),
            if (!busy && cases.isEmpty)
              const Text('Todavía no hay reportes de simulación.'),
            for (final item in cases)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Simulación IA · Posible forcejeo'),
                  subtitle: Text(
                    '${item['stage']} · Cámara ${item['cameraId']}\n${simulationTime(item['receivedAt'])}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCase(item),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CreateSessionPage extends StatefulWidget {
  const _CreateSessionPage({required this.cameraId, required this.request});
  final String cameraId;
  final AiSimulationRequest request;
  @override
  State<_CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<_CreateSessionPage> {
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  Map<String, dynamic>? session;
  bool tokenCopied = false, stopped = false;

  Future<void> stop() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.request(
        'POST',
        '/operator/ai/simulation/sessions/${session!['id']}/stop',
      );
      if (mounted) {
        setState(() {
          stopped = true;
          session!.remove('workerToken');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se pudo detener la sesión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final position = await LocationService().current();
      if (mounted) {
        setState(() {
          latitude.text = position.latitude.toStringAsFixed(6);
          longitude.text = position.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is LocationFailure
              ? e.message
              : 'No se pudo obtener la ubicación. Puedes escribir las coordenadas.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.request(
        'POST',
        '/operator/ai/simulation/sessions',
        body: {
          'cameraId': widget.cameraId,
          'latitude': double.parse(latitude.text.trim()),
          'longitude': double.parse(longitude.text.trim()),
        },
      );
      if (mounted) {
        setState(() => session = Map<String, dynamic>.from(result as Map));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se pudo crear la sesión de prueba.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? validate(String? value, double min, double max) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || !number.isFinite || number < min || number > max
        ? 'Escribe un valor entre $min y $max.'
        : null;
  }

  @override
  void dispose() {
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preparar cámara de prueba')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Cámara: ${widget.cameraId}'),
        const Text(
          'Fija la ubicación donde ocurrirá la simulación. Esa posición aparecerá en el mapa de operadores.',
        ),
        if (session == null)
          Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  controller: latitude,
                  decoration: const InputDecoration(
                    labelText: 'Latitud de la cámara',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => validate(value, -90, 90),
                ),
                TextFormField(
                  controller: longitude,
                  decoration: const InputDecoration(
                    labelText: 'Longitud de la cámara',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => validate(value, -180, 180),
                ),
                TextButton.icon(
                  onPressed: busy ? null : locate,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Usar ubicación de este celular'),
                ),
                FilledButton(
                  onPressed: busy ? null : create,
                  child: const Text('Crear sesión de simulación'),
                ),
              ],
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (session != null) ...[
          const SizedBox(height: 20),
          const Text(
            'Sesión creada. Comparte este identificador con la laptop que procesa el video.',
          ),
          SelectableText('${session!['id']}'),
          Text('Vence: ${simulationTime(session!['expiresAt'])}'),
          if (!stopped && !tokenCopied && session!['workerToken'] is String)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: session!['workerToken'] as String),
                );
                if (mounted) {
                  setState(() {
                    tokenCopied = true;
                    session!.remove('workerToken');
                  });
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar acceso temporal para la laptop'),
            ),
          if (tokenCopied)
            const Text(
              'Acceso temporal copiado. Pégalo en TRUJILLO_SIM_TOKEN en la laptop.',
            ),
          if (stopped) const Text('Sesión de cámara detenida.'),
          if (!stopped)
            TextButton(
              onPressed: busy ? null : stop,
              child: const Text('Detener sesión de cámara'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Conecta el celular por USB a la laptop y abre la dirección de cámara que muestre el servicio de visión. La laptop debe tener activo el modelo de IA.',
          ),
          const Text(
            'Crear la sesión no enciende la cámara. El navegador pedirá permiso cuando pulses Iniciar cámara.',
          ),
        ],
      ],
    ),
  );
}

class _SimulationCasePage extends StatefulWidget {
  const _SimulationCasePage({required this.item, required this.request});
  final Map<String, dynamic> item;
  final AiSimulationRequest request;
  @override
  State<_SimulationCasePage> createState() => _SimulationCasePageState();
}

class _SimulationCasePageState extends State<_SimulationCasePage> {
  late Map<String, dynamic> item = widget.item;
  bool busy = false;
  String? error;

  Future<void> decide(String stage) async {
    var reason = '';
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(stage),
        content: Form(
          key: form,
          child: TextFormField(
            onChanged: (value) => reason = value,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo o acción realizada',
            ),
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? 'Escribe al menos 5 caracteres.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar atención'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await widget.request(
        'POST',
        '/operator/ai/simulation/cases/${item['id']}/decisions',
        body: {'stage': stage, 'reason': reason.trim()},
      );
      if (mounted) {
        setState(() => item = Map<String, dynamic>.from(updated as Map));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se pudo guardar la atención. Actualiza el caso antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = item['stage'];
    final next = stage == 'Recibida'
        ? ['En revisión', 'Descartada']
        : ['En revisión', 'Acción registrada'].contains(stage)
        ? ['Acción registrada', 'Cerrada', 'Descartada']
        : <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Atender simulación IA')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Simulación IA · Posible forcejeo',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text('Estado: $stage'),
          Text('Cámara: ${item['cameraId']}'),
          Text('Ubicación: ${item['latitude']}, ${item['longitude']}'),
          Text(
            'Puntuación del modelo: ${((item['confidence'] as num) * 100).toStringAsFixed(1)}%',
          ),
          Text('Modelo: ${item['modelVersion']}'),
          const Text(
            'Revisa lo ocurrido antes de registrar la atención de este caso de prueba.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Wrap(
            spacing: 8,
            children: [
              for (final value in next)
                TextButton(
                  onPressed: busy ? null : () => decide(value),
                  child: Text(value),
                ),
            ],
          ),
          const Divider(),
          const Text('Historial de atención'),
          for (final event in (item['events'] as List? ?? []))
            ListTile(
              title: Text('${event['stage']}'),
              subtitle: Text(
                '${event['reason']}\n${simulationTime(event['at'])}',
              ),
            ),
        ],
      ),
    );
  }
}
