import 'package:alerta_ciudadana/ui/sos_incoming_attention.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/services/sos_alarm.dart';

void main() {
  test('Pasar del mapa a la ficha no cancela la alarma de la ficha', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('trujillo360/proximity');
    final sent = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          sent.add((call.arguments as Map)['enabled'] as bool);
          return null;
        });
    final map = Object(), page = Object();
    try {
      await SosAlarm.update(map, true);
      await SosAlarm.update(page, true);
      await SosAlarm.update(map, false);
      expect(sent.last, isTrue);
      await SosAlarm.update(page, false);
      expect(sent.last, isFalse);
    } finally {
      await SosAlarm.update(map, false);
      await SosAlarm.update(page, false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  testWidgets(
    'Alarma se silencia, se renueva y se detiene al desaparecer la llamada',
    (tester) async {
      const channel = MethodChannel('trujillo360/proximity');
      final enabled = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'sosIncomingAlarm') {
          enabled.add((call.arguments as Map)['enabled'] as bool);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: active,
            builder: (context, value, _) => SosIncomingAttention(
              active: value,
              builder: (muted, toggle) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: toggle,
                    child: Text(muted ? 'Activar' : 'Silenciar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(enabled.last, isTrue);
      await tester.pump(const Duration(seconds: 8));
      expect(enabled.where((e) => e).length, greaterThanOrEqualTo(2));
      await tester.tap(find.text('Silenciar'));
      await tester.pump();
      expect(enabled.last, isFalse);
      final count = enabled.length;
      await tester.pump(const Duration(seconds: 9));
      expect(enabled.length, count);
      await tester.tap(find.text('Activar'));
      await tester.pump();
      expect(enabled.last, isTrue);
      active.value = false;
      await tester.pump();
      expect(enabled.last, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(enabled.last, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
