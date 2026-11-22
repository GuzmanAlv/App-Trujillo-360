import 'package:alerta_ciudadana/ui/sos_waiting_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SOS simultáneos aparecen directamente y se ordenan por minutos', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final accepted = <String>[];
    final focused = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topCenter,
      child: SosWaitingQueue(
        calls: const ['far', 'near'],
        minutes: const {'far': 12, 'near': 4},
        waitingCalls: const {'near': true},
        onOpen: accepted.add,
        onSelect: focused.add,
        muted: false,
        onMute: () {},
        onRefresh: () {},
      ),
    ))));
    expect(find.text('SOS disponibles · 2'), findsOneWidget);
    expect(find.text('Aprox. 4 min de tu ubicación'), findsOneWidget);
    expect(find.text('Aprox. 12 min de tu ubicación'), findsOneWidget);
    expect(find.text('Llamada en espera'), findsOneWidget);
    await tester.tap(find.text('Aceptar').first);
    expect(accepted, ['near']);
    await tester.tap(find.byTooltip('Ver ubicación').last);
    expect(focused, ['far']);
    expect(tester.takeException(), isNull);
  });
}
