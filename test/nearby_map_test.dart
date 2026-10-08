import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:alerta_ciudadana/core/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/data/nearby_reports_store.dart';
import 'package:alerta_ciudadana/data/map_incidents_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/location_service.dart';
import 'package:alerta_ciudadana/ui/map_panel.dart';

Position position(double latitude) => Position(
  latitude: latitude,
  longitude: -79.02,
  timestamp: DateTime(2026),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
);

class FakeLocation extends LocationService {
  final events = StreamController<Position>.broadcast();
  @override
  Future<Position> current() async => position(-8.11);
  @override
  Stream<Position> watch() => events.stream;
}

Incident incident(String id, double lat) => Incident(
  id: id,
  type: 'Robo',
  place: 'Comunidad',
  description: '',
  latitude: lat,
  longitude: -79.02,
  createdAt: DateTime(2026),
  remoteStatus: 'corroborated',
  corroborationCount: 3,
);
void main() {
  testWidgets(
    'Mapa explora incidentes lejanos y Cerca de mí conserva su radio de 1 km',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final location = FakeLocation();
      final nearby = NearbyReportsStore(
        locationService: location,
        fetch: (_, _) async => [incident('near', -8.1101), incident('far', -9)],
      );
      final mapFeed = MapIncidentsStore(
        debounce: Duration.zero,
        fetch: (_) async => [incident('near', -8.1101), incident('far', -9)],
      );
      final local = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(store: local, nearby: nearby, mapIncidents: mapFeed),
        ),
      );
      mapFeed.setBounds(
        LatLngBounds(
          southwest: const LatLng(-9.1, -79.1),
          northeast: const LatLng(-8, -79),
        ),
      );
      await nearby.start();
      await tester.pumpAndSettle();
      var map = tester.widget<MapPanel>(find.byType(MapPanel));
      expect(map.incidents.map((i) => i.id), ['near', 'far']);
      expect(map.currentLocation, const LatLng(-8.11, -79.02));
      expect(map.locationRadius, 500);
      expect(NearbyReportsStore.searchRadius, 1000);
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(find.text('Robo · Comunidad'), findsOneWidget);
      expect(location.events.hasListener, isTrue);
      await tester.tap(find.text('Mapa'));
      await tester.pumpAndSettle();
      map = tester.widget<MapPanel>(find.byType(MapPanel));
      expect(map.incidents.map((i) => i.id), ['near', 'far']);
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      expect(location.events.hasListener, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await location.events.close();
      local.dispose();
    },
  );
  testWidgets(
    'Cerca de mí combina corroboración, categoría y 1 km sin afectar Mis reportes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final location = FakeLocation();
      Incident entry(
        String id, {
        String type = 'Robo',
        String status = 'corroborated',
        int count = 3,
        double lat = -8.1101,
      }) => Incident.fromJson({
        ...incident(id, lat).toJson(),
        'place': id,
        'type': type,
        'remoteStatus': status,
        'corroborationCount': count,
      });
      final nearby = NearbyReportsStore(
        locationService: location,
        fetch: (_, _) async => [
          entry('pendiente', status: 'pending', count: 1),
          entry('confirmado'),
          entry('auxilio', type: 'Auxilio'),
          entry('lejano', lat: -9),
        ],
      );
      final local = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            store: local,
            nearby: nearby,
            mapIncidents: MapIncidentsStore(fetch: (_) async => []),
          ),
        ),
      );
      await nearby.start();
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(find.text('Robo · pendiente'), findsOneWidget);
      expect(find.text('Robo · confirmado'), findsOneWidget);
      expect(find.text('Auxilio · auxilio'), findsOneWidget);
      expect(find.text('Robo · lejano'), findsNothing);
      await tester.tap(find.text('Corroborados'));
      await tester.pumpAndSettle();
      expect(find.text('Robo · pendiente'), findsNothing);
      expect(find.text('Robo · confirmado'), findsOneWidget);
      await tester.tap(find.text('Robo'));
      await tester.pumpAndSettle();
      expect(find.text('Auxilio · auxilio'), findsNothing);
      expect(find.text('Robo · confirmado'), findsOneWidget);
      final statusFilter = find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton<bool> &&
            widget.segments.any(
              (s) =>
                  s.label is Text && (s.label as Text).data == 'Corroborados',
            ),
      );
      await tester.tap(
        find.descendant(of: statusFilter, matching: find.text('Todos')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Robo · pendiente'), findsOneWidget);
      await tester.tap(find.text('Mis reportes'));
      await tester.pumpAndSettle();
      expect(find.text('Corroborados'), findsNothing);
      expect(find.text('Inicia sesión para ver tus reportes.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await location.events.close();
      local.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('Tocar el mapa mueve solo el círculo y volver restaura el GPS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var locateCalls = 0;
    const gps = LatLng(-8.11, -79.02);
    const chosen = LatLng(-8.15, -79.05);
    await tester.pumpWidget(
      MaterialApp(
        home: MapPanel(
          currentLocation: gps,
          locationRadius: 500,
          onLocate: () => locateCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(MapPanel));
    await tester.runAsync(() async {
      await state.prepareLocationIcon();
    });
    await tester.pumpAndSettle();
    GoogleMap renderedMap() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final root =
          state.build(tester.element(find.byType(MapPanel))) as ClipRRect;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      return ((root.child as Stack).children.first as Positioned).child
          as GoogleMap;
    }

    var map = renderedMap();
    expect(map.circles.single.radius, 500);
    expect(map.circles.single.center, gps);
    map.onTap!(chosen);
    await tester.pumpAndSettle();
    map = renderedMap();
    expect(map.circles.single.center, chosen);
    expect(
      map.markers
          .singleWhere((m) => m.markerId.value == 'exploration_center')
          .position,
      chosen,
    );
    expect(
      map.markers
          .singleWhere((m) => m.markerId.value == 'my_location')
          .position,
      gps,
    );
    state.locate();
    await tester.pumpAndSettle();
    expect(renderedMap().circles.single.center, gps);
    expect(
      renderedMap().markers.where(
        (m) => m.markerId.value == 'exploration_center',
      ),
      isEmpty,
    );
    expect(locateCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  }, skip: !AppConfig.mapsEnabled);
  test(
    'Una respuesta anterior no repuebla incidentes tras cambiar de cuenta',
    () async {
      final location = FakeLocation();
      final response = Completer<List<Incident>>();
      final nearby = NearbyReportsStore(
        locationService: location,
        fetch: (_, _) => response.future,
      );
      await nearby.start();
      nearby.setActive(false);
      nearby.clearSession();
      response.complete([incident('previous-account', -8.11)]);
      await Future<void>.delayed(Duration.zero);
      expect(nearby.filtered('Todos'), isEmpty);
      nearby.dispose();
      await location.events.close();
    },
  );
  test(
    'El círculo sigue la ubicación y no aparece sin GPS ni en el selector del formulario',
    () {
      expect(locationHighlight(null, 1000), isEmpty);
      expect(locationHighlight(const LatLng(-8.11, -79.02), 0), isEmpty);
      final circle = locationHighlight(
        const LatLng(-8.12, -79.02),
        1000,
      ).single;
      expect(circle.center, const LatLng(-8.12, -79.02));
      expect(circle.radius, 1000);
    },
  );
  test('El mapa descarta respuestas de zonas anteriores al moverlo', () async {
    final first = Completer<List<Incident>>();
    final second = Completer<List<Incident>>();
    var count = 0;
    final map = MapIncidentsStore(
      debounce: Duration.zero,
      fetch: (_) => ++count == 1 ? first.future : second.future,
    );
    map.setBounds(
      LatLngBounds(
        southwest: const LatLng(-9, -80),
        northeast: const LatLng(-8, -79),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    map.setBounds(
      LatLngBounds(
        southwest: const LatLng(-10, -80),
        northeast: const LatLng(-9, -79),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    second.complete([incident('new-zone', -9.5)]);
    await Future<void>.delayed(Duration.zero);
    first.complete([incident('old-zone', -8.5)]);
    await Future<void>.delayed(Duration.zero);
    expect(map.items.single.id, 'new-zone');
    map.dispose();
  });
}
