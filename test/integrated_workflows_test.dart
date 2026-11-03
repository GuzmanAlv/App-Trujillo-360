import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/ui/workflow_panel.dart';
import 'package:alerta_ciudadana/data/density_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 12);
  Incident entry({
    String status = 'corroborated',
    int count = 3,
    bool review = false,
    DateTime? at,
  }) => Incident(
    id: 'case',
    type: 'Robo',
    place: 'Prueba',
    description: '',
    latitude: -8.1,
    longitude: -79,
    createdAt: at ?? now,
    remoteStatus: status,
    corroborationCount: count,
    needsReview: review,
  );
  test(
    'Publicación independiente de urgencia y siete días exactos desde el hecho',
    () {
      expect(entry(status: 'verified', count: 1).isCommunityVisible, isTrue);
      expect(entry(status: 'pending', count: 100).isCommunityVisible, isFalse);
      expect(entry(review: true).isCommunityVisible, isFalse);
      expect(entry(count: 2).isCommunityVisible, isFalse);
      expect(
        entry(at: now.subtract(const Duration(days: 7))).recentAt(now),
        isFalse,
      );
      expect(
        entry(
          at: now.subtract(
            const Duration(days: 7) - const Duration(seconds: 1),
          ),
        ).recentAt(now),
        isTrue,
      );
      expect(
        entry(at: now.add(const Duration(seconds: 1))).recentAt(now),
        isFalse,
      );
    },
  );
  test(
    'Colores usan incidentes y cambiar franja elimina resultados de la anterior',
    () {
      final store = DensityStore();
      store.cells = [
        {'latitude': -8.1, 'longitude': -79.1, 'count': 2},
        {'latitude': -8.2, 'longitude': -79.2, 'count': 3},
      ];
      expect(store.overlays.first.strokeColor, Colors.amber.shade800);
      expect(store.overlays.last.strokeColor, Colors.red);
      store.configure(enabled: false, band: 3);
      expect(store.cells, isEmpty);
      store.dispose();
    },
  );
  testWidgets('No existe selector público para obtener permisos de operador', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OperatorPortal()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Verificar acceso'), findsOneWidget);
    expect(find.text('Revisar reportes'), findsNothing);
    expect(find.textContaining('Inicia sesión con Google'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
