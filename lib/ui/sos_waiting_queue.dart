import 'package:flutter/material.dart';

class SosWaitingQueue extends StatelessWidget {
  const SosWaitingQueue({
    super.key,
    required this.calls,
    required this.onSelect,
    required this.muted,
    required this.onMute,
    required this.onRefresh,
    this.onOpen,
    this.waitingCalls = const {},
    this.minutes = const {},
    this.accepting,
    this.quiet = false,
    this.addressFor,
    this.selected,
  });
  final List<String> calls;
  final Map<String, bool> waitingCalls;
  final Map<String, int> minutes;
  final String? accepting, selected;
  final Future<String?> Function(String)? addressFor;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String> onSelect;
  final bool muted, quiet;
  final VoidCallback onMute;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (calls.isEmpty) return const SizedBox.shrink();
    final ordered = [...calls]
      ..sort((a, b) => (minutes[a] ?? 9999).compareTo(minutes[b] ?? 9999));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 264),
      child: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: quiet ? const Color(0xffa7313b) : const Color(0xffc41728),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.emergency, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SOS disponibles · ${calls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!quiet)
                    IconButton(
                      tooltip: muted
                          ? 'Activar sonido y vibración'
                          : 'Silenciar sonido y vibración',
                      onPressed: onMute,
                      color: Colors.white,
                      icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                    ),
                  IconButton(
                    tooltip: 'Actualizar casos SOS',
                    onPressed: onRefresh,
                    color: Colors.white,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(5),
                itemCount: ordered.length,
                itemBuilder: (context, index) {
                  final id = ordered[index];
                  final eta = minutes[id];
                  final theme = Theme.of(context);
                  const red = Color(0xffc41728);
                  return Card(
                    key: ValueKey(id),
                    margin: const EdgeInsets.only(bottom: 3),
                    elevation: 0,
                    color: selected == id ? const Color(0xffffe4e7) : null,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelect(id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.sos, color: red, size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<String?>(
                                    future: addressFor?.call(id),
                                    builder: (context, snapshot) => Text(
                                      snapshot.data?.trim().isNotEmpty == true
                                          ? snapshot.data!
                                          : 'Ubicación SOS ${index + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    eta == null
                                        ? 'Tiempo de llegada no disponible'
                                        : 'Aprox. $eta min de tu ubicación',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    waitingCalls[id] == true
                                        ? 'Llamada en espera'
                                        : 'Pendiente de atención',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: onOpen == null || accepting != null
                                  ? null
                                  : () => onOpen!(id),
                              child: Text(
                                accepting == id ? 'Tomando…' : 'Aceptar',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
