import 'package:flutter/material.dart';
import '../services/workflow_client.dart';
import 'ai_simulation_panel.dart';

typedef AiRequest =
    Future<dynamic> Function(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? query,
    });

class AiReviewPanel extends StatefulWidget {
  const AiReviewPanel({super.key, this.request});
  final AiRequest? request;

  @override
  State<AiReviewPanel> createState() => _AiReviewPanelState();
}

class _AiReviewPanelState extends State<AiReviewPanel> {
  final List<Map<String, dynamic>> items = [];
  int? cursor;
  bool busy = false;
  String? error;

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => (widget.request ?? WorkflowClient.request)(
    method,
    path,
    body: body,
    query: query,
  );

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await request(
        'GET',
        '/operator/ai/candidates',
        query: {'limit': '50', if (more && cursor != null) 'before': '$cursor'},
      );
      final rows = (result['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        if (!more) {
          items.clear();
        }
        for (final row in rows) {
          final index = items.indexWhere(
            (e) => e['sequence'] == row['sequence'],
          );
          if (index < 0) {
            items.add(row);
          } else {
            items[index] = row;
          }
        }
        cursor = result['nextCursor'] as int?;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          items.clear();
          cursor = null;
          error = e is StateError
              ? e.message.toString()
              : 'No se pudo cargar la bandeja de IA.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> decide(Map<String, dynamic> item, String decision) async {
    var reason = '';
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'confirmed'
              ? 'Confirmar detección'
              : 'Descartar detección',
        ),
        content: Form(
          key: form,
          child: TextFormField(
            onChanged: (value) => reason = value,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo de la decisión',
            ),
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? 'Escribe al menos 5 caracteres.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar decisión'),
          ),
        ],
      ),
    );
    final text = reason.trim();
    if (accepted != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await request(
              'POST',
              '/operator/ai/candidates/${item['sequence']}/decisions',
              body: {'decision': decision, 'reason': text},
            )
            as Map,
      );
      if (!mounted) return;
      setState(() {
        final index = items.indexWhere(
          (e) => e['sequence'] == item['sequence'],
        );
        if (index >= 0) items[index] = result;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se pudo guardar la decisión. Actualiza y vuelve a intentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Detecciones de IA',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => AiSimulationPanel(request: widget.request),
            ),
          ),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Cámara y mapa de simulación'),
        ),
      ),
      const Text(
        'Candidatos de las cámaras autorizadas. Requieren revisión humana; confirmar no genera alertas automáticas.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Semantics(liveRegion: true, child: Text(error!)),
      if (!busy && error == null && items.isEmpty)
        const Text('No hay detecciones en tus cámaras autorizadas.'),
      for (final item in items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (item['status']) {
                  'confirmed' => 'Detección confirmada por operador',
                  'discarded' => 'Detección descartada por operador',
                  _ => 'Posible agresión · Pendiente de revisión',
                }),
                Text('Cámara: ${item['cameraId']}'),
                Text(
                  'Confianza del modelo: ${((item['confidence'] as num) * 100).toStringAsFixed(1)}%',
                ),
                Text('Modelo: ${item['modelVersion']}'),
                Text(
                  'Fecha: ${DateTime.tryParse('${item['detectedAt']}')?.toLocal() ?? item['detectedAt']}',
                ),
                Text('${item['latitude']}, ${item['longitude']}'),
                if (item['status'] == 'pending') ...[
                  const Text(
                    'Revisa la evidencia en el sistema de cámaras antes de decidir.',
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => decide(item, 'confirmed'),
                        child: const Text('Confirmar'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => decide(item, 'discarded'),
                        child: const Text('Descartar'),
                      ),
                    ],
                  ),
                ] else ...[
                  Text('Motivo: ${item['reason']}'),
                  Text('Revisado: ${item['reviewedAt']}'),
                ],
              ],
            ),
          ),
        ),
      if (cursor != null)
        TextButton(
          onPressed: busy ? null : () => load(more: true),
          child: const Text('Cargar anteriores'),
        ),
    ],
  );
}
