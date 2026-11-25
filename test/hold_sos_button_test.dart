import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/ui/hold_sos_button.dart';

void main() {
  testWidgets('Pausar la app cancela la cuenta regresiva', (tester) async {
    var sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HoldSosButton(onComplete: () => sent++)),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldSosButton)),
    );
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 3));
    expect(sent, 0);
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('Solo una pulsación continua de tres segundos envía el SOS', (
    tester,
  ) async {
    var sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HoldSosButton(onComplete: () => sent++)),
      ),
    );
    final point = tester.getCenter(find.byType(HoldSosButton));
    var gesture = await tester.startGesture(point);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(sent, 0);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(sent, 0);
    gesture = await tester.startGesture(point);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(sent, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(sent, 1);
    await gesture.up();
  });

  testWidgets('Salir del botón cancela; ocupado no permite otra solicitud', (
    tester,
  ) async {
    var sent = 0;
    Future<void> draw(bool busy) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldSosButton(busy: busy, onComplete: () => sent++),
        ),
      ),
    );
    await draw(false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldSosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveTo(const Offset(700, 500));
    await tester.pump(const Duration(seconds: 3));
    expect(sent, 0);
    await gesture.up();
    await draw(true);
    final busy = await tester.startGesture(
      tester.getCenter(find.byType(HoldSosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(sent, 0);
    await busy.up();
  });
}
