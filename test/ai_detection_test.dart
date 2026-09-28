import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/data/ai_detection_store.dart';
import 'package:alerta_ciudadana/ui/ai_detection_panel.dart';

Map<String, dynamic> candidate() => {
  'schemaVersion': 1,
  'type': 'aggression_candidate',
  'id': 'event-1',
  'cameraId': 'camera-1',
  'modelVersion': 'test-model',
  'confidence': 0.82,
  'latitude': -8.11,
  'longitude': -79.02,
  'detectedAt': '2026-09-12T02:00:00Z',
};

void main() {
  test('Deduplica y conserva candidatos ante eventos inválidos', () {
    final store = AiDetectionStore();
    addTearDown(store.dispose);
    store.ingest(jsonEncode(candidate()));
    store.ingest(jsonEncode(candidate()));
    for (final patch in [
      {'confidence': 1.1},
      {'latitude': 91},
      {'schemaVersion': 2},
      {'cameraId': ''},
      {'detectedAt': '2026-09-12T02:00:00'},
    ]) {
      store.ingest(jsonEncode({...candidate(), ...patch}));
    }
    store.ingest('invalid');
    store.ingest('[]');
    expect(store.items, hasLength(1));
    expect(store.rejectedEvents, 7);
  });

  test('Limita la bandeja a los 200 candidatos más recientes', () {
    final store = AiDetectionStore();
    addTearDown(store.dispose);
    for (var i = 0; i < 201; i++) {
      store.ingest(
        jsonEncode({
          ...candidate(),
          'id': '$i',
          'detectedAt': DateTime.utc(
            2026,
          ).add(Duration(seconds: i)).toIso8601String(),
        }),
      );
    }
    expect(store.items, hasLength(200));
    expect(store.items.first.id, '200');
    expect(store.items.any((item) => item.id == '0'), isFalse);
  });

  test('Recibe eventos y expone fallos y cierre de conexión', () async {
    final store = AiDetectionStore();
    final events = StreamController<String>();
    addTearDown(store.dispose);
    await store.attach(events.stream);
    events.add(jsonEncode(candidate()));
    await Future<void>.delayed(Duration.zero);
    expect(store.items, hasLength(1));
    events.addError(StateError('connection lost'));
    await Future<void>.delayed(Duration.zero);
    expect(store.connection, AiConnection.failed);
    await events.close();
    final next = StreamController<String>();
    await store.attach(next.stream);
    expect(store.connection, AiConnection.listening);
    await next.close();
    expect(store.connection, AiConnection.disconnected);
  });

  testWidgets('Muestra candidatos como pendientes de revisión', (tester) async {
    final store = AiDetectionStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiDetectionPanel(store: store)),
      ),
    );
    expect(find.text('Sin conexión con el servicio de IA.'), findsOneWidget);
    store.ingest(jsonEncode(candidate()));
    await tester.pump();
    expect(
      find.text('Posible agresión · Pendiente de revisión'),
      findsOneWidget,
    );
    expect(find.text('Confianza del modelo: 82.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
