import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/ui/report_marker.dart';

void main() {
  testWidgets('Category filters retain their labels and can be selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = IncidentStore(await SharedPreferences.getInstance())..load();
    await tester.pumpWidget(TrujilloApp(store: store));
    final robbery = find.widgetWithText(ChoiceChip, 'Robo').hitTestable();
    expect(robbery, findsOneWidget);
    expect(tester.widget<ChoiceChip>(robbery).avatar, isA<Icon>());
    await tester.tap(robbery);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(robbery).selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('Every category produces a decodable transparent map label', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final category in ['Robo', 'Auxilio', 'Agresión', 'Riesgo']) {
        final bytes = await renderReportMarker(category, '09:05');
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 348);
          expect(frame.image.height, 164);
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull);
          expect(
            rgba!.getUint8(3),
            0,
            reason: 'Transparent background around the label',
          );
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      }
    });
  });
}
