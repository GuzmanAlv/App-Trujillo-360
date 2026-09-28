import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../core/config.dart';

@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  // El sistema muestra las notificaciones con payload notification.
  // La sincronización con el backend se incorporará al implementar cuentas.
}

class PushService {
  Future<String> enable() async {
    if (!AppConfig.firebaseConfigured) {
      return 'Firebase pendiente de configuración. No se han activado notificaciones.';
    }
    if (kIsWeb) {
      return 'La configuración push web y su service worker quedan para el panel web. Prueba FCM en Android.';
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: AppConfig.firebaseApiKey,
            appId: AppConfig.firebaseAppId,
            messagingSenderId: AppConfig.firebaseSenderId,
            projectId: AppConfig.firebaseProjectId,
          ),
        );
      }
      FirebaseMessaging.onBackgroundMessage(backgroundMessage);
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return 'Notificaciones no autorizadas.';
      }
      final token = await FirebaseMessaging.instance.getToken();
      return token == null
          ? 'No se pudo registrar este dispositivo. Inténtalo nuevamente.'
          : 'Dispositivo registrado en FCM. Falta conectar el backend para enviar alertas por zona.';
    } catch (_) {
      return 'No se pudo configurar FCM. Revisa las credenciales y la conexión.';
    }
  }
}
