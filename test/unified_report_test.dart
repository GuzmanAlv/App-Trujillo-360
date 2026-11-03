import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/ui/report_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'La urgencia sobrevive el guardado y la confirmación del servidor',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = IncidentStore(prefs)..load();
      final report = Incident(
        id: 'retry',
        type: 'Robo',
        place: 'Prueba',
        description: '',
        latitude: -8.1,
        longitude: -79,
        createdAt: DateTime.now(),
        priority: 'Alta',
      );
      expect(await store.add(report), isTrue);
      final restored = (IncidentStore(prefs)..load()).items.single;
      expect(restored.priority, 'Alta');
      expect(restored.delivered('server-id').priority, 'Alta');
      final legacy = report.toJson()..remove('priority');
      expect(Incident.fromJson(legacy).priority, isNull);
    },
  );

  testWidgets(
    'Alta muestra llamada opcional sin enviar ni perder el formulario',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      const channel = MethodChannel('trujillo360/proximity');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(MaterialApp(home: ReportForm(store: store)));
      expect(find.text('Llamar a Seguridad Ciudadana'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alta').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Llamar a Seguridad Ciudadana'));
      await tester.pumpAndSettle();
      expect(calls, ['dial']);
      expect(store.items, isEmpty);
      expect(find.text('Nuevo reporte'), findsOneWidget);
      expect(find.textContaining('Hora del hecho:'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baja').last);
      await tester.pumpAndSettle();
      expect(find.text('Llamar a Seguridad Ciudadana'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
