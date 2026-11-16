# Continuar Trujillo 360 en otra laptop

Estado actualizado el 16 de noviembre de 2026. Esta guía sustituye las notas del 3 de noviembre sobre Firebase y la supuesta RTX 4060.

## Obtener el proyecto

Repositorio: https://github.com/GuzmanAlv/App-Trujillo-360, rama compartida `main`.
El backend de Render despliega desde `codex/notificaciones-fcm`; ambas ramas se mantienen en el mismo commit.

```powershell
git clone https://github.com/GuzmanAlv/App-Trujillo-360.git
cd App-Trujillo-360
git switch main
```

Si ya tienes una copia, revisa `git status` antes de `git pull --ff-only origin main`. No uses `reset --hard` para resolver cambios ajenos.

## Estado funcional

- La app Flutter Android usa Google/Firebase y el backend `https://trujillo-360-api.onrender.com`. La app instalada no necesita cable ni laptop para reportar, recibir SOS o consultar información.
- `/ready` debe devolver `schema_version: 11`, `workflow_version: 1`, `push_version: 3` y `sos_version: 1`.
- Reportar guarda tipo, descripción, fotos, ubicación y hora del hecho. Ya no pide prioridad. El operador revisa el incidente; también puede quedar público por corroboración comunitaria según las reglas del servidor.
- SOS envía la ubicación como solicitud privada en Ayuda y avisa a operadores con notificaciones habilitadas. No hace una llamada ni confirma que se haya enviado personal.
- Las cuentas de operador ven Ayuda, Revisar reportes y Cámaras / IA. El servidor comprueba el rol en cada operación. Las cuentas ciudadanas no ven esa opción de avisos del operador.
- Los avisos FCM están configurados y el usuario confirmó recepción real. Para avisos ciudadanos según la ubicación actual, Android debe conceder notificaciones y ubicación “Permitir todo el tiempo”. La app muestra un aviso persistente mientras sigue la ubicación. El servidor descarta ubicaciones de más de 20 minutos.
- La zona fija ya no aparece en la configuración nueva. Al abrir una instalación anterior, la suscripción fija se desactiva y se debe activar “Incidentes cerca de mí” otra vez.
- La pantalla Cámaras / IA es una bandeja temporal de prueba. Todavía no hay celular transmisor, modelo entrenado, inferencia en vivo ni decisiones de cámara conectadas al backend. El plan es un celular dedicado como cámara; el equipo de análisis está por definir. La laptop actual tiene gráficos AMD integrados, no RTX 4060.

## Probar avisos en Android

1. Abrir Configuración → Notificaciones y activar “Incidentes cerca de mí”.
2. Pulsar Guardar. Si Android abre ajustes, elegir Ubicación → “Permitir todo el tiempo”; regresar y pulsar Guardar de nuevo. Conceder notificaciones cuando se solicite.
3. Comprobar que aparece “Alertas por ubicación activas” mientras el seguimiento está activo.
4. Con otra cuenta operadora, activar “Nuevos reportes para el operador”, crear un reporte de prueba y confirmar el flujo. Un incidente solo debe avisar a ciudadanos cuando esté público y cerca de una ubicación reciente.
5. Probar con la app en segundo plano y con cambios de red. La detención forzada de Android y la falta de Internet pueden impedir avisos; medir el retraso real en un teléfono.

## Compilar e instalar

Instalar Flutter, Android SDK y Java compatibles. Ejecutar `flutter doctor -v`. La clave restringida de Maps se configura localmente en `android/maps.properties` tomando `android/maps.properties.example` como referencia; no está en Git. Una firma Android diferente puede requerir registrar su huella SHA para Google Sign-In y Maps.

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64 --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. El APK está ignorado por Git: hay que compartirlo como archivo aparte. El modo release actual usa una firma debug de este equipo para pruebas, no una firma de Play Store. Un APK construido en otra laptop puede no instalarse encima del anterior sin la misma firma.

Para verificar código: `flutter analyze` y, desde `backend`, `.\.venv\Scripts\python.exe -m pytest tests -q`. Para usar el backend público no se necesitan los `.env` ni Python local. Las migraciones de base requieren credenciales administrativas privadas y no se ejecutan al arrancar Render.

No subir `.env`, `android/maps.properties`, `backend/.secrets/`, `.venv/`, tokens ni claves privadas.

## Texto para continuar con otro asistente

```text
Estoy continuando Trujillo 360 desde el repositorio https://github.com/GuzmanAlv/App-Trujillo-360, rama main. Lee README.md y docs/continuar-en-otra-laptop.md antes de cambiar código. La app ciudadana, SOS, operadores y FCM ya están integrados. Los avisos ciudadanos siguen la ubicación Android con permiso “Permitir todo el tiempo”; la zona fija anterior se desactiva al abrir la versión nueva. El backend público está en https://trujillo-360-api.onrender.com y Render despliega desde codex/notificaciones-fcm. Cámaras / IA aún no tiene transmisión ni modelo: se planea un celular dedicado como cámara y el equipo de análisis está por definir. No asumas que tenemos RTX 4060. No subas claves ni el APK a Git. Verifica primero el estado actual de Git y /ready.
```
