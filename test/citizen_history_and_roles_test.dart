import 'package:alerta_ciudadana/ui/sos_history_section.dart';
import 'package:alerta_ciudadana/ui/reports_panel.dart';
import 'package:alerta_ciudadana/ui/workflow_panel.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/data/map_incidents_store.dart';
import 'package:alerta_ciudadana/data/nearby_reports_store.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nearby_map_test.dart' show FakeLocation;

Map<String, dynamic> historyRow(int id) => {
  'id': '$id',
  'category': id == 0 ? 'Robo' : 'Auxilio',
  'attention': id == 0 ? 'resolved' : 'none',
  'decision': id == 0 ? 'confirmed' : 'pending',
  'stage': id == 0 ? 'Cerrada' : 'Recibida',
  'received_at': DateTime.now()
      .subtract(Duration(days: 60 + id))
      .toIso8601String(),
  'description': 'Caso anterior $id',
};

void main() {
  testWidgets('Historial conserva resueltos antiguos, pagina y abre detalle', (
    tester,
  ) async {
    final offsets = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SosHistorySection(
              active: true,
              filter: 'Todos',
              owner: () => 'owner',
              fetch: (offset) async {
                offsets.add(offset);
                return List.generate(
                  offset == 0 ? 50 : 2,
                  (i) => historyRow(i + offset),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Resuelto'), findsOneWidget);
    await tester.tap(find.text('SOS · Robo'));
    await tester.pumpAndSettle();
    expect(find.text('Caso anterior 0'), findsOneWidget);
    Navigator.of(tester.element(find.text('Caso anterior 0'))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cargar SOS anteriores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cargar SOS anteriores'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('Cargar SOS anteriores'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Historial sin sesión no consulta datos privados', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosHistorySection(
            active: true,
            filter: 'Todos',
            owner: () => null,
            fetch: (_) async {
              calls++;
              return [historyRow(0)];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      find.text('Inicia sesión para ver tu historial SOS.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Operador tiene mapa, operador y ajustes; ciudadano mantiene reportes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final local = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      final location = FakeLocation();
      final nearby = NearbyReportsStore(
        locationService: location,
        fetch: (_, _) async => [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            store: local,
            nearby: nearby,
            mapIncidents: MapIncidentsStore(fetch: (_) async => []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(HomePage));
      state.setState(() {
        state.operatorAllowed = true;
      });
      await tester.pumpAndSettle();
      NavigationBar nav() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        nav().destinations.cast<NavigationDestination>().map((d) => d.label),
        ['Mapa', 'Operador', 'Configuración'],
      );
      expect(find.byType(ReportsPanel), findsNothing);
      await tester.tap(find.text('Operador'));
      await tester.pumpAndSettle();
      expect(find.byType(OperatorPortal), findsOneWidget);
      expect(nav().selectedIndex, 1);
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      expect(nav().selectedIndex, 2);
      state.setState(() {
        state.operatorAllowed = false;
      });
      await tester.pumpAndSettle();
      expect(
        nav().destinations.cast<NavigationDestination>().map((d) => d.label),
        ['Mapa', 'Reportes', 'Configuración'],
      );
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Tus solicitudes SOS, incluidas las confirmadas y resueltas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Historial de SOS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await location.events.close();
      local.dispose();
    },
  );
}
