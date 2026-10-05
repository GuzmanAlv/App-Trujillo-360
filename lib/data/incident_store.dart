import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident.dart';

class IncidentStore extends ChangeNotifier {
  IncidentStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'trujillo360.local_reports.v1';
  final List<Incident> _items = [];
  List<Incident> get items => List.unmodifiable(_items);
  String? error;
  bool saving = false;
  void load() {
    try {
      final raw = preferences.getString(key);
      if (raw != null) {
        final data = jsonDecode(raw) as List;
        final parsed = data
            .map((j) => Incident.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        _items
          ..clear()
          ..addAll(parsed);
      }
    } catch (_) {
      error =
          'No se pudieron leer los reportes guardados. No se sobrescribirán esos datos.';
    }
  }

  Future<bool> add(Incident incident) async {
    if (saving || error != null) return false;
    saving = true;
    notifyListeners();
    try {
      final next = [incident, ..._items.where((i) => i.id != incident.id)];
      final ok = await preferences.setString(
        key,
        jsonEncode(next.map((i) => i.toJson()).toList()),
      );
      if (!ok) return false;
      _items
        ..clear()
        ..addAll(next);
      return true;
    } catch (_) {
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
