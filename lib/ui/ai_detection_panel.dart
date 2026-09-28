import 'package:flutter/material.dart';
import '../data/ai_detection_store.dart';

class AiDetectionPanel extends StatelessWidget {
  const AiDetectionPanel({super.key, required this.store});
  final AiDetectionStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Detecciones de IA',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Posibles agresiones que requieren revisión humana. '
          'No generan reportes ciudadanos ni alertas automáticas.',
        ),
        const SizedBox(height: 16),
        Text(switch (store.connection) {
          AiConnection.disconnected => 'Sin conexión con el servicio de IA.',
          AiConnection.listening => 'Recibiendo eventos del servicio de IA.',
          AiConnection.failed =>
            'Se interrumpió la conexión con el servicio de IA.',
        }),
        if (store.rejectedEvents > 0)
          Text('Eventos con formato inválido: ${store.rejectedEvents}'),
        const SizedBox(height: 24),
        if (store.items.isEmpty)
          const Text(
            'No hay detecciones recibidas en esta sesión.',
          ),
        for (final detection in store.items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Posible agresión · Pendiente de revisión'),
                  Text('Cámara: ${detection.cameraId}'),
                  Text(
                    'Confianza del modelo: ${(detection.confidence * 100).toStringAsFixed(1)}%',
                  ),
                  Text('Modelo: ${detection.modelVersion}'),
                  Text('Fecha: ${detection.detectedAt.toLocal()}'),
                  Text('${detection.latitude}, ${detection.longitude}'),
                  const Text(
                    'La validación por operadores estará disponible al conectar el backend.',
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
