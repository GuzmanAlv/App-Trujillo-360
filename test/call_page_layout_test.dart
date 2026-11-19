import 'package:alerta_ciudadana/ui/call_page_layout.dart';
import 'package:alerta_ciudadana/ui/operator_call_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Al bajar el formulario queda la barra compacta con los tres controles',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var mic = 0, speaker = 0, hangup = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallPageLayout(
              controls: const SizedBox(
                height: 280,
                child: Center(child: Text('Cabecera ampliada')),
              ),
              compactControls: OperatorCallBar(
                message: 'Audio conectado',
                muted: false,
                speaker: false,
                finished: false,
                closing: false,
                connected: true,
                onMute: () => mic++,
                onSpeaker: () => speaker++,
                onHangUp: () => hangup++,
              ),
              evaluation: const SizedBox(
                height: 1500,
                child: Text('Formulario de evaluación'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cabecera ampliada'), findsOneWidget);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Cabecera ampliada'), findsNothing);
      expect(find.text('Atención SOS'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Atención SOS')).dy, lessThan(110));
      await tester.tap(find.byTooltip('Silenciar'));
      await tester.tap(find.byTooltip('Altavoz'));
      await tester.tap(find.byTooltip('Cortar llamada'));
      expect([mic, speaker, hangup], [1, 1, 1]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Llamada ciudadana centrada y operador sin desbordes en pantallas pequeñas',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const card = SizedBox(
        key: ValueKey('controls'),
        height: 240,
        child: Text('Preparando llamada…'),
      );
      for (final operator in [false, true]) {
        for (final size in [
          const Size(360, 800),
          const Size(320, 300),
          const Size(800, 360),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CallPageLayout(
                  controls: card,
                  evaluation: operator
                      ? const SizedBox(height: 900, child: Text('Evaluación'))
                      : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getCenter(find.byKey(const ValueKey('controls'))).dx,
            closeTo(size.width / 2, 1),
          );
          if (!operator && size.height == 800) {
            expect(
              tester.getCenter(find.byKey(const ValueKey('controls'))).dy,
              closeTo(size.height / 2, 1),
            );
          }
        }
      }
    },
  );
}
