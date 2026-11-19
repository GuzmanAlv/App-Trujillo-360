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
          if (session != null && session.minimized)
            ListenableBuilder(
              listenable: session,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: OperatorCallBar(
                  compact: true,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AudioCallPage(
                        callId: session.callId,
                        operator: session.operator,
                      ),
                    ),
                  ),
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
              ),
            ),
        ],
      ),
    ),
  );
}
