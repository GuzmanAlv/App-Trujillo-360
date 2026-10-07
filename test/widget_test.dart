import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Persiste reportes al reconstruir el almacén', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = IncidentStore(preferences)..load();
    expect(
      await store.add(
        Incident(
          id: '1',
          type: 'Robo',
          place: 'Prueba',
          description: '',
          latitude: -8.11,
          longitude: -79.02,
          createdAt: DateTime(2026),
        ),
      ),
      isTrue,
    );
    expect((IncidentStore(preferences)..load()).items.single.place, 'Prueba');
  });
  test('Conserva datos dañados sin sobrescribirlos', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(IncidentStore.key, 'invalid');
    final store = IncidentStore(preferences)..load();
    expect(store.error, isNotNull);
    expect(
      await store.add(
        Incident(
          id: '1',
          type: 'Robo',
          place: 'Prueba',
          description: '',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime(2026),
        ),
      ),
      isFalse,
    );
    expect(preferences.getString(IncidentStore.key), 'invalid');
  });
  testWidgets('Inicia sin claves externas', (tester) async {
    final store = IncidentStore(await SharedPreferences.getInstance())..load();
    await tester.pumpWidget(TrujilloApp(store: store));
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Separa reportes cercanos de los propios sin necesitar GPS para los propios',
    (tester) async {
      final store = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      await store.add(
        Incident(
          id: 'local',
          type: 'Robo',
          place: 'Mi reporte lejano',
          description: '',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime(2026),
        ),
      );
      await store.add(
        Incident(
          id: 'other',
          ownerUid: 'otra-cuenta',
          type: 'Robo',
          place: 'Reporte ajeno',
          description: '',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(TrujilloApp(store: store));
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(find.text('Cerca de mí'), findsOneWidget);
      expect(find.text('Activar ubicación'), findsOneWidget);
      await tester.tap(find.text('Mis reportes'));
      await tester.pumpAndSettle();
      expect(find.text('Inicia sesión para ver tus reportes.'), findsOneWidget);
      expect(find.text('Robo · Mi reporte lejano'), findsNothing);
      expect(find.text('Robo · Reporte ajeno'), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
