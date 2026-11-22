import 'package:flutter/material.dart';

class SosWaitingQueue extends StatelessWidget {
  const SosWaitingQueue({super.key, required this.calls, required this.onSelect,
    required this.muted, required this.onMute, required this.onRefresh,
    this.onOpen, this.waitingCalls = const {}, this.minutes = const {},
    this.accepting, this.quiet = false});
  final List<String> calls;
  final Map<String, bool> waitingCalls;
  final Map<String, int> minutes;
  final String? accepting;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String> onSelect;
  final bool muted, quiet;
  final VoidCallback onMute;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (calls.isEmpty) return const SizedBox.shrink();
    final ordered = [...calls]..sort((a, b) =>
        (minutes[a] ?? 9999).compareTo(minutes[b] ?? 9999));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 300),
      child: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: quiet ? const Color(0xffa7313b) : const Color(0xffc41728),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Icon(Icons.emergency, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('SOS disponibles · ${calls.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              if (!quiet) IconButton(
                tooltip: muted ? 'Activar sonido y vibración' : 'Silenciar sonido y vibración',
                onPressed: onMute, color: Colors.white,
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up)),
              IconButton(tooltip: 'Actualizar casos SOS', onPressed: onRefresh,
                color: Colors.white, icon: const Icon(Icons.refresh)),
            ]),
          ),
          Flexible(child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              final id = ordered[index];
              final eta = minutes[id];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    const Icon(Icons.sos, color: Color(0xffc41728)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SOS ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(eta == null ? 'Tiempo de llegada no disponible' :
                          'Aprox. $eta min de tu ubicación'),
                        Text(waitingCalls[id] == true ? 'Llamada en espera' : 'Pendiente de atención',
                          style: Theme.of(context).textTheme.bodySmall),
                      ])),
                    IconButton(tooltip: 'Ver ubicación', onPressed: () => onSelect(id),
                      icon: const Icon(Icons.my_location)),
                    FilledButton(
                      onPressed: onOpen == null || accepting != null ? null : () => onOpen!(id),
                      child: Text(accepting == id ? 'Tomando…' : 'Aceptar')),
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
    );
  }
}
