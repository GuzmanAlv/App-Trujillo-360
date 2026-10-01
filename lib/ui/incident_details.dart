import 'package:flutter/material.dart';
import '../data/incident_store.dart';
import '../models/incident.dart';

Future<void> showIncidentDetails(
  BuildContext context,
  IncidentStore store,
  String incidentId,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _IncidentDetails(store: store, incidentId: incidentId),
);

class _IncidentDetails extends StatefulWidget {
  const _IncidentDetails({required this.store, required this.incidentId});
  final IncidentStore store;
  final String incidentId;
  @override
  State<_IncidentDetails> createState() => _IncidentDetailsState();
}

class _IncidentDetailsState extends State<_IncidentDetails> {
  final reason = TextEditingController();
  String? feedback;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> review(VerificationStatus status) async {
    final ok = await widget.store.review(
      widget.incidentId,
      status,
      reason.text,
    );
    if (!mounted) return;
    setState(
      () => feedback = ok
          ? 'Revisión de prueba guardada.'
          : widget.store.actionError,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final incident = widget.store.items
          .where((i) => i.id == widget.incidentId)
          .firstOrNull;
      if (incident == null) return const SizedBox.shrink();
      final admin = widget.store.profile.isAdmin;
      final reports = admin
          ? incident.reports
          : incident.reports
                .where((r) => r.reporterId == widget.store.profile.id)
                .toList();
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${incident.type} · ${incident.place}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Chip(label: Text(incident.status.label)),
              Text(
                '${incident.reporterCount} perfiles distintos · '
                '${incident.reports.length} reportes',
              ),
              Text(
                incident.isVisible
                    ? 'Visible en el mapa de prueba.'
                    : incident.status == VerificationStatus.dismissed
                    ? 'Descartado: no aparece en el mapa.'
                    : 'Aún no aparece: requiere 3 perfiles o verificación.',
              ),
              Text(
                '${incident.latitude.toStringAsFixed(6)}, '
                '${incident.longitude.toStringAsFixed(6)}',
              ),
              if (incident.reviewedAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Revisado por administrador de prueba: '
                  '${incident.reviewedAt!.toLocal()}',
                ),
                Text('Motivo: ${incident.reviewReason}'),
              ],
              const SizedBox(height: 16),
              Text(
                admin ? 'Reportes asociados' : 'Tus reportes asociados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final report in reports)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(report.place),
                  subtitle: Text(
                    '${report.description.isEmpty ? 'Sin descripción' : report.description}\n'
                    '${report.createdAt.toLocal()}\n'
                    '${report.hasKnownReporter ? (admin ? report.reporterId : 'Tu perfil de prueba') : 'Reporte anterior sin autor: no suma al umbral'}',
                  ),
                ),
              if (admin) ...[
                const Text(
                  'Revisión simulada. Este perfil no es una cuenta real.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  maxLines: 2,
                  enabled: !widget.store.saving,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de revisión',
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          widget.store.saving || widget.store.error != null
                          ? null
                          : () => review(VerificationStatus.verified),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Verificar caso'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          widget.store.saving || widget.store.error != null
                          ? null
                          : () => review(VerificationStatus.dismissed),
                      icon: const Icon(Icons.close),
                      label: const Text('Descartar caso'),
                    ),
                  ],
                ),
              ],
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(feedback!, key: const Key('review-feedback')),
                ),
              const SizedBox(height: 12),
              const Text(
                'Demostración local. No publica a otros dispositivos ni '
                'contacta a emergencias.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
