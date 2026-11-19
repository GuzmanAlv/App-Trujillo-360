# Ruta al confirmar un SOS

Al confirmar correctamente un SOS, el operador regresa al mapa principal. La app
solicita su GPS actual y dibuja una ruta en vehículo hacia el punto del incidente
guardado en la ficha. Este punto puede haber sido corregido por el operador y no
se confunde con el GPS original del teléfono ciudadano. Se muestran distancia y
tiempo estimado; el mapa encuadra todo el recorrido.

La llamada activa continúa en una barra con micrófono, altavoz y colgar. No se
marca automáticamente «Unidad en camino»: esa declaración sigue siendo una
acción explícita del operador. Se puede actualizar o quitar la ruta del mapa.
No hay navegación giro a giro ni recálculo continuo en segundo plano.

## Configuración pendiente en Google y Render

1. Habilitar **Routes API** en el proyecto de Google Cloud con facturación activa.
2. Preparar una clave de servidor restringida a **Routes API**. No usar la clave
   de Maps SDK restringida al paquete Android y su firma. Si se restringe por IP,
   usar las direcciones de salida que correspondan al servicio de Render.
3. En Render → trujillo-360-api → Environment, agregar
   `GOOGLE_ROUTES_API_KEY` con la clave como secreto y desplegar el backend.
   Nunca incluirla en Dart, `--dart-define`, capturas, mensajes ni Git.
4. Compilar e instalar la app actualizada con `MAPS_ENABLED=true` y el backend
   público. No hace falta una nueva migración de base de datos.

La consulta usa Google Routes `DRIVE`, `TRAFFIC_AWARE_OPTIMAL` y alternativas;
elige la menor duración entre las rutas devueltas. Es una estimación con tráfico,
no una garantía de que siempre sea la ruta más rápida. Las consultas pueden
generar consumo. Se consulta al confirmar y al pulsar actualizar; el backend
limita a una consulta por operador/caso cada 10 segundos en cada proceso.

Si falta la clave, GPS, conectividad o una ruta válida, el SOS **sigue confirmado**.
La app muestra el problema y permite reintentar sin crear otro incidente.
El endpoint verifica sesión, rol y asignación mediante `sos_case_read`, rechaza
casos sin confirmar o resueltos y obtiene el destino exclusivamente de la base.
No almacena la ubicación de origen ni la geometría calculada en la base.

## Prueba en dos celulares

1. Ciudadano solicita SOS; operador toma la llamada y corrige el punto del hecho
   si corresponde. Confirmar SOS durante la conversación.
2. Comprobar regreso al mapa principal, audio continuo y barra compacta funcional.
3. Conceder GPS al operador y verificar la línea sobre calles, sus extremos y ETA.
4. Repetir con la llamada terminada: confirmar también vuelve al mapa y calcula.
5. Probar GPS desactivado, API sin configurar y sin conexión: no duplicar el SOS;
   mostrar aviso y permitir actualizar la ruta tras corregir el problema.
6. Otra cuenta ciudadana y otro operador no asignado no deben poder consultar
   esta ruta privada.

Referencia: [Google Routes computeRoutes](https://developers.google.com/maps/documentation/routes/compute_route_directions).
