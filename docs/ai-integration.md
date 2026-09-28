# Integración de IA: contrato propuesto v1

Estado: receptor Flutter y bandeja temporal implementados. No hay servidor de
inferencia, cámaras conectadas, modelo entrenado ni evaluación de precisión.

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

La siguiente etapa del servidor debe añadir consulta paginada de candidatos,
recuperación tras desconexión, evidencia con acceso autorizado y decisiones de
operadores registradas con identidad y fecha. Confirmar o descartar requiere
autorización del servidor. Esta entrega no publica incidentes automáticamente.

Antes de activar alertas, evaluar el modelo con videos representativos del
entorno, medir falsos positivos y falsos negativos, y definir el proceso de
revisión humana. El umbral se configurará en el servidor tras esa evaluación.
