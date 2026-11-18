# SOS y llamadas de voz — piloto Android

## Flujo implementado

1. El ciudadano mantiene SOS pulsado durante tres segundos. Soltar, salir del botón o interrumpir la app cancela la pulsación. Requiere sesión y ubicación, igual que el SOS anterior.
2. El API guarda primero el SOS privado y avisa a los operadores por el FCM existente. No crea un incidente público.
3. La pantalla solicita permiso de micrófono y crea una sesión de llamada, con 90 segundos para aceptar. Si el permiso o LiveKit falla, el SOS sigue en Ayuda.
4. Un operador autorizado abre el SOS en Ayuda y pulsa **Aceptar llamada**. La asignación es manual: gana el primer operador que acepta. La transacción impide aceptar simultáneamente el mismo caso o estar en dos llamadas activas.
5. Solo el ciudadano y ese operador obtienen tokens temporales para la sala privada. Se conecta voz con controles de micrófono, altavoz y finalizar. No se transmite cámara ni se graba audio.
6. Finalizar registra el cierre y elimina la sala de LiveKit. El SOS y su historial permanecen para seguimiento, clasificación y revisión del operador.

El botón de volumen experimental conserva su SOS silencioso anterior. No inicia una llamada automáticamente.

## Activar después de revisar los cambios

La implementación local no modifica automáticamente Supabase ni Render.

1. Aplicar, con autorización del responsable, `backend/migrations/017_calls.sql` mediante `backend/migrate.py` con credenciales administrativas locales. La migración es aditiva; las credenciales administrativas nunca van al API. No ejecutar pruebas contra producción.
2. Publicar estos cambios en la rama que despliega Render (consultar la configuración del servicio; actualmente se documenta `codex/notificaciones-fcm`). Render instala `requirements.lock.txt`.
3. Conservar exclusivamente en el backend:
   - `LIVEKIT_URL`: URL `wss://…livekit.cloud` del proyecto.
   - `LIVEKIT_API_KEY`: identificador de la clave del mismo proyecto.
   - `LIVEKIT_API_SECRET`: secreto de esa clave.
   No son tokens de participante. No ponerlos en Flutter, Git, capturas, ni archivos públicos.
4. Desplegar el backend. `/ready` debe incluir `calls_version: 1`. Comprueba la presencia de la migración; no prueba conectividad ni validez de credenciales LiveKit.
5. Instalar la app nueva en ambos teléfonos:

   ```powershell
   flutter run --dart-define=MAPS_ENABLED=true --dart-define=BACKEND_URL=https://trujillo-360-api.onrender.com
   ```

6. Usar cuentas diferentes: ciudadano y operador autorizado en el servidor. Mantener ambas apps abiertas y permitir el micrófono. Iniciar SOS, abrir Ayuda desde el teléfono operador y aceptar. Probar voz en ambos sentidos, silenciar, altavoz y colgar desde cada lado.
7. Verificar que otro operador no pueda aceptar la llamada ya asignada, que una pulsación corta no envíe SOS y que una llamada sin respuesta conserve la solicitud. Probar también pérdida de red y permiso denegado.

## Alcance y límites

- Piloto en primer plano. Faltan timbre/pantalla de llamada entrante, CallKit/ConnectionService, servicio de micrófono en segundo plano y pruebas con pantalla bloqueada. La notificación existente abre el caso; no contesta por sí sola.
- Se consulta el estado cada tres segundos; no se garantiza tiempo de respuesta. Render dormido, red, permisos o ausencia de operadores pueden impedir la llamada. No sustituye un servicio de emergencias.
- La sesión aceptada caduca a los 30 minutos. Los clientes desconectan al detectar cierre/caducidad. El servidor marca caducidades cuando recibe acciones; falta un proceso de limpieza independiente para salas huérfanas y webhooks de desconexión.
- Los tokens duran 60 segundos y solo autorizan micrófono y recepción en una sala. Expirar un token no expulsa a participantes ya conectados. El cierre solicita eliminar la sala; no se debe prometer revocación instantánea frente a clientes modificados o tokens ya emitidos.
- Al finalizar se intenta detener la captura del micrófono, desconectar LiveKit y avisar al servidor por separado. La pantalla espera como máximo cuatro segundos y vuelve aunque alguna operación falle; en ese caso avisa que el cierre no se confirmó por completo. Cancelar antes de conectar no espera una desconexión de sala. Si la app se cierra abruptamente, queda el tiempo de caducidad como recuperación.
- Un SOS admite una sesión; tras finalizar o agotar el tiempo, iniciar un SOS nuevo para otra llamada. Una solicitud silenciosa sin sesión puede abrirse desde Ayuda por su ciudadano para solicitar voz.
- No hay asignación policial automática, confirmación de despacho ni publicación automática de incidentes.

## Verificación local

```powershell
flutter analyze
flutter test
cd backend
.venv/Scripts/python.exe -m pytest -q
$env:PG_TEST_BIN='C:/Program Files/PostgreSQL/18/bin'
.venv/Scripts/python.exe -m pytest tests/test_calls_database.py -q
```

La prueba PostgreSQL crea y detiene una instancia temporal independiente en loopback. Comprueba la función SQL real, permisos, expiración y dos operadores aceptando a la vez; no lee `.env` ni se conecta a Supabase. La prueba no reemplaza una llamada real entre dos teléfonos.

### Resultado de esta implementación

- APK Android debug compilada con Maps y el backend público configurados.
- `flutter analyze`: sin incidencias.
- Backend: 97 pruebas aprobadas, incluida la instancia PostgreSQL temporal. Tras los últimos ajustes de llamadas, las 9 pruebas específicas también aprobaron.
- Flutter: 10 pruebas de pulsación SOS, inicio y flujo integrado aprobadas.
- La suite Flutter completa presenta cuatro fallos previos en `community_incident_test.dart` (dos), `nearby_map_test.dart` y `unified_report_test.dart`. Se reprodujeron los mismos cuatro en una copia aislada del commit anterior, sin estos cambios.
- Pendiente: migración en Supabase, despliegue y comprobación de voz en dos dispositivos reales. No se han modificado datos remotos ni publicado secretos.
