import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../data/nearby_reports_store.dart';
import 'report_style.dart';
import 'nearby_incident_page.dart';
import 'sos_history_section.dart';

class ReportsPanel extends StatefulWidget {
  const ReportsPanel({
    super.key,
    required this.filter,
    required this.active,
    required this.nearby,
    required this.onNearbySelected,
    this.onSessionChanged,
  });
  final String filter;
  final bool active;
  final NearbyReportsStore nearby;
  final ValueChanged<bool> onNearbySelected;
  final VoidCallback? onSessionChanged;
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  StreamSubscription<User?>? authSubscription;
  bool mine = true;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        widget.nearby.clearSession();
        widget.onSessionChanged?.call();
      });
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.nearby,
    builder: (context, _) {
      final nearby = widget.nearby;
      final cases = nearby
          .filtered(widget.filter)
          .where(
            (i) => i.isSos && (i.remoteStatus == 'verified' || i.isResolved),
          )
          .toList();
      return Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Cerca de mí'),
                icon: Icon(Icons.near_me_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Mis Solicitudes'),
                icon: Icon(Icons.person_outline),
              ),
            ],
            selected: {mine},
            onSelectionChanged: (value) {
              setState(() => mine = value.single);
              widget.onNearbySelected(!mine);
            },
          ),
          const SizedBox(height: 12),
          Text(
            mine
                ? 'Tus solicitudes SOS, incluidas las confirmadas y resueltas.'
                : 'SOS confirmados y resueltos a 1 km de tu ubicación.',
            textAlign: TextAlign.center,
          ),
          if (!mine) ...[
            TextButton.icon(
              onPressed: nearby.locating ? null : nearby.start,
              icon: const Icon(Icons.my_location),
              label: Text(
                nearby.locating
                    ? 'Buscando ubicación…'
                    : nearby.position == null
                    ? 'Activar ubicación'
                    : 'Actualizar ubicación',
              ),
            ),
            if (nearby.loading) const LinearProgressIndicator(),
            if (nearby.note != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(nearby.note!, textAlign: TextAlign.center),
              ),
          ],
          Expanded(
            child: mine
                ? ListView(
                    children: [
                      SosHistorySection(
                        active: widget.active,
                        filter: widget.filter,
                      ),
                    ],
                  )
                : cases.isEmpty
                ? Center(
                    child: Text(
                      nearby.position == null
                          ? 'Activa tu ubicación para ver SOS cercanos.'
                          : nearby.loading
                          ? 'Consultando SOS cercanos…'
                          : nearby.note != null
                          ? 'No se pudieron consultar los SOS cercanos.'
                          : 'No hay SOS confirmados o resueltos en esta categoría dentro de 1 km.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: cases.length,
                    itemBuilder: (context, index) {
                      final sos = cases[index];
                      final meters = nearby.distance(sos);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: ReportCategoryIcon(category: sos.type),
                          title: Text('SOS · ${sos.type}'),
                          subtitle: Text(
                            '${sos.sosStatusLabel} · ${meters.round()} m\n${reportDateTime(sos.createdAt)}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NearbyIncidentPage(
                                incident: sos,
                                distance: meters,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
