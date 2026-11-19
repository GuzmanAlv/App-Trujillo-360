import 'package:alerta_ciudadana/services/sos_route_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('Decodifica la geometría de calles de Google sin inventar puntos', () {
    final points = decodeRoutePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, const [
      LatLng(38.5, -120.2),
      LatLng(40.7, -120.95),
      LatLng(43.252, -126.453),
    ]);
  });
  test('Rechaza geometría incompleta o inválida', () {
    for (final line in ['', '_', '????~', '\u0000', '~~~~~~~~~~~~']) {
      expect(() => decodeRoutePolyline(line), throwsFormatException);
    }
  });
  test('El encuadre contiene origen, destino y recorrido', () {
    final route = SosRouteController()
      ..points = const [LatLng(-8.12, -79.02), LatLng(-8.1, -79.03)]
      ..origin = const LatLng(-8.13, -79.02)
      ..destination = const LatLng(-8.1, -79.04);
    expect(route.bounds!.contains(route.origin!), isTrue);
    expect(route.bounds!.contains(route.destination!), isTrue);
    route.clear();
    expect(route.bounds, isNull);
    route.dispose();
  });
}
