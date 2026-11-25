import 'package:alerta_ciudadana/ui/sos_waiting_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('La reserva pendiente sigue accesible para su operador', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosWaitingQueue(
            calls: const ['owned', 'available'],
            ownedCases: const {'owned'},
            onOpen: opened.add,
            onSelect: (_) {},
            muted: false,
            onMute: () {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    await tester.tap(find.text('Abrir'));
    expect(opened, ['owned']);
  });
  testWidgets(
    'SOS simultáneos aparecen directamente y se ordenan por minutos',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final accepted = <String>[];
      final focused = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SosWaitingQueue(
                calls: const ['far', 'near', 'third', 'fourth'],
                minutes: const {
                  'far': 12,
                  'near': 4,
                  'third': 20,
                  'fourth': 25,
                },
                waitingCalls: const {'near': true},
                addressFor: (id) async =>
                    id == 'far' ? 'Avenida Perú 19' : null,
                onOpen: accepted.add,
                onSelect: focused.add,
                muted: false,
                onMute: () {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SOS disponibles · 4'), findsOneWidget);
      expect(find.text('Aceptar').hitTestable(), findsNWidgets(4));
      expect(find.text('Aprox. 4 min de tu ubicación'), findsOneWidget);
      expect(find.text('Aprox. 12 min de tu ubicación'), findsOneWidget);
      expect(find.text('Llamada en espera'), findsOneWidget);
      await tester.tap(find.text('Aceptar').first);
      expect(accepted, ['near']);
      expect(focused, isEmpty);
      expect(find.byTooltip('Ver ubicación'), findsNothing);
      await tester.tap(find.text('Avenida Perú 19'));
      expect(focused, ['far']);
      expect(accepted, ['near']);
      expect(tester.takeException(), isNull);
    },
  );
}
