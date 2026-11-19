import 'package:alerta_ciudadana/ui/sos_case_panel.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> initial() => {
  'id': 'case',
  'version': 0,
  'decision': 'pending',
  'attention': 'none',
  'can_edit': true,
  'category': 'Auxilio',
  'caller_latitude': -8.11,
  'caller_longitude': -79.03,
  'latitude': -8.11,
  'longitude': -79.03,
  'received_at': '2026-11-18T10:00:00Z',
  'place': '',
  'public_description': '',
  'internal_note': '',
  'outcome': '',
  'events': [],
};
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

void main() {
  testWidgets(
    'Confirmación conserva GPS del teléfono y reintenta el mismo identificador',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      final data = {
        ...initial(),
        'place': 'Plaza de prueba',
        'public_description': 'Incidente confirmado',
      };
      Future<dynamic> request(
        String method,
        String path, {
        Map<String, dynamic>? body,
      }) async {
        if (method == 'GET') return data;
        sent.add(Map.of(body!));
        if (sent.length == 1) throw StateError('Conexión interrumpida');
        return {
          ...data,
          ...body,
          'version': 1,
          'decision': 'confirmed',
          'incident_id': 'incident',
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SosCasePanel(caseId: 'case', request: request),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(field('Referencia del lugar (opcional)'), findsNothing);
      expect(field('Descripción pública (opcional)'), findsNothing);
      expect(find.text('Solicitar más patrullas'), findsNothing);
      await enter(
        tester,
        'Comentario interno · solo operadores',
        'Nota confidencial',
      );
      await tester.ensureVisible(find.text('Confirmar SOS'));
      await tester.tap(find.text('Confirmar SOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(sent.single['latitude'], -8.11);
      expect(sent.single.containsKey('caller_latitude'), isFalse);
      expect(sent.single['public_description'], 'Incidente confirmado');
      expect(sent.single['internal_note'], 'Nota confidencial');
      await tester.ensureVisible(find.text('Reintentar el mismo envío'));
      await tester.tap(find.text('Reintentar el mismo envío'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent[1]['request_id'], sent[0]['request_id']);
      expect(find.textContaining('Teléfono: -8.11, -79.03'), findsNothing);
      expect(find.text('Unidad en camino'), findsOneWidget);
      expect(find.text('Personal en el lugar'), findsOneWidget);
    },
  );

  testWidgets(
    'Un caso asignado a otro operador no ofrece cambios habilitados',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SosCasePanel(
                caseId: 'case',
                request: (method, path, {body}) async => {
                  ...initial(),
                  'can_edit': false,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar SOS'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(field('Comentario interno · solo operadores'))
            .enabled,
        isFalse,
      );
    },
  );

  test(
    'Presencia sobre el mapa sobrevive a la serialización y no implica corroboraciones',
    () {
      final i = Incident(
        id: 'i',
        type: 'Auxilio',
        place: 'Lugar',
        description: 'Público',
        latitude: 0,
        longitude: 0,
        createdAt: DateTime.now(),
        remoteStatus: 'verified',
        attention: 'on_scene',
      );
      final restored = Incident.fromJson(i.toJson());
      expect(restored.isCommunityVisible, isTrue);
      expect(restored.corroborationCount, 0);
      expect(restored.attention, 'on_scene');
      expect(attentionLabel(restored.attention), 'Personal en el lugar');
      expect(attentionLabel('en_route'), isNot('Personal en el lugar'));
    },
  );
}
