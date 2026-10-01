import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident.dart';
import '../models/report.dart';
import '../models/demo_profile.dart';

class IncidentStore extends ChangeNotifier {
  IncidentStore(this.preferences);
  final SharedPreferences preferences;
  static const legacyKey = 'trujillo360.local_reports.v1';
  static const key = 'trujillo360.local_reports.v2';
  static const groupingMeters = 150.0;
  static const groupingWindow = Duration(minutes: 30);
  final List<Incident> _items = [];
  List<Incident> get items => List.unmodifiable(_items);
  List<Incident> get mapItems => items.where((i) => i.isVisible).toList();
  List<Incident> get ownItems => items
      .where((i) => i.reports.any((r) => r.reporterId == profile.id))
      .toList();
  DemoProfile profile = DemoProfile.neighbor1;
  String? error;
  String? actionError;
  bool saving = false;
  void selectProfile(DemoProfile value) {
    if (saving) return;
    profile = value;
    actionError = null;
    notifyListeners();
  }

  void load() {
    try {
      final raw = preferences.getString(key);
      final List<Incident> parsed;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['schemaVersion'] != 2) {
          throw const FormatException('Versión no compatible');
        }
        parsed = (data['incidents'] as List)
            .map((j) => Incident.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      } else {
        final old = preferences.getString(legacyKey);
        parsed = old == null
            ? []
            : (jsonDecode(old) as List).map((j) {
                final report = Report.fromJson(
                  Map<String, dynamic>.from(j as Map),
                  legacy: true,
                );
                return Incident(id: 'legacy-${report.id}', reports: [report]);
              }).toList();
      }
      final ids = parsed.expand((i) => i.reports).map((r) => r.id).toList();
      if (ids.toSet().length != ids.length ||
          parsed.map((i) => i.id).toSet().length != parsed.length) {
        throw const FormatException('Identificadores duplicados');
      }
      _items
        ..clear()
        ..addAll(parsed);
      error = null;
    } catch (_) {
      error =
          'No se pudieron leer los reportes guardados. Se conservan los datos originales y se bloquean los cambios.';
    }
  }

  bool matches(Incident incident, Report report) {
    final elapsed = report.createdAt.difference(incident.createdAt);
    return incident.type == report.type &&
        elapsed >= Duration.zero &&
        elapsed <= groupingWindow &&
        distanceMeters(
              incident.latitude,
              incident.longitude,
              report.latitude,
              report.longitude,
            ) <=
            groupingMeters;
  }

  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  Future<bool> add(Report report) async {
    actionError = null;
    if (profile.isAdmin || report.reporterId != profile.id) {
      actionError = 'Selecciona un perfil de vecino para reportar.';
      return false;
    }
    try {
      report.validate();
    } catch (_) {
      actionError = 'Revisa los datos del reporte.';
      return false;
    }
    if (_items.any((i) => i.reports.any((r) => r.id == report.id))) {
      actionError = 'Ese reporte ya está registrado.';
      return false;
    }
    // El ancla queda fija: no se extiende la zona o ventana mediante cadenas.
    final candidates = _items.where((i) => matches(i, report)).toList()
      ..sort((a, b) {
        final distanceA = distanceMeters(
          a.latitude,
          a.longitude,
          report.latitude,
          report.longitude,
        );
        final distanceB = distanceMeters(
          b.latitude,
          b.longitude,
          report.latitude,
          report.longitude,
        );
        final comparison = distanceA.compareTo(distanceB);
        return comparison != 0 ? comparison : a.id.compareTo(b.id);
      });
    final target = candidates.isEmpty ? null : candidates.first;
    final next = [..._items];
    if (target == null) {
      next.insert(0, Incident(id: 'case-${report.id}', reports: [report]));
    } else {
      next[next.indexOf(target)] = target.withReport(report);
    }
    return _persist(next);
  }

  Future<bool> review(
    String id,
    VerificationStatus status,
    String reason,
  ) async {
    actionError = null;
    if (!profile.isAdmin) {
      actionError = 'Solo el administrador de prueba puede revisar casos.';
      return false;
    }
    if (status == VerificationStatus.unverified ||
        reason.trim().isEmpty ||
        reason.trim().length > 500) {
      actionError = 'Escribe un motivo de revisión de hasta 500 caracteres.';
      return false;
    }
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) {
      actionError = 'El caso ya no está disponible.';
      return false;
    }
    final next = [..._items];
    next[index] = next[index].reviewed(
      status,
      profile.id,
      reason.trim(),
      DateTime.now().toUtc(),
    );
    return _persist(next);
  }

  Future<bool> _persist(List<Incident> next) async {
    if (saving || error != null) {
      actionError = error ?? 'Hay otro cambio guardándose. Inténtalo de nuevo.';
      return false;
    }
    saving = true;
    notifyListeners();
    try {
      final ok = await preferences.setString(
        key,
        jsonEncode({
          'schemaVersion': 2,
          'incidents': next.map((i) => i.toJson()).toList(),
        }),
      );
      if (!ok) throw StateError('No se pudo guardar');
      _items
        ..clear()
        ..addAll(next);
      return true;
    } catch (_) {
      actionError = 'No se pudo guardar el cambio. Inténtalo nuevamente.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
