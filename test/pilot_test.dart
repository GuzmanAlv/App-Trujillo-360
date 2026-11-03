import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/pilot/pilot_home.dart';
import 'package:alerta_ciudadana/pilot/pilot_store.dart';

void main() {
  late PilotStore store;
  final now = DateTime.now();
  Incident incident(String id, {DateTime? at}) => Incident(
    id: id,
    type: 'Robo',
    place: 'Puerta universidad',
    description: 'Descripción privada',
    latitude: -8.11,
    longitude: -79.02,
    createdAt: at ?? now,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'trujillo360.local_reports.v1': 'datos anteriores',
    });
    store = PilotStore(await SharedPreferences.getInstance())..load();
  });
  test(
    'Urgencia alta no publica; decisión explícita, motivo y seguimiento persistido',
    () async {
      expect(
        await store.submit(incident('help'), help: true, priority: 'Alta'),
        isTrue,
      );
      expect(store.cases.single.publicAt(now), isFalse);
      expect(
        await store.update(
          'help',
          stage: 'Cerrada',
          reason: 'Cerrar sin revisar',
          priority: 'Alta',
        ),
        isFalse,
      );
      expect(
        await store.update(
          'help',
          stage: 'En revisión',
          reason: '',
          priority: 'Alta',
          publish: true,
        ),
        isFalse,
      );
      expect(
        await store.update(
          'help',
          stage: 'En revisión',
          reason: 'Revisión local del punto',
          priority: 'Media',
          publish: true,
        ),
        isTrue,
      );
      expect(store.cases.single.publicAt(now), isTrue);
      expect(
        await store.update(
          'help',
          stage: 'Acción registrada',
          reason: 'Se probó el contacto en simulación',
          priority: 'Media',
        ),
        isTrue,
      );
      expect(
        await store.update(
          'help',
          stage: 'Cerrada',
          reason: 'Fin de la simulación',
          priority: 'Media',
        ),
        isTrue,
      );
      final restored = PilotStore(store.preferences)..load();
      expect(restored.cases.single.events.length, 4);
      expect(restored.cases.single.publicAt(now), isFalse);
      expect(restored.cases.single.publicAt(now, historical: true), isTrue);
      expect(
        await store.update(
          'help',
          stage: 'En revisión',
          reason: 'No debe reabrir',
          priority: 'Alta',
        ),
        isFalse,
      );
      expect(
        store.preferences.getString('trujillo360.local_reports.v1'),
        'datos anteriores',
      );
    },
  );
  test(
    'Caducidad retira alertas, no cierra ayuda; descarte retira historial público',
    () async {
      await store.submit(
        incident('old', at: now.subtract(const Duration(days: 8))),
        help: true,
        priority: 'Alta',
      );
      await store.update(
        'old',
        stage: 'En revisión',
        reason: 'Caso antiguo revisado',
        priority: 'Alta',
        publish: true,
      );
      expect(store.cases.single.publicAt(now), isFalse);
      expect(store.cases.single.publicAt(now, historical: true), isTrue);
      expect(store.cases.single.terminal, isFalse);
      await store.update(
        'old',
        stage: 'Descartada',
        reason: 'Era un caso de prueba duplicado',
        priority: 'Baja',
      );
      expect(store.cases.single.publicAt(now, historical: true), isFalse);
    },
  );
  test(
    'No publica futuros ni mayores de siete días; franja según hora del hecho',
    () async {
      final c = PilotCase(
        incident: incident('future', at: now.add(const Duration(minutes: 1))),
        help: false,
        priority: 'Baja',
        receivedAt: now,
        published: true,
      );
      expect(c.publicAt(now, historical: true), isFalse);
      expect(
        c.publicAt(now.add(const Duration(days: 91)), historical: true),
        isFalse,
      );
      expect(matchesHour(DateTime(2026, 11, 1, 18), 3), isTrue);
      expect(matchesHour(DateTime(2026, 11, 1, 12), 1), isFalse);
    },
  );
  test('Datos dañados no se sobrescriben', () async {
    await store.preferences.setString(PilotStore.storageKey, 'corrupto');
    final broken = PilotStore(store.preferences)..load();
    expect(broken.error, isNotNull);
    expect(
      await broken.submit(incident('new'), help: false, priority: 'Baja'),
      isFalse,
    );
    expect(store.preferences.getString(PilotStore.storageKey), 'corrupto');
  });
  testWidgets(
    'Ciudadano y operador muestran seguimiento; público oculta datos privados',
    (tester) async {
      await store.submit(incident('one'), help: true, priority: 'Alta');
      await tester.pumpWidget(MaterialApp(home: PilotHome(store: store)));
      expect(
        find.text('PRUEBA LOCAL · No contacta a seguridad ciudadana'),
        findsOneWidget,
      );
      await tester.tap(find.text('Operador'));
      await tester.pumpAndSettle();
      expect(find.text('1 solicitudes de ayuda abiertas'), findsOneWidget);
      await tester.tap(find.text('Robo · Puerta universidad'));
      await tester.pumpAndSettle();
      expect(find.text('Descripción privada'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await store.update(
        'one',
        stage: 'En revisión',
        reason: 'Revisado para publicación',
        priority: 'Alta',
        publish: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PilotDetails(
            id: 'one',
            store: store,
            operator: false,
            publicView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Descripción privada'), findsNothing);
      expect(find.text('Seguimiento'), findsNothing);
      expect(
        find.textContaining('No es una confirmación institucional'),
        findsOneWidget,
      );
    },
  );
}
