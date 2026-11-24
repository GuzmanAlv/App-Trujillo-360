import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/services/operator_duty.dart';
import 'package:alerta_ciudadana/services/sos_arrival_tracker.dart';

void main() {
  testWidgets(
    'Inicia al confirmar, mantiene servicio al bloquear y detiene al llegar',
    (tester) async {
      const channel = MethodChannel('trujillo360/proximity');
      final enabled = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'sosArrivalTracking') {
          enabled.add((call.arguments as Map)['enabled'] as bool);
        }
        return true;
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final tracker = SosArrivalTracker();
      tracker.configure(true);
      final row = <String, dynamic>{
        'id': 'case',
        'can_track': true,
        'decision': 'confirmed',
        'attention': 'en_route',
      };
      OperatorDuty.upsert('operator', row);
      await tester.pump();
      expect(enabled.last, isTrue);
      final count = enabled.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(enabled.length, count);
      OperatorDuty.upsert('operator', {...row, 'attention': 'on_scene'});
      await tester.pump();
      expect(enabled.last, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tracker.dispose();
      OperatorDuty.clear();
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
