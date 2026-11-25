import 'package:alerta_ciudadana/ui/citizen_sos_page.dart';
import 'package:alerta_ciudadana/ui/sos_overview_button.dart';
import 'package:alerta_ciudadana/ui/sos_waiting_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('El aviso confirma recepción pendiente sin prometer una unidad', () {
    final text = citizenSosMessage(
      'none',
      decision: 'pending',
      assignmentState: 'pending',
    );
    expect(text, contains('SOS recibido'));
    expect(text, contains('esperando atención'));
    expect(text.contains('en camino'), isFalse);
    expect(
      citizenSosMessage('en_route', decision: 'confirmed'),
      contains('en camino'),
    );
  });
  testWidgets(
    'El botón de alertas tiene el tamaño del GPS y mantiene el contador',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SosOverviewButton(count: 4, onPressed: () {}),
                FloatingActionButton.small(
                  key: const ValueKey('gps'),
                  heroTag: null,
                  onPressed: () {},
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        tester.getSize(find.byType(FloatingActionButton).first),
        tester.getSize(find.byKey(const ValueKey('gps'))),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'La cabecera compacta mantiene controles y triángulo sin desbordarse',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Align(
                alignment: Alignment.topCenter,
                child: SosWaitingQueue(
                  calls: const ['case'],
                  onSelect: (_) {},
                  onOpen: (_) {},
                  muted: false,
                  onMute: () {},
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sos-queue-header'))).height,
        lessThanOrEqualTo(40),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byTooltip('Actualizar casos SOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
