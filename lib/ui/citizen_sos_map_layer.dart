import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/workflow_client.dart';
import '../services/citizen_arrival_alerts.dart';
import 'citizen_sos_page.dart';
import 'report_marker.dart';
import 'report_style.dart';
import 'sos_incoming_attention.dart';
import 'sos_progress_feedback.dart';

class CitizenSosMapLayer extends StatefulWidget {
  const CitizenSosMapLayer({
    super.key,
    required this.enabled,
    required this.active,
    required this.builder,
    this.onCasesChanged,
    this.onActiveCases,
  });
  final bool enabled, active;
  final VoidCallback? onCasesChanged;
  final ValueChanged<List<Map<String, dynamic>>>? onActiveCases;
  final Widget Function(Set<Marker>, Set<String>) builder;
  @override
  State<CitizenSosMapLayer> createState() => _CitizenSosMapLayerState();
}

class _CitizenSosMapLayerState extends State<CitizenSosMapLayer> {
  List<Map<String, dynamic>> cases = [];
  final icons = <String, List<BitmapDescriptor>>{};
  Timer? poll, pulse;
  StreamSubscription<User?>? auth;
  bool busy = false;
  int generation = 0, frame = 0;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      auth = FirebaseAuth.instance.authStateChanges().listen((_) {
        clear();
        unawaited(refresh());
      });
    }
    poll = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
    unawaited(refresh());
  }

  void clear() {
    generation++;
    busy = false;
    pulse?.cancel();
    if (mounted) setState(() => cases = []);
  }

  void configurePulse() {
    pulse?.cancel();
    if (!widget.enabled ||
        !widget.active ||
        cases.isEmpty ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    pulse = Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (mounted) setState(() => frame = (frame + 1) % 6);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configurePulse();
  }

  @override
  void didUpdateWidget(covariant CitizenSosMapLayer old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      clear();
    } else if (!old.enabled || (!old.active && widget.active)) {
      unawaited(refresh());
    }
    configurePulse();
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
    busy = true;
    final ticket = ++generation;
    try {
      final rows = await WorkflowClient.list('/my-sos/map');
      for (final row in rows) {
        final category = '${row['category']}';
        final style = ReportStyle.forCategory(category);
        final pending = row['decision'] == 'pending';
        final iconKey = pending ? 'SOS_PENDING' : category;
        if (!icons.containsKey(iconKey)) {
          final frames = <BitmapDescriptor>[];
          for (final phase in [0.0, .35, .75, 1.0, .75, .35]) {
            final bytes = await renderPendingSosMarker(
              phase,
              symbol: pending ? Icons.sos : style.icon,
              color: pending ? const Color(0xffd4162a) : style.color,
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
          icons[iconKey] = frames;
        }
      }
      if (mounted &&
          ticket == generation &&
          uid == FirebaseAuth.instance.currentUser?.uid) {
        for (final row in rows) {
          final previous = cases.where((r) => r['id'] == row['id']);
          final arrived = DateTime.tryParse('${row['arrived_at']}');
          if (row['attention'] == 'on_scene' &&
              ((previous.isNotEmpty &&
                      previous.first['attention'] != 'on_scene') ||
                  (arrived != null &&
                      DateTime.now().difference(arrived).inSeconds.abs() <
                          300))) {
            unawaited(CitizenArrivalAlerts.instance.receive('${row['id']}'));
          }
        }
        final previous = cases
            .map((r) => '${r['id']}:${r['attention']}')
            .join('|');
        final next = rows.map((r) => '${r['id']}:${r['attention']}').join('|');
        final arrival = CitizenArrivalAlerts.instance.value;
        if (arrival != null && !rows.any((r) => r['id'] == arrival)) {
          CitizenArrivalAlerts.instance.clear();
        }
        setState(() => cases = rows);
        // Only confirmed cases replace the citizen's SOS button with a callback.
        widget.onActiveCases?.call(
          rows.where((r) => r['decision'] == 'confirmed').toList(),
        );
        if (previous != next) widget.onCasesChanged?.call();
        configurePulse();
      }
    } catch (_) {
      // Preserve the active SOS during temporary loss of connectivity.
    } finally {
      if (ticket == generation) busy = false;
    }
  }

  Future<void> open(String id) async {
    if (!mounted || !widget.enabled) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => CitizenSosPage(caseId: id)));
    await refresh();
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    pulse?.cancel();
    auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.enabled ? cases : <Map<String, dynamic>>[];
    final markers = <Marker>{};
    final ids = <String>{};
    for (final row in rows) {
      final category = '${row['category']}';
      final pending = row['decision'] == 'pending';
      if (row['incident_id'] is String) ids.add(row['incident_id'] as String);
      markers.add(
        Marker(
          markerId: MarkerId('my_sos_${row['id']}'),
          position: LatLng(
            (row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          ),
          icon:
              icons[pending ? 'SOS_PENDING' : category]?[frame] ??
              BitmapDescriptor.defaultMarkerWithHue(
                pending ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
              ),
          anchor: const Offset(.5, 74 / 76),
          zIndexInt: 5,
          infoWindow: InfoWindow(
            title: pending ? 'Mi SOS · Pendiente' : 'Mi SOS · $category',
            snippet: pending
                ? 'Solicitud recibida. Esperando atención.'
                : 'Ver caso y agregar información',
          ),
          onTap: () => open('${row['id']}'),
        ),
      );
    }
    // Real dispatch takes precedence over confirmed-but-not-dispatched cases.
    final confirmed = rows.where((r) => r['decision'] == 'confirmed');
    final dispatch = confirmed.where((r) => r['attention'] == 'en_route');
    final current = dispatch.isNotEmpty
        ? dispatch.first
        : confirmed.isNotEmpty
        ? confirmed.first
        : rows.isEmpty
        ? null
        : rows.first;
    return ValueListenableBuilder<String?>(
      valueListenable: CitizenArrivalAlerts.instance,
      builder: (context, arrivalCase, _) => SosProgressFeedback(
        mode: widget.enabled && widget.active && dispatch.isNotEmpty
            ? 'citizen'
            : null,
        child: SosIncomingAttention(
          active: widget.enabled && widget.active && confirmed.isNotEmpty,
          enableSound: false,
          glowColor: const Color(0xffff8800),
          builder: (muted, toggle) => Stack(
            fit: StackFit.expand,
            children: [
              widget.builder(markers, ids),
              if (arrivalCase != null && widget.enabled && widget.active)
                Positioned(
                  bottom: 14,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Material(
                      color: const Color(0xffe3efff),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => open(arrivalCase),
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_police,
                                color: Color(0xff1764b7),
                              ),
                              SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'La policía ya se encuentra en el lugar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff154b89),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (current != null)
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Material(
                        color: current['decision'] == 'pending'
                            ? const Color(0xffffe5e8)
                            : const Color(0xffffb454),
                        elevation: 4,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => open('${current['id']}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  current['decision'] == 'pending'
                                      ? Icons.sos
                                      : Icons.local_police,
                                  color: current['decision'] == 'pending'
                                      ? const Color(0xffa20d20)
                                      : const Color(0xff6d3100),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    citizenSosMessage(
                                      '${current['attention']}',
                                      decision: current['decision'] as String?,
                                      assignmentState:
                                          current['assignment_state']
                                              as String?,
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xff592800),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
