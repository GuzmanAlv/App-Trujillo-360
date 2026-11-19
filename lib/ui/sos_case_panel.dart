import 'citizen_sos_page.dart';
import 'report_marker.dart';
import 'sos_status.dart';
import 'audio_call_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/workflow_client.dart';
import '../services/report_sender.dart';
import '../services/location_service.dart';
import 'map_panel.dart';

String attentionLabel(String value) => switch (value) {
  'en_route' => 'Unidad en camino',
  'on_scene' => 'Personal en el lugar',
  'resolved' => 'Caso resuelto',
  _ => 'Sin despliegue confirmado',
};

String caseActionLabel(String action) => switch (action) {
  'save' => 'Ficha guardada',
  'pending' => 'Pendiente por información insuficiente',
  'confirm' => 'Incidente confirmado',
  'discard' => 'Alarma descartada',
  'en_route' => 'Unidad en camino',
  'on_scene' => 'Personal en el lugar',
  'resolve' => 'Atención resuelta',
  _ => action,
};
String caseTime(dynamic value) =>
    DateTime.tryParse('$value')?.toLocal().toString().split('.').first ??
    '$value';

class SosCasePage extends StatelessWidget {
  const SosCasePage({super.key, required this.caseId});
  final String caseId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Evaluación del SOS')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SosCasePanel(caseId: caseId),
    ),
  );
}

/// Kept mounted when audio ends, so the operator does not lose their evaluation.
typedef CaseRequest =
    Future<dynamic> Function(
      String method,
      String path, {
      Map<String, dynamic>? body,
    });

class SosCasePanel extends StatefulWidget {
  const SosCasePanel({
    super.key,
    required this.caseId,
    this.guardNavigation = true,
    this.request,
    this.showCallButton = true,
  });
  final String caseId;
  final bool showCallButton;
  final bool guardNavigation;
  final CaseRequest? request;
  @override
  State<SosCasePanel> createState() => SosCasePanelState();
}

class SosCasePanelState extends State<SosCasePanel> {
  Map<String, dynamic>? data;
  final place = TextEditingController(), publicText = TextEditingController();
  final internal = TextEditingController(), outcome = TextEditingController();
  final latitude = TextEditingController(), longitude = TextEditingController();
  String category = 'Auxilio';
  LatLng? operatorPoint, focusPoint;
  bool locating = false;
  BitmapDescriptor? citizenIcon, operatorIcon;
  Future<void> prepareActors() async {
    final citizen = await renderActorMarker(Icons.person, Colors.red.shade700);
    final police = await renderActorMarker(
      Icons.local_police,
      Colors.blue.shade700,
    );
    if (mounted) {
      setState(() {
        citizenIcon = BitmapDescriptor.bytes(
          citizen,
          imagePixelRatio: 2,
          width: 48,
          height: 56,
        );
        operatorIcon = BitmapDescriptor.bytes(
          police,
          imagePixelRatio: 2,
          width: 48,
          height: 56,
        );
      });
    }
  }

  Future<void> locateOperator() async {
    setState(() => locating = true);
    try {
      final gps = await LocationService().current();
      if (mounted) {
        setState(() {
          operatorPoint = LatLng(gps.latitude, gps.longitude);
          focusPoint = operatorPoint;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo obtener tu ubicación. Revisa los permisos.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  String? error, notice;
  bool busy = false, stale = false, dirty = false;
  Map<String, dynamic>? retryBody;
  StreamSubscription<User?>? session;
  bool allowLeave = false;
  Future<bool> mayLeave() async {
    if (busy) return false;
    return !dirty || await confirm('¿Salir sin guardar la evaluación?');
  }

  Future<void> leaveIfAllowed() async {
    if (!await mayLeave() || !mounted) return;
    setState(() => allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) => (widget.request ?? WorkflowClient.request)(method, path, body: body);
  String get path => '/operator/sos-cases/${widget.caseId}';
  bool get editable =>
      !stale &&
      !busy &&
      data?['can_edit'] == true &&
      data?['decision'] != 'discarded' &&
      data?['attention'] != 'resolved';
  LatLng? get point {
    final lat = double.tryParse(latitude.text),
        lng = double.tryParse(longitude.text);
    return lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat.abs() <= 90 &&
            lng.abs() <= 180
        ? LatLng(lat, lng)
        : null;
  }

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      session = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u?.uid != uid && mounted) {
          setState(() {
            stale = true;
            data = null;
          });
        }
      });
    }
    unawaited(load());
    unawaited(prepareActors());
  }

  void apply(Map<String, dynamic> result) {
    data = result;
    category = result['category'] as String;
    place.text = result['place'] as String;
    publicText.text = result['public_description'] as String;
    internal.text = result['internal_note'] as String;
    outcome.text = result['outcome'] as String;
    latitude.text = '${result['latitude']}';
    longitude.text = '${result['longitude']}';
    dirty = false;
    retryBody = null;
  }

  Future<void> load() async {
    if (stale || busy) return;
    if (dirty &&
        !await confirm('¿Recargar y descartar los cambios sin guardar?')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await request('GET', path) as Map,
      );
      if (mounted && !stale) setState(() => apply(result));
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String readable(Object e) => e is StateError
      ? e.message.toString()
      : 'No se confirmó el cambio. Puedes reintentar.';
  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  void changed([String? _]) {
    setState(() {
      dirty = true;
      notice = null;
    });
  }

  Future<void> save(String action) async {
    if (!editable) return;
    final selected = point;
    if (selected == null) {
      setState(() => error = 'Revisa las coordenadas del hecho.');
      return;
    }
    if (['pending', 'discard'].contains(action) &&
        internal.text.trim().length < 5) {
      setState(() => error = 'Explica el motivo en el comentario interno.');
      return;
    }
    if (action == 'resolve' && outcome.text.trim().length < 5) {
      setState(() => error = 'Registra el resultado de la atención.');
      return;
    }
    final question = switch (action) {
      'confirm' => '¿Confirmar y publicar este incidente en el mapa?',
      'discard' =>
        '¿Descartar esta alarma? La llamada sin respuesta no demuestra que sea falsa.',
      'on_scene' =>
        '¿Confirmas que el personal ya está en el lugar del incidente?',
      'resolve' =>
        '¿Cerrar la atención? Se quitará la presencia activa del mapa.',
      _ => null,
    };
    if (question != null && !await confirm(question)) return;
    if (!mounted || !editable) return;
    final body = <String, dynamic>{
      'request_id': ReportSender.requestId(),
      'version': data!['version'],
      'action': action,
      'category': category,
      'latitude': selected.latitude,
      'longitude': selected.longitude,
      'place': place.text.trim(),
      'public_description': publicText.text.trim(),
      'internal_note': internal.text.trim(),
      'outcome': outcome.text.trim(),
    };
    // Freeze a request on first send. Network retries reuse it, including arrival GPS.
    retryBody = body;
    setState(() => busy = true);
    if (action == 'on_scene') {
      try {
        final gps = await LocationService().current();
        body['arrival_position'] = {
          'latitude': gps.latitude,
          'longitude': gps.longitude,
          'accuracy': gps.accuracy,
        };
      } catch (_) {
        /* Arrival is an explicit authorized declaration, GPS is optional evidence. */
      }
    }
    if (!mounted || stale) return;
    await send(body);
  }

  Future<void> send(Map<String, dynamic> body) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await request('POST', path, body: body) as Map,
      );
      if (mounted && !stale) {
        setState(() {
          apply(result);
          notice = 'Evaluación guardada.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController control,
    String label,
    int max, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: control,
      enabled: editable,
      onChanged: changed,
      maxLength: max,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  void dispose() {
    session?.cancel();
    for (final c in [
      place,
      publicText,
      internal,
      outcome,
      latitude,
      longitude,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (stale) return const Text('La sesión cambió. Vuelve a abrir el caso.');
    final d = data;
    if (d == null) {
      return Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('Cargar evaluación'),
          ),
        ],
      );
    }
    final confirmed = d['decision'] == 'confirmed';
    return PopScope(
      canPop: !widget.guardNavigation || allowLeave || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.guardNavigation) unawaited(leaveIfAllowed());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Caso SOS',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Flexible(child: SosStatusBadge(data: d)),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.showCallButton &&
              !['resolved'].contains(d['attention']) &&
              d['decision'] != 'discarded')
            OutlinedButton.icon(
              icon: const Icon(Icons.call),
              label: Text(
                ['ended', 'unanswered'].contains(d['call_state'])
                    ? 'Llamar al usuario'
                    : 'Tomar / abrir llamada',
              ),
              onPressed: busy || d['can_edit'] != true
                  ? null
                  : () async {
                      if (!await mayLeave()) return;
                      if (!context.mounted) return;
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => AudioCallPage(
                            callId: widget.caseId,
                            operator: true,
                            callback:
                                [
                                  'ended',
                                  'unanswered',
                                ].contains(d['call_state']) ||
                                d['call_direction'] == 'operator',
                          ),
                        ),
                      );
                      if (mounted) {
                        dirty = false;
                        await load();
                      }
                    },
            ),
          SizedBox(
            height: 300,
            child: MapPanel(
              zoomControls: true,
              selected: point,
              focusTarget: focusPoint,
              extraMarkers: {
                Marker(
                  markerId: const MarkerId('citizen_sos'),
                  position: LatLng(
                    (d['caller_latitude'] as num).toDouble(),
                    (d['caller_longitude'] as num).toDouble(),
                  ),
                  icon:
                      citizenIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed,
                      ),
                  infoWindow: const InfoWindow(title: 'Ciudadano · SOS'),
                ),
                if (operatorPoint != null)
                  Marker(
                    markerId: const MarkerId('operator_sos'),
                    position: operatorPoint!,
                    icon:
                        operatorIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                    infoWindow: const InfoWindow(
                      title: 'Operador · mi ubicación',
                    ),
                  ),
              },
              onPick: editable
                  ? (p) {
                      setState(() {
                        latitude.text = '${p.latitude}';
                        longitude.text = '${p.longitude}';
                        dirty = true;
                      });
                    }
                  : null,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: locating ? null : locateOperator,
                icon: const Icon(Icons.local_police, color: Colors.blue),
                label: const Text('Mi ubicación'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => focusPoint = LatLng(
                    (d['caller_latitude'] as num).toDouble(),
                    (d['caller_longitude'] as num).toDouble(),
                  ),
                ),
                icon: const Icon(Icons.person_pin_circle, color: Colors.red),
                label: const Text('Ciudadano SOS'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            key: ValueKey(category),
            decoration: const InputDecoration(labelText: 'Tipo de incidente'),
            items: [
              for (final v in ['Robo', 'Auxilio', 'Agresión', 'Riesgo'])
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: editable
                ? (v) {
                    setState(() {
                      category = v!;
                      dirty = true;
                    });
                  }
                : null,
          ),
          field(place, 'Referencia del lugar (opcional)', 100),
          field(publicText, 'Descripción pública (opcional)', 500, lines: 3),
          field(
            internal,
            'Comentario interno · solo operadores',
            2000,
            lines: 3,
          ),
          if (confirmed)
            field(
              outcome,
              'Resultado de la atención · interno',
              1000,
              lines: 2,
            ),
          if (dirty) const Text('Hay cambios pendientes de confirmar.'),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (notice != null) Text(notice!),
          if (retryBody != null && error != null)
            TextButton(
              onPressed: busy ? null : () => send(retryBody!),
              child: const Text('Reintentar el mismo envío'),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!confirmed && d['decision'] != 'discarded') ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff52766b),
                  ),
                  onPressed: editable ? () => save('confirm') : null,
                  child: const Text('Confirmar incidente'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: editable ? () => save('discard') : null,
                  child: const Text('Descartar alarma'),
                ),
              ],
              if (editable)
                OutlinedButton.icon(
                  onPressed: () => save(
                    d['support_requested'] == true
                        ? 'support_clear'
                        : 'support',
                  ),
                  icon: const Icon(Icons.campaign, color: Colors.red),
                  label: Text(
                    d['support_requested'] == true
                        ? 'Apoyo atendido'
                        : 'Solicitar más patrullas',
                  ),
                ),
              if (confirmed && d['attention'] != 'resolved') ...[
                if (d['attention'] == 'none')
                  FilledButton(
                    onPressed: editable ? () => save('en_route') : null,
                    child: const Text('Unidad en camino'),
                  ),
                if (d['attention'] != 'on_scene')
                  FilledButton.icon(
                    onPressed: editable ? () => save('on_scene') : null,
                    icon: const Icon(Icons.location_on),
                    label: const Text('Personal en el lugar'),
                  ),
                OutlinedButton(
                  onPressed: editable ? () => save('resolve') : null,
                  child: const Text('Resolver caso'),
                ),
              ],
              TextButton(
                onPressed: busy ? null : load,
                child: const Text('Recargar ficha'),
              ),
            ],
          ),
          SosEvidencePanel(caseId: widget.caseId),
          ExpansionTile(
            title: const Text('Historial privado del caso'),
            children: [
              for (final event in d['events'] as List? ?? [])
                ListTile(
                  title: Text(
                    '${caseActionLabel('${event['action']}')} · ${caseTime(event['at'])}',
                  ),
                  subtitle: Text(
                    '${event['snapshot']['internal_note']}\n${event['snapshot']['outcome']}\n${event['arrival_position'] == null ? '' : 'Llegada con ubicación del dispositivo registrada'}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
