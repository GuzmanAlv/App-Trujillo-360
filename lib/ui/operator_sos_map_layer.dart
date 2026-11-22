import '../services/sos_alert_state.dart';
import '../services/operator_duty.dart';
import '../services/reinforcements_store.dart';
import 'reinforcement_controls.dart';
import 'sos_waiting_queue.dart';
import 'sos_incoming_attention.dart';
import 'sos_progress_feedback.dart';
import '../services/active_call.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/workflow_client.dart';
import 'report_marker.dart';
import 'report_style.dart';
import 'sos_case_panel.dart';
import 'sos_status.dart';

typedef SosMapFocus = ({LatLng target, int revision});

class OperatorSosMapLayer extends StatefulWidget {
  const OperatorSosMapLayer({
    super.key,
    required this.enabled,
    required this.active,
    required this.builder,
    required this.reinforcements,
    required this.onReinforcement,
  });
  final bool enabled, active;
  final ReinforcementsStore reinforcements;
  final void Function(Map<String, dynamic>, bool) onReinforcement;
  final Widget Function(Set<Marker>, Set<String>, SosMapFocus?) builder;
  @override
  State<OperatorSosMapLayer> createState() => _OperatorSosMapLayerState();
}

class _OperatorSosMapLayerState extends State<OperatorSosMapLayer> {
  Timer? timer, pulseTimer;
  int pulseFrame = 0;
  int lastBackupFocus = 0;
  final patrolIcons = <BitmapDescriptor>[];
  void backupsChanged() {
    if (!mounted) return;
    final store = widget.reinforcements;
    setState(() {
      if (store.focus != null && store.focusRevision != lastBackupFocus) {
        lastBackupFocus = store.focusRevision;
        focus = (
          target: LatLng(
            (store.focus!['latitude'] as num).toDouble(),
            (store.focus!['longitude'] as num).toDouble(),
          ),
          revision: ++focusRevision,
        );
      }
    });
    configurePulse();
  }

  Set<Marker> backupMarkers() => widget.reinforcements.rows
      .map(
        (row) => Marker(
          markerId: MarkerId('reinforcement_${row['id']}'),
          position: LatLng(
            (row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          ),
          icon: patrolIcons.length == 6
              ? patrolIcons[pulseFrame % 6]
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
          anchor: const Offset(.5, 74 / 76),
          zIndexInt: 3,
          infoWindow: InfoWindow(
            title: row['is_mine'] == true
                ? 'Tu solicitud de refuerzos'
                : 'Patrulla solicita refuerzos',
            snippet: '${row['name'] ?? ''}',
          ),
          onTap: () {
            if (row['is_mine'] == true) {
              unawaited(closeOwnReinforcement());
            } else {
              widget.onReinforcement(row, true);
            }
          },
        ),
      )
      .toSet();
  Future<void> closeOwnReinforcement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Solicitud de refuerzos',
          style: TextStyle(fontSize: 17),
        ),
        content: const Text(
          '¿Ya no necesitas apoyo? Puedes finalizar la solicitud activa.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Finalizar solicitud'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.reinforcements.closeMine();
  }

  final List<BitmapDescriptor> pendingIcons = [], phoneIcons = [];
  final categoryIcons = <String, List<BitmapDescriptor>>{};
  Map<String, String> categoryIds = {};
  Set<String> phoneIds = {}, urgentIds = {};
  int alertCount = 0;
  Map<String, bool> queueStates = {};
  Map<String, int> queueMinutes = {};
  String? accepting;
  Position? lastPosition;
  DateTime? positionAt;
  List<String> get queueIds => [
    ...queueStates.keys.where((id) => queueStates[id] == true),
    ...queueStates.keys.where((id) => queueStates[id] != true),
  ];
  SosMapFocus? focus;
  int focusRevision = 0;
  void focusCaller(String id) {
    if (!widget.enabled || !queueStates.containsKey(id)) return;
    final matching = baseMarkers.where((m) => m.markerId.value == id);
    if (matching.isEmpty) return;
    setState(
      () =>
          focus = (target: matching.first.position, revision: ++focusRevision),
    );
  }

  Set<Marker> baseMarkers = {};
  Set<String> pendingIds = {};
  Future<void> preparePendingIcons() async {
    for (final phase in [0.0, .35, .75, 1.0, .75, .35]) {
      final bytes = await renderPendingSosMarker(phase);
      final phoneBytes = await renderPendingSosMarker(phase, waitingCall: true);
      final patrolBytes = await renderPendingSosMarker(
        phase,
        patrol: true,
        color: ReinforcementControls.orange,
      );
      if (!mounted) return;
      phoneIcons.add(
        BitmapDescriptor.bytes(
          phoneBytes,
          imagePixelRatio: 2,
          width: 64,
          height: 76,
        ),
      );
      patrolIcons.add(
        BitmapDescriptor.bytes(
          patrolBytes,
          imagePixelRatio: 2,
          width: 64,
          height: 76,
        ),
      );
      pendingIcons.add(
        BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: 2,
          width: 64,
          height: 76,
        ),
      );
    }
    if (mounted) {
      setState(() {});
      configurePulse();
    }
  }

  void configurePulse() {
    pulseTimer?.cancel();
    pulseTimer = null;
    if (!widget.enabled ||
        !widget.active ||
        (urgentIds.isEmpty &&
            categoryIds.isEmpty &&
            widget.reinforcements.rows.isEmpty) ||
        pendingIcons.length != 6 ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    pulseTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (mounted) {
        setState(() => pulseFrame = (pulseFrame + 1) % pendingIcons.length);
      }
    });
  }

  Set<Marker> displayedMarkers() => baseMarkers
      .map(
        (m) => pendingIds.contains(m.markerId.value) && pendingIcons.isNotEmpty
            ? m.copyWith(
                iconParam:
                    (phoneIds.contains(m.markerId.value)
                    ? phoneIcons
                    : pendingIcons)[urgentIds.contains(m.markerId.value)
                        ? pulseFrame % pendingIcons.length
                        : 0],
                anchorParam: const Offset(.5, 74 / 76),
              )
            : categoryIds.containsKey(m.markerId.value)
            ? m.copyWith(
                iconParam:
                    categoryIcons[categoryIds[m.markerId.value]]?[pulseFrame %
                        6],
                anchorParam: const Offset(.5, 74 / 76),
              )
            : m,
      )
      .toSet();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configurePulse();
  }

  StreamSubscription<User?>? session;
  Set<Marker> markers = {};
  Set<String> incidentIds = {};
  final icons = <String, BitmapDescriptor>{};
  int generation = 0;
  bool busy = false;
  String? note;
  @override
  void initState() {
    super.initState();
    widget.reinforcements.addListener(backupsChanged);
    if (Firebase.apps.isNotEmpty) {
      session = FirebaseAuth.instance.authStateChanges().listen((_) {
        clear();
        unawaited(refresh());
      });
    }
    timer = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
    unawaited(refresh());
    unawaited(preparePendingIcons());
  }

  void clear() {
    generation++;
    busy = false;
    if (mounted) {
      setState(() {
        markers = {};
        baseMarkers = {};
        pendingIds = {};
        categoryIds = {};
        phoneIds = {};
        urgentIds = {};
        alertCount = 0;
        queueStates = {};
        queueMinutes = {};
        accepting = null;
        focus = null;
        pulseTimer?.cancel();
        incidentIds = {};
        note = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant OperatorSosMapLayer old) {
    super.didUpdateWidget(old);
    configurePulse();
    if (!widget.enabled) {
      clear();
    } else if (!old.enabled || (!old.active && widget.active)) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!mounted ||
        busy ||
        !widget.enabled ||
        !widget.active ||
        Firebase.apps.isEmpty) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ticket = ++generation;
    busy = true;
    try {
      if (positionAt == null || DateTime.now().difference(positionAt!) > const Duration(seconds: 30)) {
        positionAt = DateTime.now();
        try {
          if (await Geolocator.isLocationServiceEnabled() &&
              await Geolocator.checkPermission() != LocationPermission.denied &&
              await Geolocator.checkPermission() != LocationPermission.deniedForever) {
            lastPosition = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(timeLimit: Duration(seconds: 5)));
          }
        } catch (_) { lastPosition = null; }
      }
      final rows = await WorkflowClient.list('/operator/sos-map');
      final next = <Marker>{},
          ids = <String>{},
          pending = <String>{},
          phones = <String>{},
          urgent = <String>{};
      var alerts = 0;
      final nextQueue = <String, bool>{};
      final nextMinutes = <String, int>{};
      final categories = <String, String>{};
      for (final row in rows) {
        final style = sosStyle(row);
        final key = style.label;
        if (!icons.containsKey(key)) {
          final bytes = await renderActorMarker(style.icon, style.color);
          icons[key] = BitmapDescriptor.bytes(
            bytes,
            imagePixelRatio: 2,
            width: 48,
            height: 56,
          );
        }
        if (!mounted ||
            ticket != generation ||
            !widget.enabled ||
            FirebaseAuth.instance.currentUser?.uid != uid) {
          return;
        }
        final lat = (row['latitude'] as num).toDouble(),
            lng = (row['longitude'] as num).toDouble();
        if (!lat.isFinite ||
            !lng.isFinite ||
            lat.abs() > 90 ||
            lng.abs() > 180) {
          continue;
        }
        if (row['incident_id'] is String) ids.add(row['incident_id'] as String);
        final markerId = 'operator_sos_${row['id']}';
        if (row['decision'] == 'confirmed' &&
            !['on_scene', 'resolved'].contains(row['attention'])) {
          final category = '${row['category']}';
          if (!categoryIcons.containsKey(category)) {
            final frames = <BitmapDescriptor>[];
            final categoryStyle = ReportStyle.forCategory(category);
            for (final phase in [0.0, .35, .75, 1.0, .75, .35]) {
              final bytes = await renderPendingSosMarker(
                phase,
                symbol: categoryStyle.icon,
                color: categoryStyle.color,
              );
              if (!mounted || ticket != generation) return;
              frames.add(
                BitmapDescriptor.bytes(
                  bytes,
                  imagePixelRatio: 2,
                  width: 64,
                  height: 76,
                ),
              );
            }
            categoryIcons[category] = frames;
          }
          categories[markerId] = category;
        }
        final waiting = row['call_waiting'] == true;
        if (row['available'] == true) {
          nextQueue[markerId] = waiting;
          if (lastPosition != null) {
            final meters = Geolocator.distanceBetween(lastPosition!.latitude,
              lastPosition!.longitude, lat, lng);
            // Road travel estimate; actual route is shown after confirmation.
            nextMinutes[markerId] = math.max(1, (meters * 1.35 / 350).ceil());
          }
        }
        final needsAttention = needsOperatorSosAlert(row);
        if (needsAttention) {
          alerts++;
          urgent.add(markerId);
        }
        if (waiting) phones.add(markerId);
        if (waiting ||
            (row['decision'] == 'pending' &&
                row['support_requested'] != true)) {
          pending.add(markerId);
        }
        next.add(
          Marker(
            markerId: MarkerId('operator_sos_${row['id']}'),
            position: LatLng(lat, lng),
            icon: icons[key]!,
            anchor: const Offset(.5, 1),
            zIndexInt: 4,
            infoWindow: InfoWindow(
              title: waiting
                  ? 'SOS · Ayuda solicitada'
                  : 'SOS · ${style.label}',
              snippet: row['decision'] == 'pending' && row['claimed_by_me'] != true
                  ? 'Acepta este SOS en la tarjeta superior'
                  : 'Abrir caso SOS',
            ),
            onTap: row['decision'] == 'pending' && row['claimed_by_me'] != true
                ? null
                : () => openCase('${row['id']}'),
          ),
        );
      }
      if (mounted &&
          ticket == generation &&
          widget.enabled &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() {
          markers = next;
          baseMarkers = next;
          pendingIds = pending;
          categoryIds = categories;
          phoneIds = phones;
          urgentIds = urgent;
          alertCount = alerts;
          queueStates = nextQueue;
          queueMinutes = nextMinutes;
          incidentIds = ids;
          note = null;
        });
        configurePulse();
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          markers = {};
          baseMarkers = {};
          pendingIds = {};
          categoryIds = {};
          phoneIds = {};
          urgentIds = {};
          alertCount = 0;
          queueStates = {};
          queueMinutes = {};
          focus = null;
          pulseTimer?.cancel();
          incidentIds = {};
          note = 'No se pudieron actualizar los SOS del operador.';
        });
      }
    } finally {
      if (ticket == generation) busy = false;
    }
  }

  Future<void> openCase(String id) async {
    if (!widget.enabled || !mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => SosCasePage(caseId: id)));
    await refresh();
  }

  Future<void> acceptCase(String markerId) async {
    if (accepting != null || !mounted) return;
    final id = markerId.replaceFirst('operator_sos_', '');
    setState(() => accepting = markerId);
    try {
      await WorkflowClient.request('POST', '/operator/sos-cases/$id/claim');
      if (!mounted) return;
      setState(() {
        queueStates.remove(markerId);
        queueMinutes.remove(markerId);
      });
      await openCase(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este SOS ya fue tomado o no está disponible. Actualizando…')));
      }
    } finally {
      if (mounted) setState(() => accepting = null);
      await refresh();
    }
  }

  @override
  void dispose() {
    widget.reinforcements.removeListener(backupsChanged);
    generation++;
    timer?.cancel();
    pulseTimer?.cancel();
    session?.cancel();
    super.dispose();
  }

  Widget dutyHeader(List<Map<String, dynamic>> duty) => Material(
    color: const Color(0xffe4efff),
    elevation: 3,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openCase('${duty.first['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_police, color: Color(0xff145bb0)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                duty.first['attention'] == 'on_scene'
                    ? 'Ya llegaste a la zona · Evaluar SOS'
                    : 'SOS en atención · Acércate al lugar',
                style: const TextStyle(
                  color: Color(0xff124f96),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xff145bb0)),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: ActiveCall.id,
    builder: (context, call, _) =>
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: OperatorDuty.cases,
          builder: (context, duty, _) {
            final enRoute = duty.any((r) => r['attention'] == 'en_route');
            final redAlert = duty.isEmpty && alertCount > 0 && call == null;
            final backupGlow =
                widget.reinforcements.others.isNotEmpty &&
                !enRoute &&
                queueStates.isEmpty;
            return SosProgressFeedback(
              mode: widget.enabled && widget.active && enRoute
                  ? 'operator'
                  : null,
              child: SosIncomingAttention(
                active:
                    widget.enabled &&
                    widget.active &&
                    (enRoute || redAlert || backupGlow),
                enableSound: redAlert,
                glowColor: enRoute
                    ? const Color(0xff1678ff)
                    : redAlert
                    ? const Color(0xffff0028)
                    : ReinforcementControls.orange,
                builder: (muted, toggleMute) => Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.builder(
                      widget.enabled
                          ? {...displayedMarkers(), ...backupMarkers()}
                          : {},
                      widget.enabled ? incidentIds : {},
                      widget.enabled ? focus : null,
                    ),
                    if (widget.enabled)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (duty.isNotEmpty) ...[
                              dutyHeader(duty),
                              const SizedBox(height: 8),
                            ],
                            if (queueStates.isNotEmpty) ...[
                              SosWaitingQueue(
                                quiet: duty.isNotEmpty,
                                calls: queueIds,
                                waitingCalls: queueStates,
                                minutes: queueMinutes,
                                accepting: accepting,
                                onOpen: acceptCase,
                                onSelect: focusCaller,
                                muted: muted,
                                onMute: toggleMute,
                                onRefresh: busy ? null : refresh,
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (widget.reinforcements.banner != null)
                              ReinforcementControls.banner(
                                widget.reinforcements.banner!,
                                () => widget.onReinforcement(
                                  widget.reinforcements.banner!,
                                  false,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (widget.enabled &&
                        widget.reinforcements.others.isNotEmpty)
                      Positioned(
                        right: 12,
                        bottom: 100,
                        child: ReinforcementControls.button(
                          context,
                          widget.reinforcements,
                          widget.onReinforcement,
                        ),
                      ),
                    if (widget.enabled &&
                        queueStates.isEmpty &&
                        duty.isEmpty &&
                        widget.reinforcements.banner == null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(20),
                          child: IconButton(
                            tooltip: 'Actualizar casos SOS',
                            onPressed: busy ? null : refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ),
                    if (widget.enabled && note != null)
                      Positioned(
                        bottom: 66,
                        left: 8,
                        right: 8,
                        child: Material(
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(note!, textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
  );
}
