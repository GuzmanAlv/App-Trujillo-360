# Trujillo 360 — primera base Flutter

## Abrir en Visual Studio Code
Abre esta carpeta con VS Code e instala las extensiones Flutter y Dart. En este equipo el SDK está en `C:/Users/PC/Documents/Flutter/flutter`: si VS Code pregunta por el SDK, selecciona esa carpeta. Android Studio se utiliza para administrar Android SDK y el emulador.

En la terminal del proyecto:
```powershell
flutter doctor -v
flutter pub get
flutter run -d chrome
```
Si `flutter` no se reconoce, agrega `C:/Users/PC/Documents/Flutter/flutter/bin` al PATH de Windows y reinicia VS Code, o utiliza la ruta completa a `flutter.bat`.
Para Android, conecta un teléfono con depuración USB, autoriza el equipo y selecciona el dispositivo en VS Code. Ejecuta `flutter devices` y `flutter run`. Acepta las licencias mediante `flutter doctor --android-licenses` después de leerlas. La compilación Android requiere Java y los componentes del SDK que indique `flutter doctor`.

## Lo disponible
- Pantallas de mapa, reportes y configuración; formulario con validación de coordenadas.
- Reportes guardados localmente, categorías y detalle. No aparecen reportes ficticios.
- Servicio de GPS y seguimiento en primer plano. Requiere consentimiento y ubicación habilitada; se detiene al pasar la app a segundo plano.
- Google Maps integrado, desactivado hasta configurar una clave. Sin clave se muestra un aviso y puedes probar reportes con coordenadas manuales.
- Paquetes instalados: google_maps_flutter, geolocator, shared_preferences, http, web_socket_channel, firebase_core y firebase_messaging.

Los reportes de esta primera versión NO se publican a otros usuarios. SharedPreferences es almacenamiento de demostración, no una base segura de evidencias: usa datos de prueba.

## Activar Google Maps en Android
1. En Google Cloud, configura la facturación y habilita Maps SDK for Android.
2. Crea una clave restringida a Android, al paquete `pe.com.alertaciudadana.alerta_ciudadana` y al SHA-1 de tu firma. Restringe también la API autorizada. No se usa Map ID.
3. Copia `android/maps.properties.example` a `android/maps.properties` y reemplaza el valor por tu clave.
4. Copia `config/example.json` a `config/local.json` y cambia MAPS_ENABLED a true.
5. Ejecuta `flutter run --dart-define-from-file=config/local.json` en Android.

Para mostrar Google Maps en web, se necesita una clave distinta restringida por sitios web, habilitar Maps JavaScript API e incorporar su script en `web/index.html` antes de `flutter_bootstrap.js`. Después activa MAPS_ENABLED. Hasta hacer esa configuración, ejecuta web en modo local sin mapas. No incluyas claves de cuentas de servicio en la app.

## Firebase y tiempo real: preparados, pendientes de conexión
`PushService` permite solicitar permiso y registrar Android en FCM si completas los cuatro campos FIREBASE del archivo local con los datos de tu app Firebase. No se ha configurado un proyecto Firebase ni probado envíos. Falta vincular el token al usuario en el servidor, recibir eventos en primer plano y abrir el incidente al tocar la notificación. Push web requiere configuración adicional de service worker.

`BackendClient` es un adaptador inicial para HTTP y WebSocket; todavía no está conectado a las pantallas. Su contrato propuesto es GET /incidents con token y una lista JSON de incidentes. Requiere HTTPS/WSS. Falta implementar FastAPI, autenticación, permisos, reconexión WebSocket y sincronización antes de publicar reportes entre dispositivos.

La IA de cámaras se ejecutará en el servidor/equipo con RTX 4060. Esta entrega no incorpora análisis de video, cuentas ni panel de validación del operador. El proyecto generado contiene Android y web; iOS se preparará en un Mac con Xcode.

## Código
La preparación de IA incorpora una pestaña de candidatos pendientes de revisión,
un receptor de eventos validado y pruebas. Sigue sin haber cámaras ni inferencia
conectadas. El contrato propuesto y los pasos pendientes están en
[docs/ai-integration.md](docs/ai-integration.md).

- lib/app.dart: navegación y pantallas principales.
- lib/ui/: mapa y formulario.
- lib/models/ y lib/data/: reportes y almacenamiento local.
- lib/services/: ubicación, Firebase y adaptador del backend.
- lib/core/config.dart: configuración mediante dart-define.

## Verificar
```powershell
flutter analyze
flutter test
flutter build web
```
Los archivos locales de configuración quedan excluidos de Git. El identificador interno del paquete se mantiene como alerta_ciudadana por compatibilidad; el nombre visible es Trujillo 360. Antes de publicar Android se necesita una firma de producción.

## Estado de la verificación en este equipo
Flutter 3.44.4 y Dart 3.12.2 detectados. El análisis estático terminó sin observaciones y pasaron las tres pruebas iniciales. Chrome está disponible. `flutter doctor` no encuentra cmdline-tools en la ruta Android SDK configurada: para ejecutar en celular, abre Android Studio > SDK Manager y confirma la ruta del SDK; instala Android SDK Command-line Tools (latest), Platform-Tools y una plataforma Android compatible. Después configura Flutter con `flutter config --android-sdk RUTA_DEL_SDK` si la ruta es diferente, y ejecuta `flutter doctor --android-licenses`. No se ha verificado una compilación Android. La advertencia de Visual Studio corresponde a escritorio Windows y no impide desarrollar Android o web con Visual Studio Code.
