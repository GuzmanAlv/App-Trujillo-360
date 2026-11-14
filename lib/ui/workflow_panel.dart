import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../data/ai_detection_store.dart';
import '../services/workflow_client.dart';
import '../services/nearby_reports_client.dart';
import 'ai_detection_panel.dart';
import 'map_panel.dart';
import 'community_photo_view.dart';

String workflowTime(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class OperatorPortal extends StatefulWidget {
  const OperatorPortal({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<OperatorPortal> createState() => _OperatorPortalState();
}

class _OperatorPortalState extends State<OperatorPortal> {
  final ai = AiDetectionStore();
  bool allowed = false, busy = true;
  String? error;
  int generation = 0;
  StreamSubscription<User?>? session;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      session = FirebaseAuth.instance.authStateChanges().listen((_) {
        check();
      });
    } else {
      check();
    }
  }

  Future<void> check() async {
    final ticket = ++generation;
    setState(() {
      allowed = false;
      busy = true;
      error = null;
    });
    try {
      final p = await WorkflowClient.profile();
      if (mounted && ticket == generation) {
        setState(() {
          allowed =
              p['status'] == 'active' &&
              ['operator', 'admin'].contains(p['role']);
          error = allowed
              ? null
              : 'Esta cuenta es de ciudadano. Un administrador debe autorizar el acceso de operador.';
        });
      }
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se pudo verificar el permiso.',
        );
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    session?.cancel();
    ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        toolbarHeight: widget.embedded ? 0 : null,
        title: widget.embedded ? null : const Text('Seguridad ciudadana'),
        bottom: allowed
            ? const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Ayuda'),
                  Tab(text: 'Revisar reportes'),
                  Tab(text: 'Cámaras / IA'),
                ],
              )
            : null,
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : !allowed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    Text(
                      error ?? 'Acceso restringido',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: check,
                      child: const Text('Verificar acceso'),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              children: [
                WorkflowPanel(operator: true, onDenied: check),
                WorkflowPanel(operator: true, incidents: true, onDenied: check),
                AiDetectionPanel(store: ai),
              ],
            ),
    ),
  );
}

class WorkflowPanel extends StatefulWidget {
  const WorkflowPanel({
    super.key,
    this.operator = false,
    this.incidents = false,
    this.onDenied,
  });
  final bool operator, incidents;
  final VoidCallback? onDenied;
  @override
  State<WorkflowPanel> createState() => _WorkflowPanelState();
}

class _WorkflowPanelState extends State<WorkflowPanel>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> rows = [];
  String incidentGroup = 'pending';
  bool busy = false;
  String? error;
  int generation = 0;
  Timer? timer;
  StreamSubscription<User?>? session;
  final seen = <String>{};
  bool loadedOnce = false, foreground = true;
  String get path => widget.incidents
      ? '/operator/incidents'
      : widget.operator
      ? '/operator/help-requests'
      : '/help-requests';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      session = FirebaseAuth.instance.authStateChanges().listen((_) {
        generation++;
        rows = [];
        seen.clear();
        loadedOnce = false;
        busy = false;
        load();
      });
    } else {
      load();
    }
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (foreground) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) load();
  }

  Future<void> load() async {
    if (busy || !mounted) return;
    final ticket = ++generation;
    setState(() => busy = true);
    try {
      final values = await WorkflowClient.list(path);
      if (!mounted || ticket != generation) return;
      final fresh = values
          .where(
            (r) =>
                !seen.contains('${r['id']}') &&
                !['Cerrada', 'Descartada'].contains(r['stage']),
          )
          .length;
      if (widget.operator && !widget.incidents && loadedOnce && fresh > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$fresh nuevas solicitudes de ayuda. Revisa la bandeja.',
            ),
          ),
        );
      }
      seen.addAll(values.map((r) => '${r['id']}'));
      setState(() {
        rows = values;
        error = null;
        loadedOnce = true;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          rows = [];
          error = e is StateError
              ? e.message.toString()
              : 'No se pudo consultar la bandeja.';
        });
        if (e is StateError &&
            e.message.toString().contains('no está autorizada')) {
          widget.onDenied?.call();
        }
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    session?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget incidentFilter(String value, String label, int count) {
    final selected = incidentGroup == value;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count incidentes',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => incidentGroup = value),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: selected ? const Color(0xffcce9df) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? const Color(0xff087f68) : Colors.black26,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11.5),
                ),
                Text(
                  '$count',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = widget.incidents
        ? rows.where((r) => r['status'] == incidentGroup).toList()
        : rows;
    final pendingCount = rows.where((r) => r['status'] == 'pending').length;
    final communityCount = rows
        .where((r) => r['status'] == 'corroborated')
        .length;
    final reviewedCount = rows.where((r) => r['status'] == 'verified').length;
    return Column(
      children: [
        if (!widget.operator)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Tus solicitudes conservan su seguimiento hasta que un operador las cierre. No avisa automáticamente a servicios oficiales.',
            ),
          ),
        if (widget.incidents)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                incidentFilter('pending', 'Pendientes', pendingCount),
                const SizedBox(width: 4),
                incidentFilter('corroborated', 'Comunidad', communityCount),
                const SizedBox(width: 4),
                incidentFilter('verified', 'Verificados', reviewedCount),
                IconButton(
                  tooltip: 'Actualizar reportes',
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          )
        else
          TextButton.icon(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error!, textAlign: TextAlign.center),
          ),
        Expanded(
          child: visibleRows.isEmpty
              ? Center(
                  child: Text(
                    error != null
                        ? 'Sin datos confirmados.'
                        : busy
                        ? 'Consultando…'
                        : widget.incidents
                        ? switch (incidentGroup) {
                            'corroborated' =>
                              'No hay incidentes publicados por la comunidad.',
                            'verified' =>
                              'No hay incidentes verificados por un operador.',
                            _ => 'No hay reportes pendientes de revisión.',
                          }
                        : 'No hay casos para mostrar.',
                  ),
                )
              : ListView.builder(
                  itemCount: visibleRows.length,
                  itemBuilder: (_, index) {
                    final r = visibleRows[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: Icon(
                          widget.incidents
                              ? Icons.fact_check_outlined
                              : Icons.sos,
                          color: r['priority'] == 'Alta'
                              ? Colors.red
                              : const Color(0xff087f68),
                        ),
                        title: Text(
                          r['source'] == 'sos'
                              ? 'SOS · Ubicación compartida'
                              : '${r['category']} · ${r['place'] ?? 'Incidente'}',
                        ),
                        subtitle: Text(
                          widget.incidents
                              ? '${r['status']} · ${r['corroboration_count']} aportes · ${workflowTime(r['occurred_at'])}'
                              : 'Urgencia ${r['priority']} · ${r['stage']}\n${workflowTime(r['received_at'])}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkflowDetail(
                                row: r,
                                operator: widget.operator,
                                incident: widget.incidents,
                              ),
                            ),
                          );
                          load();
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class WorkflowDetail extends StatefulWidget {
  const WorkflowDetail({
    super.key,
    required this.row,
    required this.operator,
    required this.incident,
  });
  final Map<String, dynamic> row;
  final bool operator, incident;
  @override
  State<WorkflowDetail> createState() => _WorkflowDetailState();
}

class _WorkflowDetailState extends State<WorkflowDetail> {
  List<Map<String, dynamic>>? evidence;
  String? evidenceError;
  Future<void> loadEvidence() async {
    try {
      final data = await WorkflowClient.list(
        '/operator/incidents/${widget.row['id']}/reports',
      );
      if (mounted && !stale) {
        setState(() {
          evidence = data;
          evidenceError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => evidenceError = e is StateError
              ? e.message.toString()
              : 'No se pudieron consultar los aportes.',
        );
      }
    }
  }

  final reason = TextEditingController();
  String? decision, priority;
  bool busy = false, stale = false;
  String? error;
  StreamSubscription<User?>? session;
  @override
  void initState() {
    super.initState();
    final owner = currentReportOwner;
    if (widget.incident) loadEvidence();
    if (Firebase.apps.isNotEmpty) {
      session = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u?.uid != owner && mounted) setState(() => stale = true);
      });
    }
  }

  @override
  void dispose() {
    reason.dispose();
    session?.cancel();
    super.dispose();
  }

  Future<void> save([String? incidentDecision]) async {
    if (reason.text.trim().length < 5) {
      setState(() => error = 'Escribe un motivo de al menos 5 caracteres.');
      return;
    }
    setState(() => busy = true);
    try {
      final r = widget.row;
      await WorkflowClient.request(
        'POST',
        '/operator/${widget.incident ? 'incidents' : 'help-requests'}/${r['id']}/decisions',
        body: widget.incident
            ? {'decision': incidentDecision, 'reason': reason.text.trim()}
            : {
                'stage':
                    decision ??
                    (r['stage'] == 'Recibida'
                        ? 'En revisión'
                        : 'Acción registrada'),
                'priority': priority ?? r['priority'],
                'reason': reason.text.trim(),
              },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'No se confirmó el cambio.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final terminal = ['Cerrada', 'Descartada'].contains(r['stage']);
    final options = r['stage'] == 'Recibida'
        ? ['En revisión', 'Descartada']
        : ['Acción registrada', 'Cerrada', 'Descartada'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.incident ? 'Revisar incidente' : 'Seguimiento de ayuda',
        ),
      ),
      body: stale
          ? const Center(
              child: Text(
                'La sesión cambió. Regresa y vuelve a abrir el caso.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  r['source'] == 'sos'
                      ? 'SOS · Ubicación compartida'
                      : '${r['category']} · ${r['place'] ?? 'Incidente'}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  widget.incident
                      ? 'Estado: ${r['status']}'
                      : '${r['stage']} · Urgencia ${r['priority']}',
                ),
                if (r['description'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${r['description']}'),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: MapPanel(
                    selected: LatLng(
                      (r['latitude'] as num).toDouble(),
                      (r['longitude'] as num).toDouble(),
                    ),
                  ),
                ),
                for (final e in (r['events'] as List? ?? []))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text('${e['stage']} · ${e['reason']}'),
                    subtitle: Text(workflowTime(e['at'])),
                  ),
                if (widget.incident) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Aportes para revisión',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (evidence == null && evidenceError == null)
                    const LinearProgressIndicator(),
                  if (evidenceError != null) Text(evidenceError!),
                  TextButton(
                    onPressed: loadEvidence,
                    child: const Text('Actualizar aportes'),
                  ),
                  for (final contribution
                      in evidence ?? <Map<String, dynamic>>[]) ...[
                    Text(
                      '${contribution['place']} · ${workflowTime(contribution['occurred_at'])}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('${contribution['description']}'),
                    for (final photo in contribution['photos'] as List? ?? [])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 180,
                          child: CommunityPhotoView(
                            incidentId: '${r['id']}',
                            photoId: '$photo',
                            fetch: WorkflowClient.photo,
                          ),
                        ),
                      ),
                    const Divider(),
                  ],
                ],
                if (widget.operator && !terminal) ...[
                  const SizedBox(height: 16),
                  if (!widget.incident) ...[
                    DropdownButtonFormField<String>(
                      initialValue: options.first,
                      decoration: const InputDecoration(labelText: 'Decisión'),
                      items: options
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => decision = s,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: r['priority'] as String,
                      decoration: const InputDecoration(
                        labelText: 'Urgencia revisada',
                      ),
                      items: ['Baja', 'Media', 'Alta']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => priority = s,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo o acción realizada',
                    ),
                  ),
                  if (widget.incident) ...[
                    const Text(
                      'Revisa los aportes antes de confirmar o descartar.',
                    ),
                    if (r['status'] != 'verified') ...[
                      FilledButton(
                        onPressed: busy || evidence == null
                            ? null
                            : () => save('verified'),
                        child: Text(
                          busy
                              ? 'Guardando…'
                              : r['status'] == 'corroborated'
                              ? 'Confirmar incidente'
                              : 'Confirmar y publicar',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: busy || evidence == null
                            ? null
                            : () => save('discarded'),
                        child: const Text('Descartar incidente'),
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: busy || evidence == null
                            ? null
                            : () => save('closed'),
                        child: const Text('Cerrar incidente'),
                      ),
                  ] else ...[
                    const Text(
                      'Registra únicamente acciones realizadas. No presupone el envío de agentes.',
                    ),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Guardando…' : 'Guardar decisión'),
                    ),
                  ],
                ],
                if (error != null) Text(error!),
              ],
            ),
    );
  }
}
