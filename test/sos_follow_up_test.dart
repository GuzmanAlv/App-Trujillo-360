import 'package:alerta_ciudadana/services/sos_alert_state.dart';
import 'package:alerta_ciudadana/ui/citizen_sos_page.dart';
import 'package:alerta_ciudadana/ui/sos_incoming_attention.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Atender y colgar no resuelve un SOS pendiente', () {
    for (final state in ['waiting', 'accepted', 'ended', 'unanswered']) {
      expect(
        needsOperatorSosAlert({
          'decision': 'pending',
          'call_state': state,
          'attention': 'none',
        }),
        isTrue,
      );
    }
    expect(
      needsOperatorSosAlert({'decision': 'confirmed', 'attention': 'none'}),
      isFalse,
    );
    expect(
      needsOperatorSosAlert({'decision': 'discarded', 'attention': 'none'}),
      isFalse,
    );
    expect(
      needsOperatorSosAlert({'decision': 'confirmed', 'attention': 'resolved'}),
      isFalse,
    );
    expect(citizenSosMessage('none'), isNot(contains('encuentra en camino')));
    expect(citizenSosMessage('en_route'), contains('encuentra en camino'));
  });
  testWidgets(
    'Aviso naranja del ciudadano nunca solicita sonido ni vibración',
    (tester) async {
      const channel = MethodChannel('trujillo360/proximity');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SosIncomingAttention(
            active: true,
            enableSound: false,
            glowColor: Colors.orange,
            builder: (muted, toggle) =>
                const Scaffold(body: Text('Incidente confirmado')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
