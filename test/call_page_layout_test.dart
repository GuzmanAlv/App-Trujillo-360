import 'package:alerta_ciudadana/ui/call_page_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
