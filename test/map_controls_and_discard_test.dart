import 'package:alerta_ciudadana/services/citizen_sos_tracker.dart';
import 'package:alerta_ciudadana/services/active_call.dart';
import 'package:alerta_ciudadana/services/call_session.dart';
import 'package:alerta_ciudadana/services/sos_route_controller.dart';
import 'package:alerta_ciudadana/ui/map_bottom_controls.dart';
import 'package:alerta_ciudadana/ui/sos_discard_dialog.dart';
import 'package:alerta_ciudadana/ui/hold_sos_button.dart';
import 'package:alerta_ciudadana/ui/sos_route_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class TestRoom extends Fake implements lk.Room {
  @override
  void removeListener(VoidCallback listener) {}
  @override
  Future<bool> dispose() async => true;
}

void main() {
  testWidgets(
    'SOS confirmado reemplaza el botón y deja acceso a llamada y fotos',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tracker = CitizenSosTracker()
        ..value = [
          {'id': 'active-case'},
        ];
      final route = SosRouteController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: MapBottomControls(
                    operator: false,
                    route: route,
                    citizenSos: tracker,
                    onSos: () => fail('No debe crear otro SOS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(HoldSosButton), findsNothing);
      expect(find.text('Llamar al operador'), findsOneWidget);
      expect(find.byTooltip('Mi caso SOS · agregar foto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tracker.value = [];
      await tester.pump();
      expect(find.byType(HoldSosButton), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
      route.dispose();
    },
  );

  testWidgets('El descarte ofrece tres decisiones y exige un motivo nuevo', (
    tester,
  ) async {
    SosDiscardDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<SosDiscardDecision>(
                  context: context,
                  builder: (_) => const SosDiscardDialog(),
                );
              },
              child: const Text('Descartar caso'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Descartar caso'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Descartar y bloquear'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Descartar y bloquear'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Uso malicioso comprobado');
    await tester.pump();
    await tester.tap(find.text('Descartar y bloquear'));
    await tester.pumpAndSettle();
    expect(result?.action, 'discard_block');
    expect(result?.reason, 'Uso malicioso comprobado');
    await tester.tap(find.text('Descartar caso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets(
    'Los controles no tapan el SOS ni el GPS en un celular estrecho',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final route = SosRouteController()
        ..caseId = 'case'
        ..seconds = 180
        ..meters = 1000;
      final call = CallSession(
        callId: 'case',
        operator: false,
        room: TestRoom(),
      );
      ActiveCall.bind(call);
      ActiveCall.minimize(call);
      Future<void> layout(bool operator) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned(
                  right: 12,
                  bottom: 38,
                  child: SizedBox(key: ValueKey('gps'), width: 40, height: 40),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: MapBottomControls(
                    operator: operator,
                    route: route,
                    onSos: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await layout(false);
      await tester.pump();
      final sos = tester.getRect(find.byType(HoldSosButton));
      final controls = tester.getRect(
        find.byKey(const ValueKey('compact-call-controls')),
      );
      final gps = tester.getRect(find.byKey(const ValueKey('gps')));
      expect(sos.overlaps(controls), isFalse);
      expect(sos.overlaps(gps), isFalse);
      expect(controls.overlaps(gps), isFalse);
      expect(find.byType(SosRouteBadge), findsNothing);
      await layout(true);
      await tester.pump();
      expect(find.byType(HoldSosButton), findsNothing);
      expect(find.text('Solicitar refuerzos'), findsNothing);
      final routeRect = tester.getRect(find.byType(SosRouteBadge));
      final callRect = tester.getRect(find.byTooltip('Abrir llamada SOS'));
      expect(callRect.bottom, lessThan(routeRect.top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ActiveCall.release(call);
      route.dispose();
      await tester.pump();
    },
  );
}
