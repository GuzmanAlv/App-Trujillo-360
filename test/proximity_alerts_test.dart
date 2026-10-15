import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/proximity_alerts.dart';
import 'package:alerta_ciudadana/ui/nearby_incident_page.dart';
import 'package:alerta_ciudadana/data/nearby_reports_store.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  final start = DateTime.utc(2026, 10, 15, 10);
  Incident entry(String id, {int seconds = 10, String status = 'pending'}) =>
      Incident(
        id: id,
        type: 'Robo',
        place: 'Comunidad',
        description: '',
        latitude: -8.11,
        longitude: -79.02,
        createdAt: start.add(Duration(seconds: seconds)),
        remoteStatus: status,
      );

  test(
    'Alerta pendientes hasta 500 m una vez; ignora antiguos, futuros y cerrados',
    () {
      final policy = ProximityAlertPolicy(startedAt: start);
      final items = [
        entry('inside'),
        entry('boundary'),
        entry('outside'),
        entry('old', seconds: -1),
        entry('future', seconds: 100),
        entry('closed', status: 'closed'),
        entry('discarded', status: 'discarded'),
      ];
      double distance(Incident i) => i.id == 'boundary'
          ? 500
          : i.id == 'outside'
          ? 501
          : 100;
      expect(
        policy
            .collect(items, distance, start.add(const Duration(seconds: 20)))
            .map((i) => i.id),
        ['inside', 'boundary'],
      );
      expect(
        policy.collect(items, distance, start.add(const Duration(seconds: 20))),
        isEmpty,
      );
    },
  );

  test(
    'Acercarse permite avisar un incidente reciente antes fuera del radio',
    () {
      final policy = ProximityAlertPolicy(startedAt: start);
      final item = entry('walk');
      final now = start.add(const Duration(minutes: 1));
      expect(policy.collect([item], (_) => 600, now), isEmpty);
      expect(policy.collect([item], (_) => 400, now), [item]);
      expect(
        ProximityAlertPolicy(
          startedAt: start,
        ).collect([item], (_) => 100, start.add(const Duration(minutes: 16))),
        isEmpty,
      );
    },
  );

  testWidgets('Consulta periódicamente sin movimiento y se pausa al salir', (
    tester,
  ) async {
    var calls = 0;
    final store = NearbyReportsStore(
      fetch: (_, _) async {
        calls++;
        return [];
      },
    )..pollContinuously = true;
    store.position = Position(
      latitude: -8.11,
      longitude: -79.02,
      timestamp: start,
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
    await store.refresh();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(calls, 2);
    store.setActive(false);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    store.dispose();
  });

  testWidgets(
    'Detalle de un pendiente muestra ubicación y estado sin pedir fotos privadas',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyIncidentPage(incident: entry('pending'), distance: 250),
        ),
      );
      expect(find.text('Pendiente de corroboración'), findsOneWidget);
      expect(find.text('250 m de tu ubicación actual'), findsOneWidget);
      expect(find.text('-8.110000, -79.020000'), findsOneWidget);
      expect(find.textContaining('No confirma'), findsOneWidget);
    },
  );
}
