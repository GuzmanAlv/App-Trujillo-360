import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/models/demo_profile.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/models/report.dart';
import 'package:alerta_ciudadana/ui/incident_details.dart';
import 'package:alerta_ciudadana/ui/map_panel.dart';

Report report(
  String id,
  DemoProfile profile, {
  String type = 'Robo',
  double latitude = -8.1116,
  double longitude = -79.0288,
  int seconds = 0,
}) => Report(
  id: id,
  reporterId: profile.id,
  type: type,
  place: 'Mercado de prueba',
  description: 'Observación de prueba',
  latitude: latitude,
  longitude: longitude,
  createdAt: DateTime.utc(2026, 9, 30, 12).add(Duration(seconds: seconds)),
);

void main() {
  late SharedPreferences preferences;
  late IncidentStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = IncidentStore(preferences)..load();
  });
  tearDown(() => store.dispose());

  Future<void> add(String id, DemoProfile profile, {int seconds = 0}) async {
    store.selectProfile(profile);
    expect(await store.add(report(id, profile, seconds: seconds)), isTrue);
  }

  test('Tres perfiles distintos publican un solo caso sin verificar', () async {
    await add('1', DemoProfile.neighbor1);
    expect(store.mapItems, isEmpty);
    await add('2', DemoProfile.neighbor2, seconds: 60);
    expect(store.mapItems, isEmpty);
    await add('3', DemoProfile.neighbor3, seconds: 120);
    expect(store.items, hasLength(1));
    expect(store.mapItems.single.reporterCount, 3);
    expect(store.mapItems.single.status, VerificationStatus.unverified);
  });

  test('Repetir reportes del mismo perfil no suma personas', () async {
    for (var i = 0; i < 3; i++) {
      await add('$i', DemoProfile.neighbor1, seconds: i);
    }
    expect(store.items.single.reports, hasLength(3));
    expect(store.items.single.reporterCount, 1);
    expect(store.mapItems, isEmpty);
    expect(await store.add(report('0', DemoProfile.neighbor1)), isFalse);
  });

  test('Categoría, zona y tiempo separan hechos distintos', () async {
    await add('1', DemoProfile.neighbor1);
    store.selectProfile(DemoProfile.neighbor2);
    expect(
      await store.add(
        report('category', DemoProfile.neighbor2, type: 'Agresión'),
      ),
      isTrue,
    );
    expect(
      await store.add(report('far', DemoProfile.neighbor2, latitude: -8.12)),
      isTrue,
    );
    expect(
      await store.add(report('late', DemoProfile.neighbor2, seconds: 1801)),
      isTrue,
    );
    expect(store.items, hasLength(4));
    expect(store.mapItems, isEmpty);
  });

  test(
    'Ventana y radio tienen límites definidos desde el primer reporte',
    () async {
      await add('1', DemoProfile.neighbor1);
      final incident = store.items.single;
      expect(
        store.matches(
          incident,
          report('edge', DemoProfile.neighbor2, seconds: 1800),
        ),
        isTrue,
      );
      expect(
        store.matches(
          incident,
          report('after', DemoProfile.neighbor2, seconds: 1801),
        ),
        isFalse,
      );
      expect(
        store.matches(
          incident,
          report('before', DemoProfile.neighbor2, seconds: -1),
        ),
        isFalse,
      );
      expect(
        store.matches(
          incident,
          report('near', DemoProfile.neighbor2, latitude: -8.11026),
        ),
        isTrue,
      );
      expect(
        store.matches(
          incident,
          report('far', DemoProfile.neighbor2, latitude: -8.11024),
        ),
        isFalse,
      );
      store.selectProfile(DemoProfile.neighbor2);
      await store.add(
        report('near', DemoProfile.neighbor2, latitude: -8.1107, seconds: 1700),
      );
      store.selectProfile(DemoProfile.neighbor3);
      await store.add(
        report(
          'chain',
          DemoProfile.neighbor3,
          latitude: -8.1098,
          seconds: 1900,
        ),
      );
      expect(store.items, hasLength(2));
    },
  );

  test('Solo el administrador revisa y requiere motivo', () async {
    await add('1', DemoProfile.neighbor1);
    final id = store.items.single.id;
    expect(
      await store.review(id, VerificationStatus.verified, 'Evidencia'),
      isFalse,
    );
    expect(store.mapItems, isEmpty);
    store.selectProfile(DemoProfile.administrator);
    expect(await store.review(id, VerificationStatus.verified, '  '), isFalse);
    expect(
      await store.review(
        id,
        VerificationStatus.verified,
        'Revisión de evidencia de prueba',
      ),
      isTrue,
    );
    expect(store.mapItems.single.status, VerificationStatus.verified);
    expect(store.items.single.reviewedBy, 'demo-admin');
    expect(store.items.single.reviewedAt, isNotNull);
    expect(
      await store.add(report('admin', DemoProfile.administrator)),
      isFalse,
    );
  });

  test('Descartar oculta el caso incluso con nuevos reportes', () async {
    await add('1', DemoProfile.neighbor1);
    await add('2', DemoProfile.neighbor2);
    await add('3', DemoProfile.neighbor3);
    final id = store.items.single.id;
    store.selectProfile(DemoProfile.administrator);
    expect(
      await store.review(
        id,
        VerificationStatus.dismissed,
        'No se corroboró el hecho',
      ),
      isTrue,
    );
    await add('4', DemoProfile.neighbor4);
    expect(store.items.single.reporterCount, 4);
    expect(store.mapItems, isEmpty);
    expect(store.items.single.status, VerificationStatus.dismissed);
  });

  test('Persisten agrupación, autores y revisión tras reiniciar', () async {
    await add('1', DemoProfile.neighbor1);
    await add('2', DemoProfile.neighbor2);
    store.selectProfile(DemoProfile.administrator);
    await store.review(
      store.items.single.id,
      VerificationStatus.verified,
      'Prueba',
    );
    final restored = IncidentStore(preferences)..load();
    addTearDown(restored.dispose);
    expect(restored.error, isNull);
    expect(restored.mapItems.single.reporterCount, 2);
    expect(restored.mapItems.single.reviewReason, 'Prueba');
    expect(restored.mapItems.single.reviewedAt, store.items.single.reviewedAt);
  });

  test(
    'Conserva v1 sin atribuir autores ficticios ni inflar el conteo',
    () async {
      final legacy = jsonEncode([
        report('old', DemoProfile.neighbor1).toJson()..remove('reporterId'),
      ]);
      await preferences.setString(IncidentStore.legacyKey, legacy);
      store.load();
      expect(store.items.single.reports.single.reporterId, 'legacy');
      expect(store.items.single.reporterCount, 0);
      expect(store.mapItems, isEmpty);
      await add('new', DemoProfile.neighbor1);
      final restored = IncidentStore(preferences)..load();
      addTearDown(restored.dispose);
      expect(restored.items.single.reports, hasLength(2));
      expect(restored.items.single.reporterCount, 1);
      expect(preferences.getString(IncidentStore.legacyKey), legacy);
    },
  );

  test('Datos corruptos v1 bloquean escrituras sin sobrescribirlos', () async {
    await preferences.setString(IncidentStore.legacyKey, 'invalid');
    store.load();
    expect(store.error, isNotNull);
    expect(await store.add(report('new', DemoProfile.neighbor1)), isFalse);
    expect(preferences.getString(IncidentStore.legacyKey), 'invalid');
    expect(preferences.containsKey(IncidentStore.key), isFalse);
  });

  test(
    'Cada vecino consulta sus casos, incluidos los que aún no son visibles',
    () async {
      await add('1', DemoProfile.neighbor1);
      store.selectProfile(DemoProfile.neighbor2);
      expect(store.ownItems, isEmpty);
      store.selectProfile(DemoProfile.neighbor1);
      expect(store.ownItems, hasLength(1));
      expect(store.mapItems, isEmpty);
    },
  );

  testWidgets('El mapa recibe solo casos elegibles y ciudadanos no revisan', (
    tester,
  ) async {
    await add('1', DemoProfile.neighbor1);
    await tester.pumpWidget(TrujilloApp(store: store));
    expect(tester.widget<MapPanel>(find.byType(MapPanel)).incidents, isEmpty);
    expect(find.text('Revisión'), findsNothing);
    await add('2', DemoProfile.neighbor2);
    await add('3', DemoProfile.neighbor3);
    await tester.pump();
    expect(
      tester.widget<MapPanel>(find.byType(MapPanel)).incidents,
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Administrador verifica desde el primer reporte en la interfaz', (
    tester,
  ) async {
    await add('1', DemoProfile.neighbor1);
    store.selectProfile(DemoProfile.administrator);
    await tester.pumpWidget(TrujilloApp(store: store));
    expect(find.text('Revisión'), findsOneWidget);
    await tester.tap(find.text('Revisión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robo · Mercado de prueba').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Evidencia de prueba');
    await tester.ensureVisible(find.text('Verificar caso'));
    await tester.tap(find.text('Verificar caso'));
    await tester.pumpAndSettle();
    expect(store.mapItems.single.status, VerificationStatus.verified);
    expect(find.text('Verificado'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El detalle ciudadano no ofrece acciones de administrador', (
    tester,
  ) async {
    await add('1', DemoProfile.neighbor1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showIncidentDetails(context, store, store.items.single.id),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Verificar caso'), findsNothing);
    expect(find.text('Descartar caso'), findsNothing);
    expect(find.textContaining('Aún no aparece'), findsOneWidget);
  });
}
