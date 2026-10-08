import 'package:alerta_ciudadana/ui/community_photo_view.dart';
import 'package:alerta_ciudadana/ui/report_marker.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/data/map_incidents_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/ui/community_incident_page.dart';

Incident report(
  String id, {
  String status = 'corroborated',
  int count = 3,
  bool review = false,
}) => Incident(
  id: id,
  type: 'Robo',
  place: 'Comunidad',
  description: '',
  latitude: -8.11,
  longitude: -79.02,
  createdAt: DateTime(2026),
  remoteStatus: status,
  corroborationCount: count,
  needsReview: review,
);
void main() {
  testWidgets('Las fotos se pueden ampliar y reintentar sin recargar el mapa', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() => renderLocationDot());
    var failed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityPhotoView(
            incidentId: 'group',
            photoId: 'photo',
            fetch: (_, _) async {
              if (failed) throw StateError('Unavailable');
              return bytes!;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar foto'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('Reintentar foto'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  test(
    'El mapa conserva marcadores al cargar y reutiliza áreas recientes',
    () async {
      var calls = 0;
      final pending = Completer<List<Incident>>();
      final store = MapIncidentsStore(
        debounce: Duration.zero,
        fetch: (_) async {
          calls++;
          return calls == 1 ? [report('retained')] : pending.future;
        },
      );
      final first = LatLngBounds(
        southwest: const LatLng(-8.12, -79.03),
        northeast: const LatLng(-8.10, -79.01),
      );
      final second = LatLngBounds(
        southwest: const LatLng(-8.12, -79.03),
        northeast: const LatLng(-8.09, -79.01),
      );
      store.setBounds(first);
      await Future<void>.delayed(Duration.zero);
      expect(store.items.single.id, 'retained');
      store.setBounds(second);
      expect(store.items.single.id, 'retained');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      store.setBounds(first);
      expect(store.loading, isFalse);
      expect(store.items.single.id, 'retained');
      expect(calls, 2);
      pending.complete([report('stale')]);
      await Future<void>.delayed(Duration.zero);
      expect(store.items.single.id, 'retained');
      store.setActive(false);
      store.clearSession();
      expect(store.items, isEmpty);
      store.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
      store.dispose();
    },
  );

  test(
    'El mapa oculta pendientes, grupos insuficientes y coincidencias ambiguas',
    () {
      final store = MapIncidentsStore();
      store.items = [
        report('ok'),
        report('pending', status: 'pending'),
        report('two', count: 2),
        report('ambiguous', review: true),
        report('verified', status: 'verified'),
      ];
      expect(store.filtered('Todos').map((i) => i.id), ['ok', 'verified']);
      expect(store.filtered('Auxilio'), isEmpty);
      store.dispose();
    },
  );
  testWidgets('El detalle muestra todos los aportes y actualiza los nuevos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityIncidentPage(
          incident: report('group'),
          fetchPhotos: (_) async => [],
          fetch: (_) async => List.generate(count, (i) => report('r$i')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 reportes de cuentas diferentes'), findsOneWidget);
    expect(find.text('Reporte 3 · Robo'), findsOneWidget);
    count = 4;
    await tester.ensureVisible(find.text('Actualizar aportes'));
    await tester.tap(find.text('Actualizar aportes'));
    await tester.pumpAndSettle();
    expect(find.text('4 reportes de cuentas diferentes'), findsOneWidget);
    expect(find.text('Reporte 4 · Robo'), findsOneWidget);
  });
  testWidgets('Un error permite reintentar sin mostrar aportes falsos', (
    tester,
  ) async {
    var failed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityIncidentPage(
          incident: report('group'),
          fetchPhotos: (_) async => [],
          fetch: (_) async {
            if (failed) throw StateError('Unavailable');
            return [report('one'), report('two'), report('three')];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Volver a intentar'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('Volver a intentar'));
    await tester.pumpAndSettle();
    expect(find.text('3 reportes de cuentas diferentes'), findsOneWidget);
  });
}
