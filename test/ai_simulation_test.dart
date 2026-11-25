import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:alerta_ciudadana/ui/ai_simulation_panel.dart';

Map<String, dynamic> caseItem({String stage = 'Recibida'}) => {
  'id': 'case-1',
  'cameraId': 'test-camera',
  'latitude': -8.11,
  'longitude': -79.02,
  'confidence': .91,
  'modelVersion': 'pilot',
  'stage': stage,
  'receivedAt': '2026-11-25T01:00:00Z',
  'events': [
    {
      'stage': stage,
      'reason': 'Evento de prueba',
      'at': '2026-11-25T01:00:00Z',
    },
  ],
};

Widget map(Set<Marker> markers, LatLng center) =>
    Text('Mapa con ${markers.length} marcadores');

void main() {
  testWidgets(
    'Operadores sin permiso de cámara ven mapa y casos de simulación',
    (tester) async {
      Set<Marker> shown = {};
      Future<dynamic> request(
        String method,
        String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
      }) async {
        if (path.endsWith('/config')) return {'enabled': false};
        return [caseItem()];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: AiSimulationPanel(
            request: request,
            mapBuilder: (markers, center) {
              shown = markers;
              return map(markers, center);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preparar cámara de prueba'), findsNothing);
      expect(find.text('Mapa con 1 marcadores'), findsOneWidget);
      expect(shown.single.position, const LatLng(-8.11, -79.02));
      expect(shown.single.infoWindow.title, 'Simulación IA · Posible forcejeo');
      shown.single.onTap!();
      await tester.pumpAndSettle();
      expect(find.text('Atender simulación IA'), findsOneWidget);
      expect(find.text('Estado: Recibida'), findsOneWidget);
      expect(find.text('Historial de atención'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Atención requiere motivo y solo muestra cambio confirmado por servidor',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      var fail = true;
      Set<Marker> markers = {};
      Future<dynamic> request(
        String method,
        String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
      }) async {
        if (method == 'POST') {
          writes.add(body!);
          if (fail) throw StateError('No se confirmó la atención');
          return caseItem(stage: body['stage'] as String);
        }
        if (path.endsWith('/config')) return {'enabled': false};
        return [caseItem()];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: AiSimulationPanel(
            request: request,
            mapBuilder: (next, center) {
              markers = next;
              return map(next, center);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      markers.single.onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('En revisión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar atención'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe al menos 5 caracteres.'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        'Operador revisa la escena',
      );
      await tester.tap(find.text('Guardar atención'));
      await tester.pumpAndSettle();
      expect(find.text('Estado: Recibida'), findsOneWidget);
      expect(find.text('No se confirmó la atención'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('En revisión'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Operador revisa la escena',
      );
      await tester.tap(find.text('Guardar atención'));
      await tester.pumpAndSettle();
      expect(find.text('Estado: En revisión'), findsOneWidget);
      expect(find.text('Cerrada'), findsOneWidget);
      expect(writes.last, {
        'stage': 'En revisión',
        'reason': 'Operador revisa la escena',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Cuenta autorizada prepara ubicación y puede detener sesión', (
    tester,
  ) async {
    final writes = <String>[];
    Future<dynamic> request(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? query,
    }) async {
      if (method == 'POST') {
        writes.add(path);
        if (path.endsWith('/stop')) return {'status': 'stopped'};
        expect(body, {
          'cameraId': 'test-camera',
          'latitude': -8.11,
          'longitude': -79.02,
        });
        return {
          'id': 'session-1',
          'expiresAt': '2026-11-25T02:00:00Z',
          'workerToken': 'temporary-scoped-token',
        };
      }
      if (path.endsWith('/config')) {
        return {'enabled': true, 'cameraId': 'test-camera'};
      }
      return <dynamic>[];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: AiSimulationPanel(request: request, mapBuilder: map),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preparar cámara de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear sesión de simulación'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.enterText(find.byType(TextFormField).at(0), '-8.11');
    await tester.enterText(find.byType(TextFormField).at(1), '-79.02');
    await tester.tap(find.text('Crear sesión de simulación'));
    await tester.pumpAndSettle();
    expect(find.text('session-1'), findsOneWidget);
    expect(find.text('temporary-scoped-token'), findsNothing);
    await tester.ensureVisible(find.text('Detener sesión de cámara'));
    await tester.tap(find.text('Detener sesión de cámara'));
    await tester.pumpAndSettle();
    expect(writes.last, '/operator/ai/simulation/sessions/session-1/stop');
    expect(find.text('Sesión de cámara detenida.'), findsOneWidget);
    expect(find.text('Copiar acceso temporal para la laptop'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Actualización periódica se detiene en segundo plano y al cerrar',
    (tester) async {
      var reads = 0;
      Future<dynamic> request(
        String method,
        String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
      }) async {
        reads++;
        return path.endsWith('/config') ? {'enabled': false} : <dynamic>[];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: AiSimulationPanel(request: request, mapBuilder: map),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(reads, 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, 6);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
      expect(reads, 6);
    },
  );
}
