import 'package:alerta_ciudadana/ui/reports_panel.dart';
import 'package:alerta_ciudadana/data/nearby_reports_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'nearby_map_test.dart' show FakeLocation;

void main() {
  testWidgets('Cerca de mí solo incluye SOS confirmados y resueltos a 1 km', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    Incident sos(
      String id,
      String type, {
      String status = 'verified',
      bool isSos = true,
      String attention = 'none',
      double lat = -8.11,
      DateTime? date,
      DateTime? closed,
    }) => Incident(
      id: id,
      type: type,
      place: '',
      description: 'Descripción pública',
      latitude: lat,
      longitude: -79.02,
      createdAt: date ?? now,
      remoteStatus: status,
      isSos: isSos,
      attention: attention,
      resolvedAt: closed,
    );
    final location = FakeLocation();
    final nearby = NearbyReportsStore(
      locationService: location,
      fetch: (_, _) async => [
        sos('own', 'Robo'),
        sos('other', 'Auxilio', attention: 'en_route'),
        sos(
          'resolved',
          'Agresión',
          status: 'closed',
          attention: 'resolved',
          date: now.subtract(const Duration(days: 8)),
          closed: now,
        ),
        sos('legacy', 'Riesgo', isSos: false),
        sos('far', 'Riesgo', lat: -8.13),
        sos('pending', 'Robo', status: 'pending'),
        sos('discarded', 'Auxilio', status: 'discarded'),
        sos('old', 'Riesgo', date: now.subtract(const Duration(days: 8))),
        sos(
          'expired',
          'Riesgo',
          status: 'closed',
          closed: now.subtract(const Duration(days: 7)),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ReportsPanel(
              filter: 'Todos',
              active: true,
              nearby: nearby,
              onNearbySelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mis Solicitudes'), findsOneWidget);
    expect(find.text('Reportes anteriores'), findsNothing);
    expect(find.text('Mis solicitudes de ayuda'), findsNothing);
    await nearby.start();
    await tester.tap(find.text('Cerca de mí'));
    await tester.pumpAndSettle();
    expect(find.text('SOS · Robo'), findsOneWidget);
    expect(find.text('SOS · Auxilio'), findsOneWidget);
    expect(find.text('SOS · Agresión'), findsOneWidget);
    expect(find.text('SOS · Riesgo'), findsNothing);
    expect(find.textContaining('Resuelto'), findsOneWidget);
    await tester.tap(find.text('SOS · Agresión'));
    await tester.pumpAndSettle();
    expect(find.text('SOS cerca de ti'), findsOneWidget);
    expect(find.text('Resuelto'), findsOneWidget);
    expect(find.text('Pendiente de corroboración'), findsNothing);
    Navigator.of(tester.element(find.text('SOS cerca de ti'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mis Solicitudes'));
    await tester.pumpAndSettle();
    expect(find.text('SOS · Robo'), findsNothing);
    expect(find.text('SOS · Auxilio'), findsNothing);
    expect(
      find.text('Inicia sesión para ver tu historial SOS.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    nearby.dispose();
    await location.events.close();
  });
}
