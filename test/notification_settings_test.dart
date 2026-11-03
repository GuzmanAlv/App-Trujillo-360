import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/app.dart';
import 'package:alerta_ciudadana/data/incident_store.dart';
import 'package:alerta_ciudadana/ui/notification_settings.dart';

void main() {
  testWidgets(
    'La configuración antigua se reemplaza y no pide permisos al abrir',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      await tester.pumpWidget(TrujilloApp(store: store));
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      expect(find.text('Alertas a 500 metros'), findsNothing);
      expect(find.text('Activar notificaciones'), findsNothing);
      await tester.scrollUntilVisible(find.text('Notificaciones'), 250);
      await tester.tap(find.text('Notificaciones'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationSettings), findsOneWidget);
      expect(find.textContaining('Inicia sesión con Google'), findsOneWidget);
      expect(find.text('Nuevos reportes para el operador'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
