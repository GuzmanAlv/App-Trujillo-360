import 'package:flutter/material.dart';

class OperatorCallBar extends StatelessWidget {
  const OperatorCallBar({
    super.key,
    required this.message,
    required this.muted,
    required this.speaker,
    required this.finished,
    required this.closing,
    required this.connected,
    required this.onMute,
    required this.onSpeaker,
    required this.onHangUp,
    this.onOpen,
    this.compact = false,
  });
  final String message;
  final bool muted, speaker, finished, closing, connected;
  final VoidCallback onMute, onSpeaker, onHangUp;
  final VoidCallback? onOpen;
  final bool compact;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Atención SOS',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 12 : 14,
                      color: Color(0xff263d34),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff67766f),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: muted ? 'Activar micrófono' : 'Silenciar',
              onPressed: connected && !finished && !closing ? onMute : null,
              isSelected: muted,
              icon: const Icon(Icons.mic),
              selectedIcon: const Icon(Icons.mic_off),
            ),
            IconButton(
              tooltip: 'Altavoz',
              isSelected: speaker,
              onPressed: connected && !finished && !closing ? onSpeaker : null,
              icon: const Icon(Icons.hearing),
              selectedIcon: const Icon(Icons.volume_up),
            ),
            IconButton.filled(
              tooltip: closing
                  ? 'Cerrando…'
                  : finished
                  ? 'Llamada finalizada'
                  : 'Cortar llamada',
              onPressed: closing || finished ? null : onHangUp,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xffc32636),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    ),
  );
}
