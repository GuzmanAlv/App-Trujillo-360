import 'package:alerta_ciudadana/ui/sos_waiting_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
