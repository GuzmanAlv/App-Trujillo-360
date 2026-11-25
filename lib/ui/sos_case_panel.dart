import '../services/sos_navigation.dart';
import 'sos_incoming_attention.dart';
import '../services/operator_duty.dart';
import '../services/active_call.dart';
import '../services/sos_alert_state.dart';
import 'citizen_sos_page.dart';
import 'report_marker.dart';
import 'sos_status.dart';
import 'sos_discard_dialog.dart';
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
  'on_scene' => 'Unidad en la zona',
  'resolved' => 'Caso resuelto',
  _ => 'Sin despliegue confirmado',
};

String caseActionLabel(String action) => switch (action) {
  'save' => 'Ficha guardada',
  'pending' => 'Pendiente por información insuficiente',
  'confirm' => 'Incidente confirmado',
  'discard' => 'Alarma descartada',
  'discard_block' => 'SOS descartado y cuenta suspendida',
  'en_route' => 'Unidad en camino',
  'on_scene' => 'Unidad en la zona',
  'resolve' => 'Atención resuelta',
  _ => action,
};
String caseTime(dynamic value) =>
    DateTime.tryParse('$value')?.toLocal().toString().split('.').first ??
    '$value';

class SosCasePage extends StatefulWidget {
  const SosCasePage({super.key, required this.caseId});
  final String caseId;
  @override
  State<SosCasePage> createState() => _SosCasePageState();
}

class _SosCasePageState extends State<SosCasePage> {
  final incoming = ValueNotifier(false);
  @override
  void dispose() {
    incoming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Evaluación del SOS')),
    body: ValueListenableBuilder<bool>(
      valueListenable: incoming,
      builder: (_, active, _) => SosIncomingAttention(
        active: active,
        enableSound: false,
        glowExtent: 28,
        intensity: .5,
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 24),
          child: SosCasePanel(
            caseId: widget.caseId,
            onAlertChanged: (value) {
              if (mounted) incoming.value = value;
            },
          ),
        ),
      ),
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
    this.onConfirmed,
    this.onAlertChanged,
  });
  final String caseId;
  final ValueChanged<bool>? onAlertChanged;
  final FutureOr<void> Function(Map<String, dynamic>)? onConfirmed;
  final bool showCallButton;
  final bool guardNavigation;
  final CaseRequest? request;
  @override
  State<SosCasePanel> createState() => SosCasePanelState();
}

class SosCasePanelState extends State<SosCasePanel>
    with WidgetsBindingObserver {
  bool foreground = true;
  Timer? callPoll;
  Timer? positionPoll;
  bool pollingPosition = false;
  Future<void> refreshPosition() async {
    if (!mounted ||
        !foreground ||
        stale ||
        pollingPosition ||
        data?['can_track'] != true ||
        data?['decision'] != 'confirmed' ||
        data?['attention'] == 'resolved') {
      return;
    }
    pollingPosition = true;
    try {
      final result = await request('GET', '$path/navigation-target');
      if (mounted && !stale && data != null) {
        setState(() => data!['live_position'] = result);
      }
    } catch (_) {
      // Keep unsaved evaluation fields and the last known position.
    } finally {
      pollingPosition = false;
    }
  }

  bool pollingCall = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
  }

  Timer? leasePoll;
  bool renewingLease = false;
  Future<void> refreshLease() async {
    if (!mounted ||
        stale ||
        !foreground ||
        renewingLease ||
        widget.request != null ||
        data?['decision'] != 'pending' ||
        data?['can_edit'] != true) {
      return;
    }
    renewingLease = true;
    try {
      final lease = await WorkflowClient.request(
        'POST',
        '$path/heartbeat',
        timeout: const Duration(seconds: 8),
      );
      if (mounted &&
          !stale &&
          data?['decision'] == 'pending' &&
          lease['owned'] != true) {
        setState(() {
          stale = true;
          error = 'La reserva venció. Vuelve al mapa para aceptar el SOS.';
        });
      }
    } catch (_) {
      // The stored lease expires if connectivity cannot be recovered.
    } finally {
      renewingLease = false;
    }
  }

  Future<void> refreshCall() async {
    if (!mounted ||
        stale ||
        !foreground ||
        !widget.showCallButton ||
        pollingCall ||
        widget.request != null) {
      return;
    }
    pollingCall = true;
    try {
      final state = await request('GET', '/calls/${widget.caseId}');
      if (mounted && !stale && data != null) {
        setState(() => data!['call_state'] = state['state']);
      }
    } catch (_) {
      /* Case fetch exposes errors; do not replace unsaved evaluation. */
    } finally {
      pollingCall = false;
    }
  }

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
    OperatorDuty.cases.addListener(dutyChanged);
    if (widget.request == null) {
      positionPoll = Timer.periodic(
        const Duration(seconds: 12),
        (_) => refreshPosition(),
      );
      leasePoll = Timer.periodic(
        const Duration(seconds: 30),
        (_) => refreshLease(),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    if (widget.request == null && widget.showCallButton) {
      callPoll = Timer.periodic(
        const Duration(seconds: 4),
        (_) => refreshCall(),
      );
    }
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

  bool? lastAlert;
  void dutyChanged() {
    if (mounted) setState(() {});
  }

  void reportAlert(bool alert) {
    if (lastAlert == alert) return;
    lastAlert = alert;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAlertChanged?.call(alert);
    });
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
          title: const Text(
            'Evaluación SOS',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
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
    if (action == 'discard') {
      final choice = await showDialog<SosDiscardDecision>(
        context: context,
        builder: (_) => const SosDiscardDialog(),
      );
      if (!mounted || choice == null || !editable) return;
      action = choice.action;
      internal.text = choice.reason;
    }
    final selected = point;
    if (selected == null) {
      setState(() => error = 'Revisa las coordenadas del hecho.');
      return;
    }
    if (['pending', 'discard', 'discard_block'].contains(action) &&
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
    Map<String, dynamic>? confirmed;
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
          SosNavigation.caseUpdated(result);
          final uid = Firebase.apps.isEmpty
              ? null
              : FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) OperatorDuty.upsert(uid, result);
          notice = 'Evaluación guardada.';
          if (body['action'] == 'confirm' &&
              result['decision'] == 'confirmed') {
            confirmed = result;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && !stale && data?['decision'] == 'discarded') {
      final call = ActiveCall.session.value;
      if (call != null && call.callId == widget.caseId && !call.finished) {
        unawaited(call.finish());
      }
    }
    if (confirmed != null && mounted && !stale) {
      if (widget.onConfirmed != null) {
        await widget.onConfirmed!(confirmed!);
      } else if (widget.request == null) {
        setState(() => allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          SosNavigation.open(widget.caseId);
        });
      }
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
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffdce3df)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffdce3df)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffa52b36), width: 1.5),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    OperatorDuty.cases.removeListener(dutyChanged);
    WidgetsBinding.instance.removeObserver(this);
    callPoll?.cancel();
    leasePoll?.cancel();
    positionPoll?.cancel();
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
      child: ValueListenableBuilder<String?>(
        valueListenable: ActiveCall.id,
        builder: (context, active, _) {
          final alarming =
              !OperatorDuty.engaged &&
              widget.request == null &&
              widget.showCallButton &&
              active == null &&
              needsOperatorSosAlert(d) &&
              foreground &&
              (ModalRoute.isCurrentOf(context) ?? true);
          reportAlert(alarming);
          return SosIncomingAttention(
            active: alarming,
            enableGlow: false,
            builder: (muted, toggle) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showCallButton &&
                    !['resolved'].contains(d['attention']) &&
                    d['decision'] != 'discarded')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: SosSupportFrame(
                      pulse: true,
                      soft: true,
                      margin: EdgeInsets.zero,
                      active:
                          widget.request == null &&
                          needsOperatorSosAlert(d) &&
                          foreground &&
                          (ModalRoute.isCurrentOf(context) ?? true),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              ['ended', 'unanswered'].contains(d['call_state'])
                              ? const Color(0xff16834a)
                              : const Color(0xffce2333),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: Icon(
                          ['ended', 'unanswered'].contains(d['call_state'])
                              ? Icons.call_rounded
                              : Icons.call,
                        ),
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
                                setState(() => dirty = false);
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
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Caso SOS',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7,
                              color: const Color(0xff202a28),
                            ),
                      ),
                    ),
                    Flexible(child: SosStatusBadge(data: d)),
                  ],
                ),
                const SizedBox(height: 12),
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
                          (d['live_position']?['latitude'] ??
                                  d['caller_latitude'] as num)
                              .toDouble(),
                          (d['live_position']?['longitude'] ??
                                  d['caller_longitude'] as num)
                              .toDouble(),
                        ),
                        icon:
                            citizenIcon ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed,
                            ),
                        infoWindow: InfoWindow(
                          title: 'Ciudadano · SOS',
                          snippet: d['live_position']?['stale'] == true
                              ? 'Última posición conocida · esperando GPS'
                              : d['live_position']?['live'] == true
                              ? 'Posición actual del dispositivo'
                              : 'Ubicación registrada del SOS',
                        ),
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
                    if (confirmed && editable)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Transferir a otra unidad'),
                        onPressed: () async {
                          if (!await confirm(
                            '¿Transferir el SOS? Se cerrará el audio y se buscará otro operador disponible, sin cerrar el caso.',
                          )) {
                            return;
                          }
                          final call = ActiveCall.session.value;
                          if (call?.callId == widget.caseId) {
                            await call!.finish();
                          }
                          try {
                            await request('POST', '$path/handoff');
                            final uid = Firebase.apps.isEmpty
                                ? null
                                : FirebaseAuth.instance.currentUser?.uid;
                            if (uid != null) {
                              OperatorDuty.replace(
                                uid,
                                OperatorDuty.cases.value
                                    .where((r) => r['id'] != widget.caseId)
                                    .toList(),
                              );
                            }
                            if (mounted) {
                              dirty = false;
                              await load();
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => error =
                                    'No se pudo transferir el caso. Comprueba la conexión y reintenta.',
                              );
                            }
                          }
                        },
                      ),
                    OutlinedButton.icon(
                      onPressed: () => setState(
                        () => focusPoint = LatLng(
                          (d['live_position']?['latitude'] ??
                                  d['caller_latitude'] as num)
                              .toDouble(),
                          (d['live_position']?['longitude'] ??
                                  d['caller_longitude'] as num)
                              .toDouble(),
                        ),
                      ),
                      icon: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.red,
                      ),
                      label: const Text('Ciudadano SOS'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  key: ValueKey(category),
                  decoration: InputDecoration(
                    labelText: 'Tipo de incidente',
                    prefixIcon: const Icon(Icons.category_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xffdce3df)),
                    ),
                  ),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                      TextButton(
                        onPressed: !editable
                            ? null
                            : () async {
                                if (!await confirm(
                                  '¿Liberar el SOS para que otro operador pueda atenderlo?',
                                )) {
                                  return;
                                }
                                if (!mounted) return;
                                setState(() => busy = true);
                                try {
                                  await request('POST', '$path/release');
                                  final call = ActiveCall.session.value;
                                  if (call?.callId == widget.caseId &&
                                      !call!.finished) {
                                    await call.finish();
                                  }
                                  if (context.mounted) {
                                    Navigator.of(context).maybePop();
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = readable(e));
                                  }
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              },
                        child: const Text('Liberar SOS para otro operador'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffc12635),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(160, 50),
                        ),
                        onPressed: editable ? () => save('confirm') : null,
                        child: const Text('Confirmar SOS'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff687078),
                          minimumSize: const Size(150, 50),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: editable ? () => save('discard') : null,
                        child: const Text('Descartar alarma'),
                      ),
                    ],
                    if (confirmed && d['attention'] != 'resolved') ...[
                      FilledButton.tonal(
                        onPressed: editable ? () => save('discard') : null,
                        child: const Text('Descartar SOS'),
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
                    for (final transfer in d['transfers'] as List? ?? [])
                      ListTile(
                        leading: const Icon(Icons.swap_horiz),
                        title: Text(
                          '${transfer['reason'] == 'assignment_accepted'
                              ? 'Transferencia aceptada'
                              : transfer['reason'] == 'operator_offer'
                              ? 'Oferta a otra unidad'
                              : 'Reasignación por indisponibilidad'} · ${caseTime(transfer['created_at'])}',
                        ),
                        subtitle: const Text(
                          'El SOS y sus evidencias se conservan.',
                        ),
                      ),
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
        },
      ),
    );
  }
}
