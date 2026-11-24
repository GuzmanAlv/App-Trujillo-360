import 'package:alerta_ciudadana/ui/incoming_call_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('La llamada de un ciudadano asignado permite responder', (
    tester,
  ) async {
    String? accepted;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => IncomingCallView(
          queue: const [
            {'id': 'assigned-case', 'assigned': true},
          ],
          onAccept: (id) => accepted = id,
          onHide: (_) {},
          child: child!,
        ),
        home: const Scaffold(body: Text('Mapa')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu ciudadano te llama'), findsOneWidget);
    await tester.tap(find.text('Tomar llamada'));
    expect(accepted, 'assigned-case');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Las llamadas SOS al operador no muestran una tarjeta flotante', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => IncomingCallView(
          queue: const [
            {'id': 'operator-sos'},
          ],
          onAccept: (_) {},
          onHide: (_) {},
          child: child!,
        ),
        home: const Scaffold(body: Text('Mapa del operador')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mapa del operador'), findsOneWidget);
    expect(find.text('Tomar llamada'), findsNothing);
    expect(find.text('SOS Alerta'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Aviso sobre el Navigator permite tooltip, aceptar y ocultar sin perder la ruta',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      final calls = ValueNotifier<List<Map<String, dynamic>>>([]);
      addTearDown(calls.dispose);
      String? accepted;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: calls,
            builder: (context, queue, _) => IncomingCallView(
              queue: queue,
              onAccept: (id) {
                accepted = id;
                calls.value = [];
              },
              onHide: (_) => calls.value = [],
              child: child!,
            ),
          ),
          home: const Scaffold(body: Center(child: Text('Mapa'))),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Otra pantalla'))),
        ),
      );
      await tester.pumpAndSettle();
      calls.value = [
        {'id': 'sos-1', 'callback': true},
      ];
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Otra pantalla'), findsOneWidget);
      expect(find.text('Tomar llamada').hitTestable(), findsOneWidget);
      const tooltip = 'Ocultar aviso; el SOS sigue pendiente';
      await tester.longPress(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(tooltip), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Tomar llamada'));
      await tester.pumpAndSettle();
      expect(accepted, 'sos-1');
      expect(find.text('Otra pantalla'), findsOneWidget);
      calls.value = [
        {'id': 'sos-2', 'callback': true},
      ];
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.text('El operador te llama'), findsNothing);
      expect(find.text('Otra pantalla'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Mapa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
