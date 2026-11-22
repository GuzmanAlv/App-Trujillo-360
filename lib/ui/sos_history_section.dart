import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/nearby_reports_client.dart';
import '../services/workflow_client.dart';
import 'report_style.dart';

Future<List<Map<String, dynamic>>> fetchSosHistory(int offset) async =>
    (await WorkflowClient.request(
              'GET',
              '/my-sos/history',
              query: {'limit': '50', 'offset': '$offset'},
            )
            as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

String sosHistoryStatus(Map<String, dynamic> row) {
  if (row['decision'] == 'discarded' || row['stage'] == 'Descartada') {
    return 'Descartado';
  }
  if (row['attention'] == 'resolved' || row['stage'] == 'Cerrada') {
    return 'Resuelto';
  }
  return switch (row['attention']) {
    'on_scene' => 'Personal en el lugar',
    'en_route' => 'Unidad en camino',
    _ => row['decision'] == 'confirmed' ? 'Confirmado' : 'Pendiente',
  };
}

String historyTime(dynamic value) {
  final at = DateTime.tryParse('$value');
  return at == null ? '' : reportDateTime(at);
}

/// Owner-only, paginated history. Closed cases never feed the active SOS layer.
class SosHistorySection extends StatefulWidget {
  const SosHistorySection({
    super.key,
    required this.active,
    required this.filter,
    this.fetch,
    this.owner,
  });
  final bool active;
  final String filter;
  final Future<List<Map<String, dynamic>>> Function(int)? fetch;
  final String? Function()? owner;
  @override
  State<SosHistorySection> createState() => _SosHistorySectionState();
}

class _SosHistorySectionState extends State<SosHistorySection> {
  List<Map<String, dynamic>> rows = [];
  StreamSubscription<User?>? auth;
  int generation = 0;
  bool busy = false, more = false;
  String? error;
  String? get owner =>
      widget.owner == null ? currentReportOwner : widget.owner!();
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty && widget.owner == null) {
      auth = FirebaseAuth.instance.authStateChanges().listen((_) {
        generation++;
        setState(() {
          rows = [];
          busy = false;
          more = false;
          error = null;
        });
        if (widget.active) unawaited(load());
      });
    } else if (widget.active) {
      unawaited(load());
    }
  }

  @override
  void didUpdateWidget(covariant SosHistorySection old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) unawaited(load());
  }

  Future<void> load({bool append = false}) async {
    if (busy) return;
    final uid = owner;
    final ticket = ++generation;
    if (uid == null) {
      setState(() {
        rows = [];
        more = false;
        error = null;
      });
      return;
    }
    final offset = append ? rows.length : 0;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await (widget.fetch ?? fetchSosHistory)(offset);
      if (mounted && generation == ticket && owner == uid) {
        setState(() {
          rows = append ? [...rows, ...page] : page;
          more = page.length == 50;
        });
      }
    } catch (_) {
      if (mounted && generation == ticket && owner == uid) {
        setState(
          () =>
              error = 'No se pudo cargar tu historial SOS. Vuelve a intentar.',
        );
      }
    } finally {
      if (mounted && generation == ticket) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    auth?.cancel();
    super.dispose();
  }

  void details(Map<String, dynamic> row) {
    final date = DateTime.tryParse('${row['received_at']}');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SOS · ${row['category']}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(sosHistoryStatus(row)),
              if (date != null) Text('Solicitado: ${reportDateTime(date)}'),
              if (DateTime.tryParse('${row['resolved_at']}')
                  case final DateTime at)
                Text('Resuelto: ${reportDateTime(at)}'),
              if ('${row['place'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${row['place']}'),
              ],
              if ('${row['description'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${row['description']}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows.where(
      (r) => widget.filter == 'Todos' || r['category'] == widget.filter,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Historial de SOS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar historial SOS',
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, textAlign: TextAlign.center),
        if (visible.isEmpty && !busy && error == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              owner == null
                  ? 'Inicia sesión para ver tu historial SOS.'
                  : 'No hay SOS en esta categoría.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final row in visible)
          Card(
            child: ListTile(
              leading: ReportCategoryIcon(category: '${row['category']}'),
              title: Text('SOS · ${row['category']}'),
              subtitle: Text(
                '${sosHistoryStatus(row)}\n${historyTime(row['received_at'])}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => details(row),
            ),
          ),
        if (more)
          TextButton(
            onPressed: busy ? null : () => load(append: true),
            child: const Text('Cargar SOS anteriores'),
          ),
      ],
    );
  }
}
