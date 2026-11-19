import 'package:flutter/material.dart';

/// Only live waiting calls belong here. Missed SOS remain on the map itself.
class SosWaitingQueue extends StatefulWidget {
  const SosWaitingQueue({
    super.key,
    required this.calls,
    required this.onSelect,
    required this.muted,
    required this.onMute,
    required this.onRefresh,
  });
  final List<String> calls;
  final ValueChanged<String> onSelect;
  final bool muted;
  final VoidCallback onMute;
  final VoidCallback? onRefresh;
  @override
  State<SosWaitingQueue> createState() => _SosWaitingQueueState();
}

class _SosWaitingQueueState extends State<SosWaitingQueue> {
  bool expanded = false;
  @override
  void didUpdateWidget(covariant SosWaitingQueue old) {
    super.didUpdateWidget(old);
    if (widget.calls.length <= 1) expanded = false;
  }

  void select(String id) {
    setState(() => expanded = false);
    widget.onSelect(id);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.calls.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Material(
        color: const Color(0xffc41728),
        elevation: 5,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (widget.calls.length == 1) {
                        select(widget.calls.single);
                      } else {
                        setState(() => expanded = !expanded);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phone_in_talk,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 7),
                          const Flexible(
                            child: Text(
                              'SOS Ayuda solicitada',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.calls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.calls.length > 1)
                            Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                              color: Colors.white,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.muted
                      ? 'Activar sonido y vibración'
                      : 'Silenciar sonido y vibración',
                  onPressed: widget.onMute,
                  color: Colors.white,
                  icon: Icon(
                    widget.muted ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar casos SOS',
                  onPressed: widget.onRefresh,
                  color: Colors.white,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            if (expanded && widget.calls.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  shrinkWrap: true,
                  itemCount: widget.calls.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.phone_in_talk,
                          color: Colors.red,
                        ),
                        title: Text(
                          'Llamada SOS ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('En espera · ver ubicación'),
                        trailing: const Icon(
                          Icons.my_location,
                          color: Colors.red,
                        ),
                        onTap: () => select(widget.calls[index]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
