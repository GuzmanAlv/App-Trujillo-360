import 'package:flutter/material.dart';
import '../services/active_call.dart';
import '../services/sos_route_controller.dart';
import 'audio_call_page.dart';

/// An overlay row: the red call tile opens audio/evaluation; actions stay separate.
class SosRoutePanel extends StatelessWidget {
  const SosRoutePanel({super.key, required this.route});
  final SosRouteController route;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ActiveCall.presentation,
    builder: (context, _) => ValueListenableBuilder(
      valueListenable: ActiveCall.session,
      builder: (context, session, _) {
        if (session == null || !session.minimized) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final controlsEnabled =
                session.joined && !session.finished && !session.closing;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filled(
                    key: const ValueKey('compact-call-open'),
                    tooltip: 'Abrir llamada SOS',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xffc42637),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AudioCallPage(
                          callId: session.callId,
                          operator: session.operator,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.phone_in_talk, size: 23),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  key: const ValueKey('compact-call-controls'),
                  color: Colors.white.withValues(alpha: .97),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: session.muted
                            ? 'Activar micrófono'
                            : 'Silenciar micrófono',
                        isSelected: session.muted,
                        onPressed: controlsEnabled
                            ? session.toggleMicrophone
                            : null,
                        icon: const Icon(Icons.mic, size: 22),
                        selectedIcon: const Icon(Icons.mic_off, size: 22),
                      ),
                      IconButton(
                        tooltip: 'Altavoz',
                        isSelected: session.speaker,
                        onPressed: controlsEnabled
                            ? session.toggleSpeaker
                            : null,
                        icon: const Icon(Icons.volume_down, size: 23),
                        selectedIcon: const Icon(Icons.volume_up, size: 23),
                      ),
                      IconButton(
                        tooltip: session.closing
                            ? 'Cerrando…'
                            : 'Cortar llamada',
                        color: const Color(0xffc42637),
                        onPressed: session.closing || session.finished
                            ? null
                            : () async {
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
                        icon: const Icon(Icons.call_end, size: 23),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
