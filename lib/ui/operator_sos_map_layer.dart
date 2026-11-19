import 'sos_incoming_attention.dart';
import '../services/active_call.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/workflow_client.dart';
import 'report_marker.dart';
import 'sos_case_panel.dart';
import 'sos_status.dart';

class OperatorSosMapLayer extends StatefulWidget {
  const OperatorSosMapLayer({
    super.key,
    required this.enabled,
    required this.active,
    required this.builder,
  });
  final bool enabled, active;
  final Widget Function(Set<Marker>, Set<String>) builder;
  @override
  State<OperatorSosMapLayer> createState() => _OperatorSosMapLayerState();
}

class _OperatorSosMapLayerState extends State<OperatorSosMapLayer> {
  Timer? timer, pulseTimer;
  int pulseFrame = 0;
  final List<BitmapDescriptor> pendingIcons = [], phoneIcons = [];
  Set<String> phoneIds = {}, urgentIds = {};
  int alertCount = 0;
  Set<Marker> baseMarkers = {};
  Set<String> pendingIds = {};
  Future<void> preparePendingIcons() async {
    for (final phase in [0.0, .35, .75, 1.0, .75, .35]) {
      final bytes = await renderPendingSosMarker(phase);
      final phoneBytes = await renderPendingSosMarker(phase, waitingCall: true);
      if (!mounted) return;
      phoneIcons.add(
        BitmapDescriptor.bytes(
          phoneBytes,
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
        urgentIds.isEmpty ||
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
        phoneIds = {};
        urgentIds = {};
        alertCount = 0;
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
      final rows = await WorkflowClient.list('/operator/sos-map');
      final next = <Marker>{},
          ids = <String>{},
          pending = <String>{},
          phones = <String>{},
          urgent = <String>{};
      var alerts = 0;
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
        final waiting = row['call_waiting'] == true;
        final needsAttention =
            waiting ||
            (row['decision'] == 'pending' && row['unanswered_alert'] == true) ||
            row['support_requested'] == true;
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
                  ? 'SOS · Esperando llamada'
                  : 'SOS · ${style.label}',
              snippet: 'Abrir caso SOS',
            ),
            onTap: () => openCase('${row['id']}'),
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
          phoneIds = phones;
          urgentIds = urgent;
          alertCount = alerts;
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
          phoneIds = {};
          urgentIds = {};
          alertCount = 0;
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

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    pulseTimer?.cancel();
    session?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: ActiveCall.id,
    builder: (context, call, _) => SosIncomingAttention(
      active: widget.enabled && widget.active && alertCount > 0 && call == null,
      builder: (muted, toggleMute) => Stack(
        fit: StackFit.expand,
        children: [
          widget.builder(
            widget.enabled ? displayedMarkers() : {},
            widget.enabled ? incidentIds : {},
          ),
          if (widget.enabled)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 4,
                  color: alertCount > 0
                      ? const Color(0xffc62828)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          alertCount > 0 ? Icons.sos : Icons.local_police,
                          size: 20,
                          color: alertCount > 0 ? Colors.white : null,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            note ??
                                (alertCount > 0
                                    ? 'SOS Ayuda solicitada'
                                    : 'SOS privados · ${markers.length}'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: alertCount > 0 ? Colors.white : null,
                            ),
                          ),
                        ),
                        if (alertCount > 0)
                          IconButton(
                            tooltip: muted
                                ? 'Activar sonido y vibración'
                                : 'Silenciar sonido y vibración',
                            onPressed: toggleMute,
                            color: Colors.white,
                            icon: Icon(
                              muted ? Icons.volume_off : Icons.volume_up,
                              size: 20,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Actualizar casos SOS',
                          onPressed: busy ? null : refresh,
                          color: alertCount > 0 ? Colors.white : null,
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
