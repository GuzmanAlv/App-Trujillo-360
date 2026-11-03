import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/incident.dart';

/// Only public incidents in the rolling seven-day window can alert once/session.
class ProximityAlertPolicy {
  ProximityAlertPolicy({DateTime? startedAt})
    : startedAt = startedAt ?? DateTime.now();
  final DateTime startedAt;
  final Set<String> seen = {};

  List<Incident> collect(
    Iterable<Incident> items,
    double Function(Incident) distance,
    DateTime now,
  ) => items.where((i) {
    final age = now.difference(i.createdAt);
    if (age.isNegative ||
        age >= const Duration(days: 7) ||
        !i.isCommunityVisible ||
        distance(i) > 500 ||
        seen.contains(i.id)) {
      return false;
    }
    seen.add(i.id);
    return true;
  }).toList();
}

class ProximityNotifications {
  static const channel = MethodChannel('trujillo360/proximity');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<bool> enable() async {
    if (!supported) return false;
    return await channel.invokeMethod<bool>('enable') ?? false;
  }

  Future<void> show(Incident incident, int meters) async {
    if (!supported) return;
    await channel.invokeMethod<void>('show', {
      'id': incident.id,
      'title': '${incident.type} · A $meters m de ti',
      'body':
          'Nueva incidencia cerca de ti. Toca para ver la ubicación. ${!incident.needsReview && incident.corroborationCount >= 3 && ['corroborated', 'verified'].contains(incident.remoteStatus) ? 'Corroborado por la comunidad.' : 'Pendiente de corroboración.'}',
      'payload': jsonEncode(incident.toJson()),
    });
  }

  Future<Incident?> takePending() async {
    if (!supported) return null;
    final raw = await channel.invokeMethod<String>('takePending');
    return raw == null
        ? null
        : Incident.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  void listen(void Function(Incident) onTap) {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        onTap(
          Incident.fromJson(
            jsonDecode(call.arguments as String) as Map<String, dynamic>,
          ),
        );
      }
    });
  }

  void dispose() {
    if (supported) channel.setMethodCallHandler(null);
  }
}
