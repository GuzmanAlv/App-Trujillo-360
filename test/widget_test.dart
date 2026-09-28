import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Trujillo 360'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
