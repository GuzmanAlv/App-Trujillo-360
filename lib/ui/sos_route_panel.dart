import 'package:flutter/material.dart';
import '../services/active_call.dart';
import '../services/sos_route_controller.dart';
import 'operator_call_bar.dart';
import 'audio_call_page.dart';

class SosRoutePanel extends StatelessWidget {
  const SosRoutePanel({super.key, required this.route});
  final SosRouteController route;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([route, ActiveCall.presentation]),
    builder: (context, _) => ValueListenableBuilder(
      valueListenable: ActiveCall.session,
      builder: (context, session, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (route.caseId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffdce3df)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: Color(0xff1769ce)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.loading
                              ? 'Calculando ruta…'
                              : route.error != null
                              ? 'SOS confirmado · ruta pendiente'
                              : '${(route.seconds / 60).ceil()} min · ${(route.meters / 1000).toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          route.error ??
                              (route.loading
                                  ? 'Consultando tráfico y calles disponibles'
                                  : 'Ruta en vehículo · tiempo estimado'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar ruta',
                    onPressed: route.loading
                        ? null
                        : () => route.calculate(route.caseId!),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Quitar ruta',
                    onPressed: route.clear,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (session != null && session.minimized)
            ListenableBuilder(
              listenable: session,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AudioCallPage(
                              callId: session.callId,
                              operator: session.operator,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_full, size: 16),
                        label: const Text('Abrir llamada'),
                      ),
                    ),
                    OperatorCallBar(
                      message: session.failure ?? session.message,
                      muted: session.muted,
                      speaker: session.speaker,
                      finished: session.finished,
                      closing: session.closing,
                      connected: session.joined,
                      onMute: session.toggleMicrophone,
                      onSpeaker: session.toggleSpeaker,
                      onHangUp: () async {
                        final complete = await session.finish();
                        if (!complete && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se confirmó todo el cierre de audio.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
