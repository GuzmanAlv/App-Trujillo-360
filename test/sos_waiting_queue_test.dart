import 'package:alerta_ciudadana/ui/sos_waiting_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Pendientes y llamadas permiten ubicar o evaluar sin confundir las acciones',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final cases = ValueNotifier<List<String>>(['missed-sos']);
      addTearDown(cases.dispose);
      final located = <String>[], opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder(
                valueListenable: cases,
                builder: (context, ids, _) => SosWaitingQueue(
                  calls: ids,
                  waitingCalls: const {
                    'missed-sos': false,
                    'waiting-call': true,
                  },
                  onSelect: located.add,
                  onOpen: opened.add,
                  muted: false,
                  onMute: () {},
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      );
      // One unresolved SOS remains in the header even without a live call.
      expect(find.text('SOS Ayuda solicitada'), findsOneWidget);
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pumpAndSettle();
      expect(located, ['missed-sos']);
      await tester.tap(find.byTooltip('Evaluar caso SOS'));
      await tester.pumpAndSettle();
      expect(opened, ['missed-sos']);
      expect(located.length, 1);
      cases.value = ['waiting-call', 'missed-sos'];
      await tester.pump();
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pumpAndSettle();
      expect(find.text('Llamada en espera'), findsOneWidget);
      expect(find.text('Pendiente de evaluación'), findsOneWidget);
      await tester.tap(find.byTooltip('Evaluar caso SOS').last);
      await tester.pumpAndSettle();
      expect(opened, ['missed-sos', 'missed-sos']);
      expect(located.length, 1);
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver ubicación').first);
      await tester.pumpAndSettle();
      expect(located.last, 'waiting-call');
      cases.value = [];
      await tester.pump();
      expect(find.text('SOS Ayuda solicitada'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Una llamada centra directamente, varias se despliegan y solo se selecciona la elegida',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = ValueNotifier<List<String>>(['call-a']);
      addTearDown(calls.dispose);
      final selected = <String>[];
      var muteTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder(
                valueListenable: calls,
                builder: (context, ids, _) => SosWaitingQueue(
                  calls: ids,
                  onSelect: selected.add,
                  muted: false,
                  onMute: () => muteTaps++,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pumpAndSettle();
      expect(selected, ['call-a']);
      expect(find.text('Llamada SOS 1'), findsNothing);
      calls.value = ['call-a', 'call-b', 'call-c'];
      await tester.pump();
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pumpAndSettle();
      expect(selected, ['call-a']);
      expect(find.text('Llamada SOS 2'), findsOneWidget);
      await tester.tap(find.text('Llamada SOS 2'));
      await tester.pumpAndSettle();
      expect(selected, ['call-a', 'call-b']);
      expect(find.text('Llamada SOS 1'), findsNothing);
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pump();
      calls.value = ['call-c'];
      await tester.pump();
      expect(find.text('Llamada SOS 1'), findsNothing);
      await tester.tap(find.text('SOS Ayuda solicitada'));
      await tester.pump();
      expect(selected.last, 'call-c');
      await tester.tap(find.byTooltip('Silenciar sonido y vibración'));
      await tester.pump();
      expect(muteTaps, 1);
      expect(selected.length, 3);
      calls.value = [];
      await tester.pump();
      expect(find.text('SOS Ayuda solicitada'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
