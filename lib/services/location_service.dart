import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'Activa la ubicación del dispositivo e inténtalo otra vez.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Permiso bloqueado. Habilita la ubicación en los ajustes de la aplicación o del navegador.',
      );
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw const LocationFailure(
        'No se concedió el permiso de ubicación. Actívalo para usar esta función.',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Stream<Position> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );

  Stream<Position> watchAlerts({bool batterySaver = false}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: batterySaver ? 500 : 250,
          intervalDuration: Duration(minutes: batterySaver ? 15 : 5),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'Alertas por ubicación activas',
            notificationText: 'Trujillo 360 actualiza tu zona para avisarte de incidentes cercanos.',
            notificationChannelName: 'Ubicación para alertas',
            setOngoing: true,
          ),
        ),
      );
}

class LocationFailure implements Exception {
  const LocationFailure(this.message);
  final String message;
}
