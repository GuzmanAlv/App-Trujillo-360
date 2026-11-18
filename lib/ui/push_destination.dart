import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/incident.dart';
import '../services/push_service.dart';
import '../services/workflow_client.dart';
import 'community_incident_page.dart';
import 'workflow_panel.dart';

class PushDestination extends StatefulWidget {
  const PushDestination({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<PushDestination> createState() => _PushDestinationState();
}

class _PushDestinationState extends State<PushDestination> {
  Map<String, dynamic>? row;
  String? error;
  int generation = 0;
  StreamSubscription<User?>? session;
  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      session = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (!PushService.instance.valid(widget.data) && mounted) {
          generation++;
          setState(() {
            row = null;
            error =
                'La sesión cambió. Regresa e inicia sesión con la cuenta que recibió el aviso.';
          });
        }
      });
    }
    load();
  }

  @override
  void dispose() {
    generation++;
    session?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation;
    try {
      if (!PushService.instance.valid(widget.data)) {
        throw StateError('Inicia sesión con la cuenta que recibió el aviso.');
      }
      final kind = widget.data['kind'] == 'citizen'
          ? 'citizen'
          : widget.data['incident'] == 'true'
          ? 'operator_incident'
          : 'operator_help';
      final data = await WorkflowClient.request(
        'GET',
        '/push/targets/$kind/${widget.data['target_id']}',
      );
      if (mounted && ticket == generation) {
        setState(() => row = Map<String, dynamic>.from(data as Map));
      }
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() => error = PushService.readable(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = row;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aviso')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error!),
          ),
        ),
      );
    }
    if (r == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.data['kind'] == 'operator') {
      return WorkflowDetail(
        row: r,
        operator: true,
        incident: widget.data['incident'] == 'true',
      );
    }
    return CommunityIncidentPage(
      incident: Incident(
        id: '${r['id']}',
        remoteId: '${r['id']}',
        type: '${r['category']}',
        place: r['place'] as String? ?? 'Incidente en tu zona',
        description: r['description'] as String? ?? '',
        attention: r['attention'] as String? ?? 'none',
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        createdAt: DateTime.parse('${r['occurred_at']}'),
        remoteStatus: '${r['status']}',
        corroborationCount: r['corroboration_count'] as int,
        needsReview: r['needs_review'] as bool,
      ),
    );
  }
}
