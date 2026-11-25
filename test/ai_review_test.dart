import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/ui/ai_review_panel.dart';

Map<String, dynamic> candidate(int sequence) => {
  'sequence': sequence,
  'status': 'pending',
  'cameraId': 'camera-$sequence',
  'modelVersion': 'pilot',
  'confidence': .82,
  'latitude': -8.11,
  'longitude': -79.02,
  'detectedAt': '2026-01-01T00:00:00Z',
};

void main() {
  testWidgets('Loads paginated candidates and saves a human decision', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    Future<dynamic> request(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? query,
    }) async {
      requests.add({
        'method': method,
        'path': path,
        'body': body,
        'query': query,
      });
      if (method == 'POST') {
        return {
          ...candidate(2),
          'status': 'discarded',
          'reason': body!['reason'],
          'reviewedAt': '2026-01-02T00:00:00Z',
        };
      }
      if (query?['before'] == '2') {
        return {
          'items': [candidate(1)],
          'nextCursor': null,
        };
      }
      return {
        'items': [candidate(2)],
        'nextCursor': 2,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiReviewPanel(request: request)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confianza del modelo: 82.0%'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar decisión'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe al menos 5 caracteres.'), findsOneWidget);
    expect(requests.where((e) => e['method'] == 'POST'), isEmpty);
    await tester.enterText(
      find.byType(TextFormField),
      'No hay agresión en la cámara',
    );
    await tester.tap(find.text('Guardar decisión'));
    await tester.pumpAndSettle();
    expect(find.text('Detección descartada por operador'), findsOneWidget);
    expect(requests.last['path'], '/operator/ai/candidates/2/decisions');
    await tester.ensureVisible(find.text('Cargar anteriores'));
    await tester.tap(find.text('Cargar anteriores'));
    await tester.pumpAndSettle();
    expect(requests.last['query'], {'limit': '50', 'before': '2'});
    expect(find.text('Cargar anteriores'), findsNothing);
  });

  testWidgets('A failed write never displays a saved decision', (tester) async {
    Future<dynamic> request(
      String method,
      String path, {
      Map<String, dynamic>? body,
      Map<String, String>? query,
    }) async {
      if (method == 'POST') throw StateError('No se confirmó el cambio');
      return {
        'items': [candidate(1)],
        'nextCursor': null,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiReviewPanel(request: request)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Revisado en cámara');
    await tester.tap(find.text('Guardar decisión'));
    await tester.pumpAndSettle();
    expect(
      find.text('Posible agresión · Pendiente de revisión'),
      findsOneWidget,
    );
    expect(find.text('No se confirmó el cambio'), findsOneWidget);
    expect(find.text('Detección confirmada por operador'), findsNothing);
  });
}
