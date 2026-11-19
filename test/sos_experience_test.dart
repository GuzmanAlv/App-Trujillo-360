import 'package:alerta_ciudadana/services/active_call.dart';
import 'package:alerta_ciudadana/services/call_session.dart';
import 'package:alerta_ciudadana/services/operator_duty.dart';
import 'package:alerta_ciudadana/services/sos_route_controller.dart';
import 'package:alerta_ciudadana/ui/audio_call_page.dart';
import 'package:alerta_ciudadana/ui/callback_ring.dart';
import 'package:alerta_ciudadana/ui/sos_incoming_attention.dart';
import 'package:alerta_ciudadana/ui/sos_route_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class TestRoom extends Fake implements lk.Room {
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  Future<bool> dispose() async => true;
}

void main() {
  test('Solo la asignación propia en camino o en zona silencia otros SOS', () {
    OperatorDuty.replace('operator', [
      {
        'id': 'other',
        'decision': 'confirmed',
        'attention': 'en_route',
        'can_track': false,
      },
      {
        'id': 'pending',
        'decision': 'pending',
        'attention': 'none',
        'can_track': true,
      },
    ]);
    expect(OperatorDuty.engaged, isFalse);
    OperatorDuty.upsert('operator', {
      'id': 'own',
      'decision': 'confirmed',
      'attention': 'en_route',
      'can_track': true,
    });
    expect(OperatorDuty.engaged, isTrue);
    OperatorDuty.upsert('operator', {
      'id': 'own',
      'decision': 'confirmed',
      'attention': 'on_scene',
      'can_track': true,
    });
    expect(OperatorDuty.engaged, isTrue);
    OperatorDuty.upsert('operator', {
      'id': 'own',
      'decision': 'confirmed',
      'attention': 'resolved',
      'can_track': true,
    });
    expect(OperatorDuty.engaged, isFalse);
    OperatorDuty.clear();
  });

  testWidgets(
    'Volver al mapa conserva la sesión ciudadana y su barra compacta',
    (tester) async {
      final call = CallSession(
        callId: 'citizen-call',
        operator: false,
        room: TestRoom(),
      );
      final route = SosRouteController();
      ActiveCall.bind(call);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: Text('Mapa')),
                SosRoutePanel(route: route),
              ],
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const AudioCallPage(callId: 'citizen-call'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver al mapa sin colgar'));
      await tester.pumpAndSettle();
      expect(find.text('Mapa'), findsOneWidget);
      expect(find.text('Abrir llamada'), findsNothing);
      expect(find.byTooltip('Abrir llamada SOS'), findsOneWidget);
      await tester.tap(find.byTooltip('Abrir llamada SOS'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Volver al mapa sin colgar'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver al mapa sin colgar'));
      await tester.pumpAndSettle();
      expect(ActiveCall.session.value, same(call));
      expect(call.finished, isFalse);
      expect(call.minimized, isTrue);
      expect(ActiveCall.id.value, 'citizen-call');
      await tester.pumpWidget(const SizedBox.shrink());
      ActiveCall.release(call);
      route.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cambiar a resplandor azul detiene el sonido de la alerta roja', (
    tester,
  ) async {
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
    final quiet = ValueNotifier(false);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: quiet,
          builder: (_, silent, _) => SosIncomingAttention(
            active: true,
            enableSound: !silent,
            glowColor: silent ? Colors.blue : Colors.red,
            builder: (_, _) => const Scaffold(body: Text('Mapa')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(enabled.last, isTrue);
    quiet.value = true;
    await tester.pump();
    expect(enabled.last, isFalse);
    await tester.pump(const Duration(seconds: 9));
    expect(enabled.last, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    quiet.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets(
    'La devolución de llamada renueva timbre y para al aceptar u ocultar',
    (tester) async {
      const channel = MethodChannel('trujillo360/proximity');
      final enabled = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'sosCallbackRing') {
          enabled.add((call.arguments as Map)['enabled'] as bool);
        }
        return null;
      });
      final active = ValueNotifier(true);
      final ringId = ValueNotifier('first-return');
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: Listenable.merge([active, ringId]),
            builder: (_, _) => CallbackRing(
              active: active.value,
              ringId: ringId.value,
              builder: (muted, toggle) => TextButton(
                onPressed: toggle,
                child: Text(muted ? 'Activar' : 'Silenciar'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(enabled.last, isTrue);
      await tester.pump(const Duration(seconds: 8));
      expect(enabled.where((v) => v).length, greaterThanOrEqualTo(2));
      await tester.tap(find.text('Silenciar'));
      await tester.pump();
      expect(enabled.last, isFalse);
      ringId.value = 'second-return';
      await tester.pump();
      expect(enabled.last, isTrue);
      active.value = false;
      await tester.pump();
      expect(enabled.last, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      active.dispose();
      ringId.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
