import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/active_call.dart';
import '../services/citizen_sos_tracker.dart';
import 'audio_call_page.dart';
import 'citizen_sos_page.dart';
import '../services/sos_route_controller.dart';
import 'sos_route_panel.dart';
import 'sos_route_badge.dart';
import 'hold_sos_button.dart';

/// Keeps the call above the route/SOS and leaves the right edge for GPS controls.
class MapBottomControls extends StatelessWidget {
  const MapBottomControls({
    super.key,
    required this.operator,
    required this.route,
    required this.onSos,
    this.sending = false,
    this.showSos = true,
    this.sendingLabel = 'Enviando…',
    this.citizenSos,
  });
  final bool operator, sending, showSos;
  final String sendingLabel;
  final SosRouteController route;
  final VoidCallback onSos;
  final CitizenSosTracker? citizenSos;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      route,
      ActiveCall.session,
      ActiveCall.presentation,
      ?citizenSos,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final call = ActiveCall.session.value;
        final active = call != null && call.minimized;
        final hasRoute = operator && route.caseId != null;
        final caseId = citizenSos?.caseId;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (active) ...[
              SosRoutePanel(route: route),
              if (hasRoute || (!operator && showSos))
                const SizedBox(height: 10),
            ],
            if (hasRoute) SosRouteBadge(route: route),
            if (!operator && showSos)
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      100,
                      math.min(
                        caseId == null ? 200 : 300,
                        constraints.maxWidth - (caseId == null ? 104 : 84),
                      ),
                    ),
                  ),
                  child: caseId != null
                      ? Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade800,
                                ),
                                onPressed: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => AudioCallPage(
                                          callId: caseId,
                                          redial: true,
                                        ),
                                      ),
                                    ),
                                icon: const Icon(Icons.call, size: 20),
                                label: const Text(
                                  'Llamar al operador',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Mi caso SOS · agregar foto',
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CitizenSosPage(caseId: caseId),
                                ),
                              ),
                              icon: const Icon(Icons.add_a_photo_outlined),
                            ),
                          ],
                        )
                      : HoldSosButton(
                          key: const ValueKey('map-sos-button'),
                          busy: sending,
                          busyLabel: sendingLabel,
                          onComplete: onSos,
                        ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
