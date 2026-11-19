import 'package:flutter/foundation.dart';

/// Only cases assigned to this signed-in operator suppress incoming SOS alarms.
class OperatorDuty {
  static final cases = ValueNotifier<List<Map<String, dynamic>>>([]);
  static String? owner;
  static bool get engaged => cases.value.isNotEmpty;
  static bool active(Map<String, dynamic> row) =>
      row['can_track'] == true &&
      row['decision'] == 'confirmed' &&
      ['en_route', 'on_scene'].contains(row['attention']);
  static void replace(String uid, List<Map<String, dynamic>> rows) {
    owner = uid;
    final next = rows.where(active).toList()
      ..sort((a, b) {
        final priority = (a['attention'] == 'en_route' ? 0 : 1).compareTo(
          b['attention'] == 'en_route' ? 0 : 1,
        );
        if (priority != 0) return priority;
        return '${b['received_at']}'.compareTo('${a['received_at']}');
      });
    cases.value = next;
  }

  static void upsert(String uid, Map<String, dynamic> row) {
    final previous = owner == uid ? cases.value : <Map<String, dynamic>>[];
    replace(uid, [...previous.where((r) => r['id'] != row['id']), row]);
  }

  static void clear() {
    owner = null;
    cases.value = [];
  }
}
