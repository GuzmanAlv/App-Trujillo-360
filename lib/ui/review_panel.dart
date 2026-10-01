import 'package:flutter/material.dart';
import '../data/incident_store.dart';
import 'incident_details.dart';

class ReviewPanel extends StatelessWidget {
  const ReviewPanel({super.key, required this.store});
  final IncidentStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (!store.profile.isAdmin) {
        return const Center(
          child: Text('Selecciona el administrador de prueba.'),
        );
      }
      final incidents = store.items;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Revisión de casos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Puedes revisar desde el primer reporte. '
            'Verificar publica el caso en el mapa de prueba; descartar lo oculta. '
            'No gestiona atención de autoridades.',
          ),
          const SizedBox(height: 16),
          if (incidents.isEmpty) const Text('No hay casos para revisar.'),
          for (final incident in incidents)
            Card(
              child: ListTile(
                title: Text('${incident.type} · ${incident.place}'),
                subtitle: Text(
                  '${incident.status.label} · '
                  '${incident.reporterCount} perfiles distintos',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showIncidentDetails(context, store, incident.id),
              ),
            ),
        ],
      );
    },
  );
}
