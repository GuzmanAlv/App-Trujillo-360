import 'package:alerta_ciudadana/services/operator_route_recovery.dart';
import 'package:alerta_ciudadana/services/sos_alert_state.dart';
import 'package:alerta_ciudadana/ui/sos_overview_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test(
    'Recupera la ruta asignada tras salir/entrar sin recalcular en cada consulta',
    () {
      final recovery = OperatorRouteRecovery();
      final rows = [
        {
          'id': 'case',
          'can_track': true,
          'decision': 'confirmed',
          'attention': 'en_route',
        },
      ];
      expect(recovery.recover('op', rows, null), 'case');
      expect(recovery.recover('op', rows, 'case'), isNull);
      expect(
        recovery.recover('op', rows, null),
        isNull,
      ); // Manual removal stays removed.
      recovery.reset();
      expect(recovery.recover('op', rows, null), 'case');
      recovery.reset();
      expect(
        recovery.recover('other', [
          {...rows.first, 'can_track': false},
        ], null),
        isNull,
      );
      expect(
        recovery.recover('op', [
          {...rows.first, 'attention': 'on_scene'},
        ], null),
        isNull,
      );
    },
  );
  test('SOS lejanos permanecen visibles pero no producen alarmas', () {
    expect(
      needsOperatorSosAlert({'decision': 'pending', 'alert_in_range': false}),
      isFalse,
    );
    expect(
      needsOperatorSosAlert({'decision': 'pending', 'alert_in_range': true}),
      isTrue,
    );
  });
  test('El encuadre incluye todos los SOS dispersos', () {
    const points = [
      LatLng(-8.1, -79.03),
      LatLng(-8.3, -79.1),
      LatLng(-8.05, -78.9),
    ];
    final bounds = sosOverviewBounds(points)!;
    expect(points.every(bounds.contains), isTrue);
    expect(sosOverviewBounds([]), isNull);
  });
  testWidgets('El contador ofrece ver todos los SOS y no solo los cercanos', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SosOverviewButton(
              count: 203,
              onPressed: () => opened = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('203'), findsOneWidget);
    await tester.tap(find.byTooltip('Todos los SOS activos · 203'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
