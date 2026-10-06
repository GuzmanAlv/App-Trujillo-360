import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/report_sender.dart';

void main() {
  test('Corroboration survives reload and differs from verification', () {
    final original = Incident(
      id: 'id',
      type: 'Robo',
      place: 'Prueba',
      description: '',
      latitude: 0,
      longitude: 0,
      createdAt: DateTime.now(),
    );
    final restored = Incident.fromJson(
      original.delivered('server', status: 'corroborated', count: 3).toJson(),
    );
    expect(restored.corroborationCount, 3);
    expect(restored.deliveryLabel, 'Corroborado por la comunidad');
    expect(restored.remoteStatus, isNot('verified'));
  });
  test(
    'Pending delivery survives reload and acknowledgement replaces it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = IncidentStore(prefs)..load();
      final report = Incident(
        id: ReportSender.requestId(),
        type: 'Robo',
        place: 'Prueba',
        description: '',
        latitude: 0,
        longitude: 0,
        createdAt: DateTime.now(),
        ownerUid: 'uid',
      );
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(report.id),
        true,
      );
      expect(await store.add(report), true);
      final restored = IncidentStore(prefs)..load();
      expect(restored.items.single.ownerUid, 'uid');
      expect(restored.items.single.remoteId, isNull);
      expect(await restored.add(report.delivered('server-id')), true);
      final acknowledged = IncidentStore(prefs)..load();
      expect(acknowledged.items.length, 1);
      expect(acknowledged.items.single.remoteId, 'server-id');
      expect(acknowledged.items.single.id, report.id);
    },
  );
}
