import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident.dart';

/// A device-only rehearsal. Operator selection is not authentication.
class PilotCase {
  const PilotCase({
    required this.incident,
    required this.help,
    required this.priority,
    required this.receivedAt,
    this.stage = 'Recibida',
    this.published = false,
    this.events = const [],
  });
  final Incident incident;
  final bool help, published;
  final String priority, stage;
  final DateTime receivedAt;
  final List<Map<String, String>> events;
  bool get terminal => stage == 'Cerrada' || stage == 'Descartada';
  // Pilot policy, not an assertion that a threat has ended.
  bool activeAt(DateTime now) =>
      !terminal &&
      !incident.createdAt.isAfter(now) &&
      now.difference(incident.createdAt) < const Duration(days: 7);
  bool publicAt(DateTime now, {bool historical = false}) =>
      published &&
      stage != 'Descartada' &&
      !incident.createdAt.isAfter(now) &&
      (historical
          ? now.difference(incident.createdAt) < const Duration(days: 90)
          : activeAt(now));
  Map<String, dynamic> toJson() => {
    'incident': incident.toJson(),
    'help': help,
    'priority': priority,
    'receivedAt': receivedAt.toIso8601String(),
    'stage': stage,
    'published': published,
    'events': events,
  };
  factory PilotCase.fromJson(Map<String, dynamic> value) => PilotCase(
    incident: Incident.fromJson(
      Map<String, dynamic>.from(value['incident'] as Map),
    ),
    help: value['help'] as bool,
    priority: value['priority'] as String,
    receivedAt: DateTime.parse(value['receivedAt'] as String),
    stage: value['stage'] as String,
    published: value['published'] as bool,
    events: (value['events'] as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList(),
  );
}

class PilotStore extends ChangeNotifier {
  PilotStore(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'trujillo360.pilot.cases.v1';
  List<PilotCase> _cases = [];
  List<PilotCase> get cases => List.unmodifiable(_cases);
  bool saving = false;
  String? error;
  void load() {
    try {
      final raw = preferences.getString(storageKey);
      if (raw != null) {
        _cases = (jsonDecode(raw) as List)
            .map((e) => PilotCase.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      error =
          'No se pudo leer la prueba local. No se sobrescribirán los datos.';
    }
  }

  Future<bool> _save(List<PilotCase> next) async {
    if (saving || error != null) return false;
    saving = true;
    notifyListeners();
    try {
      if (!await preferences.setString(
        storageKey,
        jsonEncode(next.map((e) => e.toJson()).toList()),
      )) {
        return false;
      }
      _cases = next;
      return true;
    } catch (_) {
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> submit(
    Incident incident, {
    required bool help,
    required String priority,
  }) {
    if (_cases.any((c) => c.incident.id == incident.id)) {
      return Future.value(false);
    }
    final now = DateTime.now();
    return _save([
      PilotCase(
        incident: incident,
        help: help,
        priority: priority,
        receivedAt: now,
        events: [
          {
            'at': now.toIso8601String(),
            'text': help
                ? 'Solicitud recibida en la bandeja local. No se contactó a una institución.'
                : 'Reporte guardado para revisión local.',
          },
        ],
      ),
      ..._cases,
    ]);
  }

  static const transitions = {
    'Recibida': ['En revisión', 'Descartada'],
    'En revisión': ['Acción registrada', 'Cerrada', 'Descartada'],
    'Acción registrada': ['Acción registrada', 'Cerrada', 'Descartada'],
  };
  Future<bool> update(
    String id, {
    required String stage,
    required String reason,
    required String priority,
    bool publish = false,
  }) async {
    final index = _cases.indexWhere((c) => c.incident.id == id);
    if (index < 0 ||
        reason.trim().length < 5 ||
        !['Baja', 'Media', 'Alta'].contains(priority)) {
      return false;
    }
    final old = _cases[index];
    if (old.terminal || !(transitions[old.stage] ?? []).contains(stage)) {
      return false;
    }
    // Publication is an explicit review decision, independent of urgency.
    if (publish && stage != 'En revisión' && stage != 'Acción registrada') {
      return false;
    }
    final next = List<PilotCase>.of(_cases);
    next[index] = PilotCase(
      incident: old.incident,
      help: old.help,
      receivedAt: old.receivedAt,
      priority: priority,
      stage: stage,
      published: stage == 'Descartada' ? false : old.published || publish,
      events: [
        ...old.events,
        {
          'at': DateTime.now().toIso8601String(),
          'text':
              '$stage · Urgencia $priority${publish ? ' · Revisado para publicación' : ''}: ${reason.trim()}',
        },
      ],
    );
    return _save(next);
  }
}
