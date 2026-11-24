import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/active_call.dart';
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
  });
  final bool operator, sending, showSos;
  final String sendingLabel;
  final SosRouteController route;
  final VoidCallback onSos;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      route,
      ActiveCall.session,
      ActiveCall.presentation,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final call = ActiveCall.session.value;
        final active = call != null && call.minimized;
        final hasRoute = operator && route.caseId != null;
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
                      math.min(200, constraints.maxWidth - 104),
                    ),
                  ),
                  child: HoldSosButton(
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
