import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/ui/report_details_page.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/photo_store.dart';
import 'package:alerta_ciudadana/services/report_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Persistent photo files survive report acknowledgement and reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'report-photos-test',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      try {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final photo = await PhotoStore.save(ReportSender.requestId(), bytes);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final store = IncidentStore(preferences)..load();
        final report = Incident(
          id: ReportSender.requestId(),
          type: 'Robo',
          place: 'Prueba',
          description: '',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime(2026),
          photos: [photo],
        );
        expect(await store.add(report), isTrue);
        expect(await store.add(report.delivered('server-id')), isTrue);
        final restored = IncidentStore(preferences)..load();
        expect(restored.items.single.photos.single.id, photo.id);
        expect(
          await PhotoStore.read(restored.items.single.photos.single),
          orderedEquals(bytes),
        );
        await PhotoStore.remove(photo);
        expect(PhotoStore.read(photo), throwsA(isA<FileSystemException>()));
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('Report detail shows exact date, time and photo state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = IncidentStore(await SharedPreferences.getInstance())..load();
    await store.add(
      Incident(
        id: 'legacy',
        type: 'Robo',
        place: 'Plaza de Armas',
        description: 'Detalle de prueba',
        latitude: -8.11,
        longitude: -79.02,
        createdAt: DateTime(2026, 10, 5, 9, 7, 12),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDetailsPage(report: store.items.single, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detalle del reporte'), findsOneWidget);
    expect(find.text('05/10/2026'), findsOneWidget);
    expect(find.text('09:07:12 (hora local)'), findsOneWidget);
    expect(find.text('Detalle de prueba'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Este reporte no tiene fotos.'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Este reporte no tiene fotos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
