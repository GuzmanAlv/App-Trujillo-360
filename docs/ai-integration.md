# Integración de IA: candidatos y revisión v1

Nueva etapa: [cámara Android de simulación y mapa de operadores](camera-simulation.md).
Incluye sesiones efímeras y casos de prueba; requiere migración IA versión 2.

Estado: API de candidatos persistentes y bandeja Flutter de revisión implementadas.
La migración `017_ai_candidates.sql` debe aplicarse antes de iniciar esta versión.
No hay servidor de inferencia, cámaras conectadas, modelo entrenado ni evaluación
de precisión. El receptor WebSocket original se conserva para una futura conexión.

## Activar el piloto

Desde `backend`, ejecutar `python migrate.py` con las credenciales administrativas
locales y reiniciar la API. `/ready` exige `ai_version: 1`.
Las cámaras y sus permisos se provisionan administrativamente, no desde la app:

```sql
INSERT INTO trujillo.ai_cameras(id) VALUES ('camera-authorized-id');
INSERT INTO trujillo.ai_camera_access(camera_id, operator_id)
VALUES ('camera-authorized-id', '<UUID del operador>');
```

El usuario debe tener rol `operator` o `admin` y estar activo. Los administradores
acceden a todas las cámaras activas; los operadores solo a las asignadas. Desactivar
una cámara impide leer, registrar y revisar sus candidatos.

## API del piloto

Todos los endpoints requieren un token Firebase en `Authorization: Bearer ...`:

- `POST /operator/ai/candidates`: importa un candidato con el JSON v1 de abajo.
  Es un ingreso autenticado para el piloto, no un endpoint anónimo para cámaras.
- `GET /operator/ai/candidates?limit=50&before=123`: devuelve `items` y
  `nextCursor`. Usar ese cursor como `before` hasta recibir `null`. El orden es
  de recepción descendente, independiente de la fecha del video. Actualizar
  vuelve a consultar la primera página y permite recuperar la bandeja tras cerrar
  la app o perder la conexión. No hay suscripción en tiempo real todavía.
- `POST /operator/ai/candidates/{sequence}/decisions`: acepta
  `{"decision":"confirmed","reason":"Revisión realizada en el sistema de cámaras"}`
  o `discarded`. El motivo tiene entre 5 y 500 caracteres. Se guardan identidad y
  fecha del servidor; una decisión final no puede sobrescribirse.

Los candidatos son inmutables: reenviar el mismo ID y contenido es idempotente;
reutilizar el ID con otro contenido devuelve 409. Repetir una decisión idéntica
por el mismo operador también es idempotente. No se crean reportes ciudadanos,
incidentes públicos ni notificaciones al confirmar. La evidencia todavía debe
consultarse en el sistema autorizado de cámaras; no se sirven videos desde esta API.

Flutter usa estos endpoints en **Seguridad ciudadana → Cámaras / IA**, con botones
para actualizar, cargar anteriores y confirmar o descartar con motivo.

Pruebas: `python -m pytest -q`; `python verify_ai.py` verifica permisos reales,
RLS, deduplicación, paginación y decisiones contra PostgreSQL y revierte todos los
cambios. Requiere la base existente y credenciales administrativas. Si falta la
migración de IA, el verificador la aplica solo dentro de la transacción revertida.

## Contrato de inferencia y futura conexión en tiempo real

El servidor de inferencia procesa video fuera de Flutter y emite candidatos.
El backend debe autenticar al operador, autorizar el acceso a las cámaras y
entregar un ticket efímero para un WebSocket WSS. No colocar credenciales de
cámaras ni claves privadas dentro de la app.

Cada mensaje de texto del WebSocket contiene un objeto JSON:

```json
{
  "schemaVersion": 1,
  "type": "aggression_candidate",
  "id": "event-unique-id",
  "cameraId": "camera-authorized-id",
  "modelVersion": "model-version",
  "confidence": 0.82,
  "latitude": -8.1116,
  "longitude": -79.0288,
  "detectedAt": "2026-09-12T02:00:00Z"
}
```

Los identificadores y la versión del modelo son cadenas no vacías de hasta 200
caracteres. La confianza está entre 0 y 1; las coordenadas deben estar dentro de
sus rangos geográficos. La fecha incluye zona horaria. La confianza es una salida
del modelo, no una probabilidad garantizada de agresión.

`AiDetectionStore.attach(channel.stream)` acepta el stream de un canal creado
por `BackendClient.events(ticketUrl)`. El llamador debe esperar `channel.ready`
antes de adjuntarlo y cerrar `channel.sink` al abandonar la sesión. La bandeja
cancela su suscripción al desecharse; la propiedad del socket es del llamador.
La conexión no se activa en la aplicación hasta implementar autenticación y el
endpoint de tickets. No existe reconexión automática todavía.

El receptor descarta mensajes inválidos o de más de 16 384 caracteres y cuenta
los rechazos. Deduplica por ID dentro de la bandeja y conserva los 200 candidatos
más recientes. Es una vista temporal en memoria: no constituye historial de
auditoría y se pierde al cerrar la app. El servidor debe conservar el historial
y gestionar reenvíos; un ID representa un candidato inmutable.

La siguiente etapa debe conectar un productor de inferencia con credenciales y
permisos propios, añadir evidencia con acceso autorizado y tickets WebSocket.
La consulta paginada y las decisiones auditadas ya existen en la API del piloto.
Esta entrega no publica incidentes automáticamente.

Antes de activar alertas, evaluar el modelo con videos representativos del
entorno, medir falsos positivos y falsos negativos, y definir el proceso de
revisión humana. El umbral se configurará en el servidor tras esa evaluación.
